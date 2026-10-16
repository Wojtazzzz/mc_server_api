defmodule McServerApi.Ping.Login do
  @moduledoc """
  Finds out whether a server needs a premium (paid) account by starting a login
  and reading the server's first answer:

    * Encryption Request — online mode, a Mojang/Microsoft account is required,
    * Set Compression or Login Success — offline mode ("no premium"),
    * Disconnect — the server said why (whitelist, anti-bot, wrong version…).

  The connection is closed right after that answer, before joining the game.
  Servers still log it as a connection attempt, which is why this check is opt-in.
  """

  alias McServerApi.Ping.Protocol
  alias McServerApi.Ping.TextFormat

  @fallback_protocol 47
  # Most servers and proxies accept it; tried when the advertised protocol gets rejected.
  @common_protocol 769

  @type result :: %{
          mode: :online | :offline | :unknown,
          protocol: integer(),
          disconnect_reason: String.t() | nil
        }

  @doc """
  Tries the protocol the server advertised and, if the server disconnects with a reason
  (often "unsupported client version" from proxies), once more with a widely supported one.
  """
  @spec detect(
          :inet.ip_address(),
          :inet.port_number(),
          String.t(),
          integer() | nil,
          pos_integer()
        ) ::
          {:ok, result()} | {:error, term()}
  def detect(ip, port, host, protocol, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    case probe(ip, port, host, protocol, timeout) do
      {:ok, %{mode: :unknown, protocol: tried}} = first when tried != @common_protocol ->
        remaining = deadline - System.monotonic_time(:millisecond)

        with true <- remaining > 0,
             {:ok, %{mode: mode}} = second when mode != :unknown <-
               probe(ip, port, host, @common_protocol, remaining) do
          second
        else
          _ -> first
        end

      result ->
        result
    end
  end

  @spec probe(:inet.ip_address(), :inet.port_number(), String.t(), integer() | nil, pos_integer()) ::
          {:ok, result()} | {:error, term()}
  def probe(ip, port, host, protocol, timeout) do
    protocol = if is_integer(protocol) and protocol > 0, do: protocol, else: @fallback_protocol
    deadline = System.monotonic_time(:millisecond) + timeout

    with {:ok, socket} <- :gen_tcp.connect(ip, port, [:binary, active: false], timeout) do
      try do
        request = Protocol.handshake(host, port, protocol, 2) <> login_start(protocol)

        with :ok <- :gen_tcp.send(socket, request),
             {:ok, id, payload} <- receive_packet(socket, <<>>, deadline) do
          {:ok, %{interpret(id, payload) | protocol: protocol}}
        end
      after
        :gen_tcp.close(socket)
      end
    end
  end

  @doc "Login Start; its fields changed in 1.19, 1.19.1, 1.19.3 and 1.20.2."
  @spec login_start(integer(), String.t()) :: binary()
  def login_start(protocol, name \\ random_name()) do
    uuid = :crypto.strong_rand_bytes(16)

    payload =
      cond do
        protocol >= 764 -> Protocol.encode_string(name) <> uuid
        protocol >= 761 -> Protocol.encode_string(name) <> <<1>> <> uuid
        protocol == 760 -> Protocol.encode_string(name) <> <<0, 1>> <> uuid
        protocol == 759 -> Protocol.encode_string(name) <> <<0>>
        true -> Protocol.encode_string(name)
      end

    Protocol.packet(0x00, payload)
  end

  @spec interpret(integer(), binary()) :: result()
  def interpret(0x01, _payload), do: %{mode: :online, protocol: 0, disconnect_reason: nil}

  def interpret(id, _payload) when id in [0x02, 0x03],
    do: %{mode: :offline, protocol: 0, disconnect_reason: nil}

  def interpret(0x00, payload) do
    reason =
      case Protocol.decode_string(payload) do
        {:ok, text, _rest} ->
          text = (match?({:ok, _}, Jason.decode(text)) && Jason.decode!(text)) || text

          text
          |> TextFormat.render()
          |> Map.fetch!(:clean)
          |> Enum.join("\n")
          |> String.slice(0, 500)

        _ ->
          nil
      end

    %{mode: :unknown, protocol: 0, disconnect_reason: reason}
  end

  def interpret(_id, _payload), do: %{mode: :unknown, protocol: 0, disconnect_reason: nil}

  defp random_name, do: "Ping" <> (:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower))

  defp receive_packet(socket, buffer, deadline) do
    case Protocol.decode_packet(buffer) do
      {:ok, id, payload, _rest} ->
        {:ok, id, payload}

      :incomplete ->
        timeout = max(deadline - System.monotonic_time(:millisecond), 0)

        with {:ok, data} <- :gen_tcp.recv(socket, 0, timeout) do
          receive_packet(socket, buffer <> data, deadline)
        end

      error ->
        error
    end
  end
end
