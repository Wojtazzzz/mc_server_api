defmodule McServerApi.Ping.Query do
  @moduledoc """
  The UDP Query protocol (GameSpy 4), answered only by servers with
  `enable-query=true`. It reveals what the status ping does not: server software,
  plugin list, world name and game type.

  See https://minecraft.wiki/w/Query
  """

  import Bitwise

  @magic <<0xFE, 0xFD>>
  @type_handshake 0x09
  @type_stat 0x00
  # Fixed padding that turns a basic stat request into a full stat request.
  @full_stat_padding <<0, 0, 0, 0>>
  @max_plugins 300
  @max_players 100

  @type result :: %{
          software: String.t() | nil,
          plugins: [String.t()],
          map: String.t() | nil,
          game_type: String.t() | nil,
          version: String.t() | nil,
          host_port: :inet.port_number() | nil,
          players: [String.t()]
        }

  @spec query(:inet.ip_address(), :inet.port_number(), pos_integer()) ::
          {:ok, result()} | {:error, term()}
  def query(ip, port, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout
    session = :rand.uniform(0x7FFFFFFF) &&& 0x0F0F0F0F

    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])

    try do
      with :ok <- :gen_udp.send(socket, ip, port, handshake_request(session)),
           {:ok, response} <- receive_from(socket, deadline),
           {:ok, token} <- parse_handshake(response, session),
           :ok <- :gen_udp.send(socket, ip, port, full_stat_request(session, token)),
           {:ok, response} <- receive_from(socket, deadline) do
        parse_full_stat(response, session)
      end
    after
      :gen_udp.close(socket)
    end
  end

  @spec handshake_request(integer()) :: binary()
  def handshake_request(session), do: @magic <> <<@type_handshake, session::32>>

  @spec full_stat_request(integer(), integer()) :: binary()
  def full_stat_request(session, token),
    do: @magic <> <<@type_stat, session::32, token::signed-32>> <> @full_stat_padding

  @spec parse_handshake(binary(), integer()) :: {:ok, integer()} | {:error, atom()}
  def parse_handshake(<<@type_handshake, session::32, token::binary>>, session) do
    case token |> String.trim_trailing(<<0>>) |> Integer.parse() do
      {value, ""} -> {:ok, value}
      _ -> {:error, :invalid_token}
    end
  end

  def parse_handshake(_response, _session), do: {:error, :invalid_handshake}

  @doc """
  Parses a full stat response: a padding marker, null-separated key/value pairs,
  another marker, then null-separated player names.
  """
  @spec parse_full_stat(binary(), integer()) :: {:ok, result()} | {:error, atom()}
  def parse_full_stat(<<@type_stat, session::32, "splitnum", 0, 0x80, 0, rest::binary>>, session) do
    case :binary.split(rest, <<0, 0, 1, "player_", 0, 0>>) do
      [pairs, players] -> {:ok, build(key_values(pairs), names(players))}
      [pairs] -> {:ok, build(key_values(pairs), [])}
    end
  end

  def parse_full_stat(_response, _session), do: {:error, :invalid_stat}

  defp key_values(binary) do
    binary
    |> :binary.split(<<0>>, [:global])
    |> Enum.chunk_every(2, 2, :discard)
    |> Map.new(fn [key, value] -> {key, latin1_to_utf8(value)} end)
  end

  defp names(binary) do
    binary
    |> :binary.split(<<0>>, [:global])
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&latin1_to_utf8/1)
    |> Enum.take(@max_players)
  end

  # "Paper on 1.21.4: LuckPerms 5.4.1; EssentialsX 2.20.1" — software before the colon, plugins after.
  defp build(values, players) do
    {software, plugins} = split_plugins(values["plugins"])

    %{
      software: software,
      plugins: plugins,
      map: blank_to_nil(values["map"]),
      game_type: blank_to_nil(values["gametype"]),
      version: blank_to_nil(values["version"]),
      host_port: integer_or_nil(values["hostport"]),
      players: players
    }
  end

  defp split_plugins(nil), do: {nil, []}

  defp split_plugins(text) do
    case String.split(text, ":", parts: 2) do
      [software, plugins] ->
        {blank_to_nil(String.trim(software)),
         plugins
         |> String.split(";")
         |> Enum.map(&String.trim/1)
         |> Enum.reject(&(&1 == ""))
         |> Enum.take(@max_plugins)}

      [software] ->
        {blank_to_nil(String.trim(software)), []}
    end
  end

  # Query strings are not guaranteed to be UTF-8.
  defp latin1_to_utf8(value) do
    if String.valid?(value), do: value, else: :unicode.characters_to_binary(value, :latin1)
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(value), do: if(String.trim(value) == "", do: nil, else: value)

  defp integer_or_nil(nil), do: nil

  defp integer_or_nil(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp receive_from(socket, deadline) do
    case max(deadline - System.monotonic_time(:millisecond), 0) do
      0 ->
        {:error, :timeout}

      timeout ->
        case :gen_udp.recv(socket, 0, timeout) do
          {:ok, {_address, _port, data}} -> {:ok, data}
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
