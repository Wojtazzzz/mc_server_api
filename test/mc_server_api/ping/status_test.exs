defmodule McServerApi.Ping.StatusTest do
  use ExUnit.Case, async: true

  alias McServerApi.Ping.Status

  test "reads players, version, chat flags and favicon" do
    {:ok, status} =
      Status.parse(
        Jason.encode!(%{
          "version" => %{"name" => "§bPaper 1.21.4", "protocol" => 769},
          "players" => %{
            "online" => 12,
            "max" => 100,
            "sample" => [
              %{"name" => "Notch", "id" => "069a79f4-44e9-4726-a5be-fca90e38aaf5"},
              %{
                "name" => "§6★ Witaj na serwerze ★",
                "id" => "00000000-0000-0000-0000-000000000000"
              },
              %{
                "name" => "§e§lWILD§f§lNETWORK",
                "id" => "84648a51-0af4-4867-a627-ead4c55ff4cb"
              }
            ]
          },
          "description" => "Hello",
          "favicon" => "data:image/png;base64,AAAA",
          "enforcesSecureChat" => true,
          "preventsChatReports" => true
        })
      )

    assert status.version == %{name: "§bPaper 1.21.4", name_clean: "Paper 1.21.4", protocol: 769}
    assert status.players.online == 12
    assert status.players.max == 100
    # Decorative sample lines are not player names.
    assert status.players.sample == [%{name: "Notch", id: "069a79f4-44e9-4726-a5be-fca90e38aaf5"}]
    assert status.favicon == "data:image/png;base64,AAAA"
    assert status.secure_chat == %{enforced: true, previews_chat: nil, prevents_reports: true}
    assert status.forge == nil
  end

  test "lists Forge mods from both old and new formats, and modpack info" do
    status =
      Status.from_map(%{
        "modinfo" => %{"type" => "FML", "modList" => [%{"modid" => "jei", "version" => "1.0"}]},
        "forgeData" => %{
          "fmlNetworkVersion" => 3,
          "mods" => [%{"modId" => "create", "modmarker" => "0.5"}]
        },
        "modpackData" => %{
          "projectID" => 123,
          "name" => "All the Mods 10",
          "version" => "2.3",
          "releaseType" => "Release"
        }
      })

    assert status.forge.type == "FML"
    assert status.forge.network_version == 3
    assert status.forge.mods == [%{id: "jei", version: "1.0"}, %{id: "create", version: "0.5"}]

    assert status.modpack == %{
             name: "All the Mods 10",
             version: "2.3",
             project_id: 123,
             release_type: "Release"
           }
  end

  test "ignores fields of the wrong type instead of crashing" do
    status =
      Status.from_map(%{
        "version" => "1.20",
        "players" => %{"online" => "lots", "max" => -5, "sample" => "nope"},
        "description" => 42,
        "favicon" => "http://example.com/icon.png",
        "enforcesSecureChat" => "yes"
      })

    assert status.version == %{name: nil, name_clean: nil, protocol: nil}
    assert status.players == %{online: nil, max: nil, sample: []}
    assert status.motd.clean == []
    assert status.favicon == nil
    assert status.secure_chat.enforced == nil
  end

  test "rejects a response that is not a JSON object" do
    assert Status.parse("[]") == {:error, :invalid_json}
    assert Status.parse("not json") == {:error, :invalid_json}
  end
end
