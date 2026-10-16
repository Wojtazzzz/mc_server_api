defmodule McServerApi.Ping.UdpParsingTest do
  use ExUnit.Case, async: true

  alias McServerApi.Ping.Bedrock
  alias McServerApi.Ping.Query

  @magic <<0x00, 0xFF, 0xFF, 0x00, 0xFE, 0xFE, 0xFE, 0xFE, 0xFD, 0xFD, 0xFD, 0xFD, 0x12, 0x34,
           0x56, 0x78>>

  test "parses a Bedrock pong" do
    id = "MCPE;§aMy Server;766;1.21.40;12;100;123456789;Second line;Survival;1;19132;19133;"
    pong = <<0x1C, 0::64, 42::64>> <> @magic <> <<byte_size(id)::16>> <> id

    assert {:ok, result} = Bedrock.parse(pong)
    assert result.edition == "Bedrock"
    assert result.motd == ["My Server", "Second line"]
    assert result.version == "1.21.40"
    assert result.protocol == 766
    assert result.players == %{online: 12, max: 100}
    assert result.game_mode == "Survival"
  end

  test "rejects anything that is not a Bedrock pong" do
    assert Bedrock.parse(<<0x1C, 1, 2, 3>>) == {:error, :invalid_pong}
  end

  test "parses the Query handshake token and a full stat without plugins" do
    assert Query.parse_handshake(<<0x09, 7::32, "-1234", 0>>, 7) == {:ok, -1234}
    assert Query.parse_handshake(<<0x09, 8::32, "1", 0>>, 7) == {:error, :invalid_handshake}

    stat = <<0x00, 7::32, "splitnum", 0, 0x80, 0>> <> "plugins\0\0map\0lobby\0hostport\025565\0"

    assert {:ok, %{software: nil, plugins: [], map: "lobby", host_port: 25_565, players: []}} =
             Query.parse_full_stat(stat, 7)
  end
end
