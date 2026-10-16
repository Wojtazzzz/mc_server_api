defmodule McServerApiWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use McServerApiWeb, :html

  embed_templates "page_html/*"

  @examples ["hypixel.net", "craftmc.pl", "donutsmp.net", "kokscraft.pl"]

  @doc "Addresses offered as one-click examples on the search form."
  def examples, do: @examples

  @doc "How many of the five signal bars to light, the way the game shows ping."
  def signal_bars(nil), do: 0
  def signal_bars(ms) when ms < 50, do: 5
  def signal_bars(ms) when ms < 100, do: 4
  def signal_bars(ms) when ms < 150, do: 3
  def signal_bars(ms) when ms < 300, do: 2
  def signal_bars(_ms), do: 1

  @doc "Share of slots taken, 0–100; servers that report more players than slots are capped."
  def fill_percent(%{online: online, max: max})
      when is_integer(online) and is_integer(max) and max > 0,
      do: min(100, round(online / max * 100))

  def fill_percent(_players), do: 0

  def auth_label(%{mode: :online}), do: {"Premium", "Requires a Mojang/Microsoft account"}
  def auth_label(%{mode: :offline}), do: {"Cracked", "Playable without a paid account"}
  def auth_label(_auth), do: {"Unknown", "Check with ?login=true"}

  def format_number(nil), do: "—"

  def format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1 ")
    |> String.reverse()
  end

  @doc "Segments of the timing bar: label, value in ms and colour class."
  def timing_segments(nil), do: []

  def timing_segments(timings) do
    [
      {"DNS", timings[:dns_ms], "bg-[#7C4DFF]"},
      {"Connect", timings[:connect_ms], "bg-[#5217D1]"},
      {"Status", timings[:status_ms], "bg-[#1740D1]"},
      {"Ping", timings[:latency_ms], "bg-[#3B82F6]"}
    ]
    |> Enum.filter(fn {_label, value, _class} -> is_integer(value) end)
  end
end
