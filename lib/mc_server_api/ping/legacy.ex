defmodule McServerApi.Ping.Legacy do
  @moduledoc """
  Server List Ping used before 1.7 (0xFE 0x01). Tried only when a server does not
  speak the modern protocol, so very old servers are still reported as online.
  """

  alias McServerApi.Ping.TextFormat

  @max_length 4_096

  @spec ping(:inet.ip_address(), :inet.port_number(), pos_integer()) ::
          {:ok, map()} | {:error, term()}
  def ping(ip, port, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    with {:ok, socket} <- :gen_tcp.connect(ip, port, [:binary, active: false], timeout) do
      try do
        with :ok <- :gen_tcp.send(socket, <<0xFE, 0x01>>),
             {:ok, response} <- receive_all(socket, <<>>, deadline) do
          parse(response)
        end
      after
        :gen_tcp.close(socket)
      end
    end
  end

  @doc """
  Parses the kick packet the server answers with: `0xFF`, a UTF-16BE length and text that is
  either `§1\\0protocol\\0version\\0motd\\0online\\0max` (1.4–1.6) or `motd§online§max` (older).
  """
  @spec parse(binary()) :: {:ok, map()} | {:error, atom()}
  def parse(<<0xFF, length::16, text::binary-size(length * 2), _rest::binary>>) do
    text = :unicode.characters_to_binary(text, {:utf16, :big})

    case String.split(text, <<0>>) do
      ["§1", protocol, version, motd, online, max] ->
        {:ok, result(motd, online, max, version, integer(protocol))}

      [_single] ->
        case String.split(text, "§") |> Enum.take(-3) do
          [motd, online, max] -> {:ok, result(motd, online, max, nil, nil)}
          _ -> {:error, :invalid_legacy_response}
        end

      _ ->
        {:error, :invalid_legacy_response}
    end
  end

  def parse(_response), do: {:error, :invalid_legacy_response}

  defp result(motd, online, max, version, protocol) do
    %{
      version: %{
        name: version,
        name_clean: version && TextFormat.strip_codes(version),
        protocol: protocol
      },
      players: %{online: integer(online), max: integer(max), sample: []},
      motd: TextFormat.render(motd)
    }
  end

  defp receive_all(socket, buffer, deadline) do
    case buffer do
      <<0xFF, length::16, rest::binary>> when byte_size(rest) >= length * 2 ->
        {:ok, buffer}

      _ when byte_size(buffer) > @max_length ->
        {:error, :response_too_large}

      _ ->
        timeout = max(deadline - System.monotonic_time(:millisecond), 0)

        case :gen_tcp.recv(socket, 0, timeout) do
          {:ok, data} -> receive_all(socket, buffer <> data, deadline)
          {:error, :closed} when buffer != <<>> -> {:ok, buffer}
          error -> error
        end
    end
  end

  defp integer(value) do
    case Integer.parse(value || "") do
      {integer, ""} -> integer
      _ -> nil
    end
  end
end
