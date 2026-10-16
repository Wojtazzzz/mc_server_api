defmodule McServerApi.Ping.ClientTest do
  use ExUnit.Case, async: true

  alias McServerApi.Ping.Client
  alias McServerApi.Ping.Protocol

  import OpenApiSpex.TestAssertions

  @no_extras [query: false, bedrock: false, network: false, blocked: false]

  @status %{
    "version" => %{"name" => "1.21.4", "protocol" => 769},
    "players" => %{"online" => 7, "max" => 50, "sample" => [%{"name" => "Steve"}]},
    "description" => %{"text" => "§aTest server"}
  }

  # A minimal fake server: answers the status request with `response`, then echoes the ping.
  defp start_server(response, opts \\ []) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true])
    {:ok, port} = :inet.port(listen)
    test_pid = self()

    spawn_link(fn ->
      {:ok, socket} = :gen_tcp.accept(listen)
      {:ok, request} = read_packets(socket, <<>>, 2)
      send(test_pid, {:handshake, request})

      unless opts[:silent] do
        :gen_tcp.send(socket, response)

        unless opts[:no_pong] do
          {:ok, [{0x01, payload}]} = read_packets(socket, <<>>, 1)
          :gen_tcp.send(socket, Protocol.packet(0x01, payload))
        end
      end

      Process.sleep(opts[:hold] || 50)
      :gen_tcp.close(socket)
    end)

    port
  end

  defp read_packets(_socket, _buffer, 0), do: {:ok, []}

  defp read_packets(socket, buffer, count) do
    case Protocol.decode_packet(buffer) do
      {:ok, id, payload, rest} ->
        {:ok, packets} = read_packets(socket, rest, count - 1)
        {:ok, [{id, payload} | packets]}

      :incomplete ->
        {:ok, data} = :gen_tcp.recv(socket, 0, 1_000)
        read_packets(socket, buffer <> data, count)
    end
  end

  defp status_response(status),
    do: Protocol.packet(0x00, Protocol.encode_string(Jason.encode!(status)))

  test "reads the status and measures latency" do
    port = start_server(status_response(@status))

    assert {:ok, data} = Client.status("127.0.0.1:#{port}", @no_extras)
    assert data.online
    assert data.players.online == 7
    assert data.players.max == 50
    assert data.players.sample == [%{name: "Steve", id: nil}]

    assert data.version == %{
             name: "1.21.4",
             name_clean: "1.21.4",
             protocol: 769,
             protocol_name: "1.21.4",
             range: %{oldest: "1.21", newest: "1.21"}
           }

    assert data.auth == %{mode: :unknown, source: nil, disconnect_reason: nil}
    assert data.links == %{discord: [], websites: []}
    refute data.legacy
    assert data.motd.clean == ["Test server"]
    assert data.motd.raw == "§r§aTest server"
    assert data.ip == "127.0.0.1"
    assert data.port == port
    assert data.srv == nil
    assert is_integer(data.timings.latency_ms)
    assert is_integer(data.timings.total_ms)

    # The API returns exactly this struct, so it must match the documented schema.
    api_json = data |> Map.from_struct() |> Jason.encode!() |> Jason.decode!()
    assert_schema(api_json, "StatusResponse", McServerApiWeb.ApiSpec.spec())

    assert_received {:handshake, [{0x00, handshake}, {0x00, ""}]}
    assert {:ok, -1, rest} = Protocol.decode_varint(handshake)
    assert {:ok, "127.0.0.1", <<^port::16, 1>>} = Protocol.decode_string(rest)
  end

  test "adds software and plugins when the server answers the UDP query" do
    port = start_server(status_response(@status))
    {:ok, udp} = :gen_udp.open(port, [:binary, active: false])

    spawn_link(fn ->
      {:ok, {address, client_port, <<0xFE, 0xFD, 0x09, session::32>>}} =
        :gen_udp.recv(udp, 0, 2_000)

      :gen_udp.send(udp, address, client_port, <<0x09, session::32, "9513307", 0>>)

      {:ok, {address, client_port, <<0xFE, 0xFD, 0x00, ^session::32, 9_513_307::32, 0::32>>}} =
        :gen_udp.recv(udp, 0, 2_000)

      stat =
        <<0x00, session::32, "splitnum", 0, 0x80, 0>> <>
          "plugins\0Paper on 1.21.4: LuckPerms 5.4; EssentialsX 2.20\0map\0world\0gametype\0SMP\0" <>
          <<0, 1, "player_", 0, 0>> <> "Steve\0Alex\0\0"

      :gen_udp.send(udp, address, client_port, stat)
    end)

    assert {:ok, data} =
             Client.status("127.0.0.1:#{port}", bedrock: false, network: false, blocked: false)

    assert data.software == "Paper"
    assert data.query.plugins == ["LuckPerms 5.4", "EssentialsX 2.20"]
    assert data.query.map == "world"
    assert data.query.players == ["Steve", "Alex"]
  end

  test "still returns the status when the server does not answer the ping" do
    port = start_server(status_response(@status), no_pong: true)

    assert {:ok, %{players: %{online: 7}, timings: %{latency_ms: nil}}} =
             Client.status("127.0.0.1:#{port}", @no_extras)
  end

  test "handles a response split across many TCP segments" do
    response =
      status_response(
        Map.put(@status, "favicon", "data:image/png;base64," <> String.duplicate("A", 20_000))
      )

    port = start_server(response)

    assert {:ok, %{favicon: "data:image/png;base64," <> _icon}} =
             Client.status("127.0.0.1:#{port}", @no_extras)
  end

  test "times out on a server that never answers" do
    port = start_server(<<>>, silent: true, hold: 1_000)

    assert {:error, :timeout} = Client.status("127.0.0.1:#{port}", [timeout: 200] ++ @no_extras)
  end

  test "rejects a server announcing an oversized packet" do
    port = start_server(Protocol.encode_varint(Protocol.max_packet_size() + 1), no_pong: true)

    assert {:error, :packet_too_large} = Client.status("127.0.0.1:#{port}", @no_extras)
  end

  test "reports a refused connection as an error, and as offline for the page" do
    {:ok, listen} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(listen)
    :gen_tcp.close(listen)

    assert {:error, :econnrefused} = Client.status("127.0.0.1:#{port}", @no_extras)
    assert %{online: false} = Client.call("127.0.0.1:#{port}")
  end

  test "parses host, port and IPv6 addresses" do
    assert Client.parse_address("Play.Example.PL") == {:ok, "play.example.pl", nil}
    assert Client.parse_address("example.pl:25570") == {:ok, "example.pl", 25_570}
    assert Client.parse_address("[::1]:25565") == {:ok, "::1", 25_565}
    assert Client.parse_address("example.pl:99999") == {:error, :invalid_address}
    assert Client.parse_address("http://example.pl") == {:error, :invalid_address}
    assert Client.parse_address("") == {:error, :invalid_address}
  end
end
