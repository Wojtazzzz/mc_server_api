defmodule McServerApi.Ping.ExtrasTest do
  use ExUnit.Case, async: true

  alias McServerApi.Ping.BlockedServers
  alias McServerApi.Ping.Legacy
  alias McServerApi.Ping.Login
  alias McServerApi.Ping.Protocol
  alias McServerApi.Ping.Status
  alias McServerApi.Ping.Versions

  describe "versions" do
    test "names release protocols and leaves unknown ones empty" do
      assert Versions.protocol_name(47) == "1.8–1.8.9"
      assert Versions.protocol_name(769) == "1.21.4"
      assert Versions.protocol_name(999_999) == nil
    end

    test "reads the advertised version range" do
      assert Versions.range("Velocity 1.7.2-26.3") == %{oldest: "1.7", newest: "26.3"}
      assert Versions.range("Requires MC 1.8 / 1.21") == %{oldest: "1.8", newest: "1.21"}
      assert Versions.range("1.7.x - 26.x") == %{oldest: "1.7", newest: "26"}
      assert Versions.range("-50% na rangi, 200 slotów") == nil
    end
  end

  test "finds Discord invites and websites in the MOTD" do
    assert Status.links([
             "Strona WWW: www.craftmc.pl",
             "Dołącz na discorda dc.artmc.pl lub discord.gg/AbC123"
           ]) ==
             %{discord: ["dc.artmc.pl", "discord.gg/abc123"], websites: ["www.craftmc.pl"]}
  end

  test "guesses online or offline mode from player UUID versions" do
    assert Status.auth_hint([%{id: "069a79f4-44e9-4726-a5be-fca90e38aaf5"}]) == :online
    assert Status.auth_hint([%{id: "5b0b6dd0-9e42-3c6c-8b7d-2f0e3b1f1c2a"}]) == :offline
    assert Status.auth_hint([]) == nil
  end

  test "builds the host patterns Mojang's blocklist is checked against" do
    assert BlockedServers.patterns("play.example.com") == [
             "play.example.com",
             "*.example.com",
             "*.com"
           ]

    assert BlockedServers.patterns("1.2.3.4") == ["1.2.3.4", "1.2.3.*", "1.2.*", "1.*"]
  end

  describe "legacy ping" do
    test "parses the 1.4–1.6 response" do
      text = Enum.join(["§1", "61", "1.5.2", "§aOld server", "3", "20"], <<0>>)

      response =
        <<0xFF, String.length(text)::16>> <>
          :unicode.characters_to_binary(text, :utf8, {:utf16, :big})

      assert {:ok,
              %{
                version: %{name: "1.5.2", protocol: 61},
                players: %{online: 3, max: 20},
                motd: %{clean: ["Old server"]}
              }} =
               Legacy.parse(response)
    end

    test "parses the pre-1.4 response" do
      text = "A Minecraft Server§5§10"

      response =
        <<0xFF, String.length(text)::16>> <>
          :unicode.characters_to_binary(text, :utf8, {:utf16, :big})

      assert {:ok, %{players: %{online: 5, max: 10}, motd: %{clean: ["A Minecraft Server"]}}} =
               Legacy.parse(response)
    end
  end

  describe "login probe" do
    test "writes Login Start in the format of each protocol era" do
      assert {:ok, 0x00, <<4, "Test">>, ""} =
               Protocol.decode_packet(Login.login_start(47, "Test"))

      assert {:ok, 0x00, <<4, "Test", uuid::binary-size(16)>>, ""} =
               Protocol.decode_packet(Login.login_start(769, "Test"))

      assert byte_size(uuid) == 16

      assert {:ok, 0x00, <<4, "Test", 1, _uuid::binary-size(16)>>, ""} =
               Protocol.decode_packet(Login.login_start(763, "Test"))
    end

    test "reads the server's first answer" do
      assert %{mode: :online} = Login.interpret(0x01, <<>>)
      assert %{mode: :offline} = Login.interpret(0x03, <<>>)

      reason = Protocol.encode_string(Jason.encode!(%{"text" => "§cNie jesteś na whitelist"}))

      assert %{mode: :unknown, disconnect_reason: "Nie jesteś na whitelist"} =
               Login.interpret(0x00, reason)
    end
  end
end
