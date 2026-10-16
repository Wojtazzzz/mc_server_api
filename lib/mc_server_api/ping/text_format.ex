defmodule McServerApi.Ping.TextFormat do
  @moduledoc """
  Minecraft formatted text (MOTD, version name) in three forms:

    * `raw`   — legacy string with `§` codes, as old clients and most APIs show it,
    * `clean` — plain text lines,
    * `html`  — lines of `<span>`s with inline styles, safe to embed (text is escaped).

  Input is either a legacy string or a JSON chat component (`text`, `extra`,
  `color`, `bold`…), which may itself contain `§` codes.
  """

  @colors %{
    "0" => {"black", "#000000"},
    "1" => {"dark_blue", "#0000AA"},
    "2" => {"dark_green", "#00AA00"},
    "3" => {"dark_aqua", "#00AAAA"},
    "4" => {"dark_red", "#AA0000"},
    "5" => {"dark_purple", "#AA00AA"},
    "6" => {"gold", "#FFAA00"},
    "7" => {"gray", "#AAAAAA"},
    "8" => {"dark_gray", "#555555"},
    "9" => {"blue", "#5555FF"},
    "a" => {"green", "#55FF55"},
    "b" => {"aqua", "#55FFFF"},
    "c" => {"red", "#FF5555"},
    "d" => {"light_purple", "#FF55FF"},
    "e" => {"yellow", "#FFFF55"},
    "f" => {"white", "#FFFFFF"}
  }

  @color_by_name Map.new(@colors, fn {code, {name, hex}} -> {name, {code, hex}} end)

  @formats %{
    "k" => :obfuscated,
    "l" => :bold,
    "m" => :strikethrough,
    "n" => :underlined,
    "o" => :italic
  }

  @format_codes Map.new(@formats, fn {code, name} -> {name, code} end)

  @plain_style %{
    color: nil,
    bold: false,
    italic: false,
    underlined: false,
    strikethrough: false,
    obfuscated: false
  }

  @max_lines 10
  @max_line_length 256

  @type segment :: {String.t(), map()}

  @spec render(term()) :: %{raw: String.t(), clean: [String.t()], html: [String.t()]}
  def render(text) do
    segments = segments(text)

    %{
      raw: raw(segments),
      clean: clean_lines(segments),
      html: html_lines(segments)
    }
  end

  @doc "Removes `§` codes from a string."
  @spec strip_codes(String.t()) :: String.t()
  def strip_codes(text), do: String.replace(text, ~r/§(?:x(?:§[0-9a-f]){6}|[0-9a-fk-or])/iu, "")

  @doc "Splits formatted text into `{text, style}` segments."
  @spec segments(term()) :: [segment()]
  def segments(text),
    do: text |> segments(@plain_style) |> Enum.reject(fn {text, _} -> text == "" end)

  defp segments(text, style) when is_binary(text), do: legacy_segments(text, style)
  defp segments(list, style) when is_list(list), do: Enum.flat_map(list, &segments(&1, style))

  defp segments(%{} = component, parent_style) do
    style = component_style(component, parent_style)

    own =
      case component do
        %{"text" => text} when is_binary(text) -> text
        %{"translate" => key} when is_binary(key) -> key
        _ -> ""
      end

    segments(own, style) ++ segments(Map.get(component, "extra", []), style)
  end

  defp segments(_other, _style), do: []

  defp component_style(component, parent) do
    color =
      case component["color"] do
        "#" <> hex = color when byte_size(hex) == 6 -> String.upcase(color)
        name when is_binary(name) -> with {_code, hex} <- @color_by_name[name], do: hex
        _ -> parent.color
      end

    Enum.reduce(Map.keys(@format_codes), %{parent | color: color}, fn format, style ->
      case component[Atom.to_string(format)] do
        value when is_boolean(value) -> Map.put(style, format, value)
        _ -> style
      end
    end)
  end

  # Walks a string with § codes; a colour code resets formatting, as in the game.
  defp legacy_segments(text, style) do
    ~r/§(x(?:§[0-9a-f]){6}|[0-9a-fk-or])/iu
    |> Regex.split(text, include_captures: true)
    |> Enum.reduce({[], style}, fn part, {acc, current} ->
      case legacy_code(part) do
        nil -> {[{part, current} | acc], current}
        {:color, hex} -> {acc, %{@plain_style | color: hex}}
        {:format, format} -> {acc, Map.put(current, format, true)}
        :reset -> {acc, @plain_style}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp legacy_code("§" <> code) do
    code = String.downcase(code)

    cond do
      String.starts_with?(code, "x") ->
        {:color, "#" <> (code |> String.replace(["x", "§"], "") |> String.upcase())}

      Map.has_key?(@colors, code) ->
        {:color, elem(@colors[code], 1)}

      Map.has_key?(@formats, code) ->
        {:format, @formats[code]}

      code == "r" ->
        :reset

      true ->
        nil
    end
  end

  defp legacy_code(_text), do: nil

  defp raw(segments) do
    Enum.map_join(segments, fn {text, style} -> legacy_prefix(style) <> text end)
  end

  defp legacy_prefix(style) do
    color =
      case style.color do
        nil ->
          ""

        hex ->
          case Enum.find(@colors, fn {_code, {_name, value}} -> value == hex end) do
            {code, _} ->
              "§" <> code

            nil ->
              "§x" <>
                (hex
                 |> String.trim_leading("#")
                 |> String.downcase()
                 |> String.graphemes()
                 |> Enum.map_join(&("§" <> &1)))
          end
      end

    formats =
      @format_codes
      |> Enum.filter(fn {format, _code} -> style[format] end)
      |> Enum.map_join(fn {_format, code} -> "§" <> code end)

    "§r" <> color <> formats
  end

  defp clean_lines(segments) do
    segments
    |> Enum.map_join(fn {text, _style} -> strip_codes(text) end)
    |> to_lines()
    |> Enum.map(&String.trim/1)
    |> drop_trailing_empty()
    |> Enum.map(&String.slice(&1, 0, @max_line_length))
  end

  defp html_lines(segments) do
    segments
    |> Enum.flat_map(fn {text, style} ->
      text |> String.split("\n") |> Enum.map(&{&1, style}) |> Enum.intersperse(:newline)
    end)
    |> Enum.chunk_by(&(&1 == :newline))
    |> Enum.reject(&(&1 == [:newline]))
    |> Enum.map(fn line -> Enum.map_join(line, &span/1) end)
    |> Enum.take(@max_lines)
  end

  defp span({"", _style}), do: ""

  defp span({text, style}) do
    css =
      [
        style.color && "color: #{style.color}",
        style.bold && "font-weight: bold",
        style.italic && "font-style: italic",
        decoration(style)
      ]
      |> Enum.filter(& &1)
      |> Enum.join("; ")

    escaped = text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    if css == "", do: "<span>#{escaped}</span>", else: ~s(<span style="#{css}">#{escaped}</span>)
  end

  defp decoration(%{underlined: true, strikethrough: true}),
    do: "text-decoration: underline line-through"

  defp decoration(%{underlined: true}), do: "text-decoration: underline"
  defp decoration(%{strikethrough: true}), do: "text-decoration: line-through"
  defp decoration(_style), do: nil

  defp to_lines(text), do: text |> String.split("\n") |> Enum.take(@max_lines)

  defp drop_trailing_empty(lines),
    do: lines |> Enum.reverse() |> Enum.drop_while(&(&1 == "")) |> Enum.reverse()
end
