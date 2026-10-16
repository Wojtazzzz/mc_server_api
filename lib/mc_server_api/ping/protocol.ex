defmodule McServerApi.Ping.Protocol do
  @moduledoc """
  Encoding and decoding of the Minecraft Java Edition Server List Ping packets.

  Only the handful of packets the status handshake needs are covered:
  handshake, status request, status response, ping and pong.
  See https://minecraft.wiki/w/Java_Edition_protocol/Server_List_Ping
  """

  import Bitwise

  # The status response is JSON with an optional base64 favicon; anything larger is not a real server.
  @max_packet_size 1_048_576

  @doc "Largest packet accepted from a server, in bytes."
  @spec max_packet_size() :: pos_integer()
  def max_packet_size, do: @max_packet_size

  @doc """
  Encodes a VarInt. Negative numbers are written as their 32-bit two's complement,
  as the protocol expects (e.g. protocol version -1).
  """
  @spec encode_varint(integer()) :: binary()
  def encode_varint(value) when value < 0, do: encode_varint(value &&& 0xFFFFFFFF)
  def encode_varint(value) when value < 0x80, do: <<value>>

  def encode_varint(value),
    do: <<(value &&& 0x7F) ||| 0x80>> <> encode_varint(value >>> 7)

  @doc """
  Decodes a VarInt from the start of `binary`.

  Returns `{:ok, value, rest}`, `:incomplete` when more bytes are needed, or
  `{:error, :varint_too_long}` for more than five bytes.
  """
  @spec decode_varint(binary()) ::
          {:ok, integer(), binary()} | :incomplete | {:error, :varint_too_long}
  def decode_varint(binary), do: decode_varint(binary, 0, 0)

  defp decode_varint(_binary, 5, _acc), do: {:error, :varint_too_long}
  defp decode_varint(<<>>, _position, _acc), do: :incomplete

  defp decode_varint(<<byte, rest::binary>>, position, acc) do
    acc = acc ||| (byte &&& 0x7F) <<< (7 * position)

    if (byte &&& 0x80) == 0 do
      {:ok, to_signed_32(acc), rest}
    else
      decode_varint(rest, position + 1, acc)
    end
  end

  defp to_signed_32(value) when value >= 0x80000000, do: value - 0x100000000
  defp to_signed_32(value), do: value

  @doc "Encodes a length-prefixed UTF-8 string."
  @spec encode_string(String.t()) :: binary()
  def encode_string(string), do: encode_varint(byte_size(string)) <> string

  @doc "Decodes a length-prefixed UTF-8 string."
  @spec decode_string(binary()) :: {:ok, String.t(), binary()} | {:error, atom()}
  def decode_string(binary) do
    with {:ok, length, rest} when length >= 0 <- decode_varint(binary),
         <<string::binary-size(length), rest::binary>> <- rest do
      {:ok, string, rest}
    else
      :incomplete -> {:error, :truncated_string}
      {:ok, _negative, _rest} -> {:error, :invalid_string_length}
      {:error, reason} -> {:error, reason}
      _short -> {:error, :truncated_string}
    end
  end

  @doc "Wraps a payload into a length-prefixed packet with the given packet id."
  @spec packet(non_neg_integer(), binary()) :: binary()
  def packet(id, payload) do
    body = encode_varint(id) <> payload
    encode_varint(byte_size(body)) <> body
  end

  @doc """
  Handshake. `next_state` 1 asks for the status, 2 starts a login.
  Protocol version -1 asks the server to answer regardless of the client version.
  """
  @spec handshake(String.t(), :inet.port_number(), integer(), 1 | 2) :: binary()
  def handshake(host, port, protocol_version \\ -1, next_state \\ 1) do
    packet(
      0x00,
      encode_varint(protocol_version) <>
        encode_string(host) <> <<port::16>> <> encode_varint(next_state)
    )
  end

  @spec status_request() :: binary()
  def status_request, do: packet(0x00, <<>>)

  @spec ping(integer()) :: binary()
  def ping(payload), do: packet(0x01, <<payload::signed-64>>)

  @doc """
  Takes one complete packet off the front of `buffer`.

  Returns `{:ok, id, payload, rest}`, `:incomplete` when the packet has not fully
  arrived yet, or `{:error, reason}` when the data cannot be a valid packet.
  """
  @spec decode_packet(binary()) ::
          {:ok, integer(), binary(), binary()} | :incomplete | {:error, atom()}
  def decode_packet(buffer) do
    case decode_varint(buffer) do
      {:ok, length, _rest} when length <= 0 ->
        {:error, :invalid_packet_length}

      {:ok, length, _rest} when length > @max_packet_size ->
        {:error, :packet_too_large}

      {:ok, length, rest} when byte_size(rest) < length ->
        :incomplete

      {:ok, length, rest} ->
        <<body::binary-size(length), remaining::binary>> = rest

        case decode_varint(body) do
          {:ok, id, payload} -> {:ok, id, payload, remaining}
          _invalid -> {:error, :invalid_packet_id}
        end

      other ->
        other
    end
  end
end
