defmodule McServerApi.Ping.ProtocolTest do
  use ExUnit.Case, async: true

  alias McServerApi.Ping.Protocol

  describe "VarInt" do
    test "round-trips values across the whole 32-bit range" do
      for value <- [
            0,
            1,
            127,
            128,
            255,
            300,
            25_565,
            2_097_151,
            2_147_483_647,
            -1,
            -2_147_483_648
          ] do
        assert {:ok, ^value, ""} = value |> Protocol.encode_varint() |> Protocol.decode_varint()
      end
    end

    test "encodes the reference examples from the protocol documentation" do
      assert Protocol.encode_varint(0) == <<0x00>>
      assert Protocol.encode_varint(128) == <<0x80, 0x01>>
      assert Protocol.encode_varint(25_565) == <<0xDD, 0xC7, 0x01>>
      assert Protocol.encode_varint(-1) == <<0xFF, 0xFF, 0xFF, 0xFF, 0x0F>>
    end

    test "asks for more bytes when the VarInt is cut off" do
      assert Protocol.decode_varint(<<0x80>>) == :incomplete
      assert Protocol.decode_varint(<<>>) == :incomplete
    end

    test "rejects a VarInt longer than five bytes" do
      assert Protocol.decode_varint(<<0x80, 0x80, 0x80, 0x80, 0x80, 0x01>>) ==
               {:error, :varint_too_long}
    end
  end

  describe "packets" do
    test "builds the handshake for the status state" do
      handshake = Protocol.handshake("localhost", 25_565)

      assert {:ok, 0x00, payload, ""} = Protocol.decode_packet(handshake)
      assert {:ok, -1, rest} = Protocol.decode_varint(payload)
      assert {:ok, "localhost", <<25_565::16, 1>>} = Protocol.decode_string(rest)
    end

    test "decodes a packet and keeps what follows it" do
      buffer = Protocol.packet(0x01, <<42::signed-64>>) <> <<1, 2>>

      assert {:ok, 0x01, <<42::signed-64>>, <<1, 2>>} = Protocol.decode_packet(buffer)
    end

    test "waits for the rest of a packet that has not fully arrived" do
      packet = Protocol.packet(0x00, Protocol.encode_string("{}"))

      assert Protocol.decode_packet(binary_part(packet, 0, byte_size(packet) - 1)) == :incomplete
    end

    test "refuses packets announcing an absurd size" do
      oversized = Protocol.encode_varint(Protocol.max_packet_size() + 1)

      assert Protocol.decode_packet(oversized) == {:error, :packet_too_large}
      assert Protocol.decode_packet(<<0x00>>) == {:error, :invalid_packet_length}
    end

    test "reports a string shorter than its declared length" do
      assert Protocol.decode_string(<<10, "abc">>) == {:error, :truncated_string}
    end
  end
end
