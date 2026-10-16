defmodule McServerApi.Ping.Versions do
  @moduledoc """
  Game versions: the release a protocol number belongs to, and the range of versions
  a server advertises in its version name (e.g. "Velocity 1.7.2-1.21.4").
  """

  # Release protocol numbers. Snapshots and versions newer than this table return nil.
  @protocols %{
    4 => "1.7.2–1.7.5",
    5 => "1.7.6–1.7.10",
    47 => "1.8–1.8.9",
    107 => "1.9",
    108 => "1.9.1",
    109 => "1.9.2",
    110 => "1.9.3–1.9.4",
    210 => "1.10–1.10.2",
    315 => "1.11",
    316 => "1.11.1–1.11.2",
    335 => "1.12",
    338 => "1.12.1",
    340 => "1.12.2",
    393 => "1.13",
    401 => "1.13.1",
    404 => "1.13.2",
    477 => "1.14",
    480 => "1.14.1",
    485 => "1.14.2",
    490 => "1.14.3",
    498 => "1.14.4",
    573 => "1.15",
    575 => "1.15.1",
    578 => "1.15.2",
    735 => "1.16",
    736 => "1.16.1",
    751 => "1.16.2",
    753 => "1.16.3",
    754 => "1.16.4–1.16.5",
    755 => "1.17",
    756 => "1.17.1",
    757 => "1.18–1.18.1",
    758 => "1.18.2",
    759 => "1.19",
    760 => "1.19.1–1.19.2",
    761 => "1.19.3",
    762 => "1.19.4",
    763 => "1.20–1.20.1",
    764 => "1.20.2",
    765 => "1.20.3–1.20.4",
    766 => "1.20.5–1.20.6",
    767 => "1.21–1.21.1",
    768 => "1.21.2–1.21.3",
    769 => "1.21.4",
    770 => "1.21.5",
    771 => "1.21.6",
    772 => "1.21.7–1.21.8",
    773 => "1.21.9–1.21.10",
    774 => "1.21.11"
  }

  @spec protocol_name(integer() | nil) :: String.t() | nil
  def protocol_name(protocol), do: Map.get(@protocols, protocol)

  @doc """
  Oldest and newest game version found in a version name. Year-based versions
  (26.1, 26.x) need a dot, so prices, slot counts or IP fragments are not mistaken for one.
  """
  @spec range(String.t() | nil) :: %{oldest: String.t(), newest: String.t()} | nil
  def range(nil), do: nil

  def range(name) do
    pattern = ~r/(?<![\d.])(?:(1\.\d{1,2})(?:\.(\d{1,2}|x))?|(2[5-9])\.(\d{1,2}|x))(?![\d.]\d)/i

    case Regex.scan(pattern, name) do
      [] ->
        nil

      matches ->
        versions =
          matches
          |> Enum.map(fn
            [_, minor | _] when minor != "" -> minor
            [_, "", _, year, "x"] -> year
            [_, "", _, year, drop] -> "#{year}.#{String.to_integer(drop)}"
          end)
          |> Enum.sort_by(&version_key/1)

        %{oldest: List.first(versions), newest: List.last(versions)}
    end
  end

  defp version_key(version), do: version |> String.split(".") |> Enum.map(&String.to_integer/1)
end
