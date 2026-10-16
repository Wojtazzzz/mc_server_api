defmodule McServerApi.Ping.Status do
  @moduledoc """
  Turns the JSON of a status response into plain values.

  Everything in it is set by the server owner, so every field is optional,
  type-checked and length-limited instead of trusted.
  """

  alias McServerApi.Ping.TextFormat

  @max_sample 20
  @max_mods 300
  @max_favicon_size 262_144

  @spec parse(String.t()) :: {:ok, map()} | {:error, :invalid_json}
  def parse(json) do
    case Jason.decode(json) do
      {:ok, %{} = status} -> {:ok, from_map(status)}
      _invalid -> {:error, :invalid_json}
    end
  end

  @spec from_map(map()) :: map()
  def from_map(status) do
    version = map_or_empty(status["version"])
    players = map_or_empty(status["players"])
    version_name = string_or_nil(version["name"])

    %{
      version: %{
        name: version_name,
        name_clean: version_name && TextFormat.strip_codes(version_name),
        protocol: integer_or_nil(version["protocol"])
      },
      players: %{
        online: non_negative_or_nil(players["online"]),
        max: non_negative_or_nil(players["max"]),
        sample: players_sample(players["sample"])
      },
      motd: TextFormat.render(status["description"]),
      favicon: favicon(status["favicon"]),
      secure_chat: %{
        enforced: boolean_or_nil(status["enforcesSecureChat"]),
        previews_chat: boolean_or_nil(status["previewsChat"]),
        # Set by the NoChatReports mod/plugin.
        prevents_reports: boolean_or_nil(status["preventsChatReports"])
      },
      forge: forge(status),
      modpack: modpack(status["modpackData"])
    }
  end

  @doc "MOTD as plain lines (kept for callers that only need the text)."
  @spec motd(term()) :: [String.t()]
  def motd(description), do: TextFormat.render(description).clean

  @doc """
  Discord invites and websites mentioned in the MOTD lines — servers advertise them there
  more reliably than anywhere else.
  """
  @spec links([String.t()]) :: %{discord: [String.t()], websites: [String.t()]}
  def links(lines) do
    text = Enum.join(lines, " ")

    discord =
      ~r/\b(?:(?:discord\.gg|discord\.com\/invite)\/[A-Za-z0-9-]+|dc\.[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,})/i
      |> Regex.scan(text)
      |> Enum.map(&(&1 |> hd() |> String.downcase()))
      |> Enum.uniq()

    websites =
      ~r/\b(?:https?:\/\/)?(?:[a-z0-9-]+\.)+(?:pl|com|net|eu|org|gg|me|io|xyz|online|fun|club|pro|info|dev|games|store|shop)\b(?:\/[^\s]*)?/i
      |> Regex.scan(text)
      |> Enum.map(&(&1 |> hd() |> String.downcase() |> String.replace(~r/^https?:\/\//, "")))
      |> Enum.reject(fn site ->
        Enum.any?(discord, &String.starts_with?(&1, site)) or
          String.starts_with?(site, "discord.")
      end)
      |> Enum.uniq()

    %{discord: discord, websites: websites}
  end

  @doc """
  Online or offline mode guessed from the UUIDs in the player sample: Mojang accounts
  have version 4 UUIDs, offline ("no premium") players get name-based version 3 ones.
  """
  @spec auth_hint([%{id: String.t() | nil}]) :: :online | :offline | nil
  def auth_hint(sample) do
    versions =
      sample
      |> Enum.flat_map(fn
        %{id: <<_::binary-size(14), version::binary-size(1), _::binary>>} -> [version]
        _ -> []
      end)
      |> Enum.uniq()

    cond do
      versions == [] -> nil
      "4" in versions -> :online
      versions == ["3"] -> :offline
      true -> nil
    end
  end

  defp players_sample(sample) when is_list(sample) do
    sample
    |> Enum.flat_map(fn
      %{"name" => name} = player when is_binary(name) ->
        [%{name: TextFormat.strip_codes(name), id: string_or_nil(player["id"])}]

      _ ->
        []
    end)
    # Servers often fill the sample with decorative lines instead of player names.
    |> Enum.filter(&Regex.match?(~r/^[A-Za-z0-9_]{3,16}$/, &1.name))
    |> Enum.take(@max_sample)
  end

  defp players_sample(_sample), do: []

  defp favicon("data:image/png;base64," <> _rest = favicon)
       when byte_size(favicon) <= @max_favicon_size,
       do: favicon

  defp favicon(_favicon), do: nil

  # Forge reports mods as "modinfo" (up to 1.12) or "forgeData" (1.13+, also NeoForge).
  defp forge(status) do
    legacy = map_or_empty(status["modinfo"])
    modern = map_or_empty(status["forgeData"])

    if legacy == %{} and modern == %{} do
      nil
    else
      %{
        type: string_or_nil(legacy["type"]) || (modern != %{} && "FML2") || nil,
        network_version: integer_or_nil(modern["fmlNetworkVersion"]),
        # Servers with many mods send a compressed "d" field instead of the list; it is not decoded here.
        truncated: modern["truncated"] == true or is_binary(modern["d"]),
        mods: mods(legacy["modList"]) ++ mods(modern["mods"])
      }
    end
  end

  defp mods(list) when is_list(list) do
    list
    |> Enum.flat_map(fn
      %{"modid" => id, "version" => version} when is_binary(id) and is_binary(version) ->
        [%{id: id, version: version}]

      %{"modId" => id, "modmarker" => version} when is_binary(id) and is_binary(version) ->
        [%{id: id, version: version}]

      %{"modid" => id} when is_binary(id) ->
        [%{id: id, version: nil}]

      %{"modId" => id} when is_binary(id) ->
        [%{id: id, version: nil}]

      _ ->
        []
    end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(@max_mods)
  end

  defp mods(_list), do: []

  # Sent by the CurseForge "Better Compatibility Checker" style mods.
  defp modpack(%{} = data) do
    %{
      name: string_or_nil(data["name"]),
      version: string_or_nil(data["version"]),
      project_id: integer_or_nil(data["projectID"]),
      release_type: string_or_nil(data["releaseType"])
    }
  end

  defp modpack(_data), do: nil

  defp map_or_empty(%{} = map), do: map
  defp map_or_empty(_other), do: %{}

  defp string_or_nil(value) when is_binary(value), do: value
  defp string_or_nil(_value), do: nil

  defp integer_or_nil(value) when is_integer(value), do: value
  defp integer_or_nil(_value), do: nil

  defp boolean_or_nil(value) when is_boolean(value), do: value
  defp boolean_or_nil(_value), do: nil

  defp non_negative_or_nil(value) when is_integer(value) and value >= 0, do: value
  defp non_negative_or_nil(_value), do: nil
end
