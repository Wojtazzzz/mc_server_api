defmodule McServerApi.Ping.Bedrock do
  @moduledoc """
  Bedrock Edition status over RakNet "unconnected ping" (UDP). A Java server that
  answers it (usually through Geyser) can be joined from phones and consoles.
  """

  # RakNet's fixed "offline message" marker.
  @magic <<0x00, 0xFF, 0xFF, 0x00, 0xFE, 0xFE, 0xFE, 0xFE, 0xFD, 0xFD, 0xFD, 0xFD, 0x12, 0x34,
           0x56, 0x78>>
  @unconnected_ping 0x01
  @unconnected_pong 0x1C

  @default_port 19_132

  @type result :: %{
          edition: String.t(),
          motd: [String.t()],
          version: String.t() | nil,
          protocol: integer() | nil,
          players: %{online: integer() | nil, max: integer() | nil},
          game_mode: String.t() | nil,
          port: :inet.port_number()
        }

  @spec default_port() :: :inet.port_number()
  def default_port, do: @default_port

  @spec ping(:inet.ip_address(), :inet.port_number(), pos_integer()) ::
          {:ok, result()} | {:error, term()}
  def ping(ip, port, timeout) do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])

    try do
      with :ok <- :gen_udp.send(socket, ip, port, request()),
           {:ok, {_address, _port, response}} <- :gen_udp.recv(socket, 0, timeout),
           {:ok, result} <- parse(response) do
        {:ok, %{result | port: port}}
      end
    after
      :gen_udp.close(socket)
    end
  end

  @spec request() :: binary()
  def request do
    <<@unconnected_ping, System.system_time(:millisecond)::64>> <>
      @magic <> <<:rand.uniform(0x7FFFFFFFFFFFFFFF)::64>>
  end

  @doc """
  Parses the pong. Its server id string looks like
  `MCPE;Line 1;766;1.21.40;12;100;12345;Line 2;Survival;1;19132;19133;`.
  """
  @spec parse(binary()) :: {:ok, result()} | {:error, atom()}
  def parse(
        <<@unconnected_pong, _time::64, _server_guid::64, @magic, length::16,
          id::binary-size(length), _rest::binary>>
      ) do
    case String.split(id, ";") do
      [edition, line1 | fields] when edition in ["MCPE", "MCEE"] ->
        [protocol, version, online, max, _server_id, line2, game_mode | _] =
          fields ++ List.duplicate(nil, 7)

        {:ok,
         %{
           edition: if(edition == "MCEE", do: "Education", else: "Bedrock"),
           motd:
             [line1, line2]
             |> Enum.reject(&(&1 in [nil, ""]))
             |> Enum.map(&McServerApi.Ping.TextFormat.strip_codes/1),
           version: version,
           protocol: to_integer(protocol),
           players: %{online: to_integer(online), max: to_integer(max)},
           game_mode: game_mode,
           port: @default_port
         }}

      _ ->
        {:error, :invalid_pong}
    end
  end

  def parse(_response), do: {:error, :invalid_pong}

  defp to_integer(nil), do: nil

  defp to_integer(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end
end
