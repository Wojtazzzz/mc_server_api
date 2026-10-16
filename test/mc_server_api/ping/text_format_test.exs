defmodule McServerApi.Ping.TextFormatTest do
  use ExUnit.Case, async: true

  alias McServerApi.Ping.TextFormat

  test "renders a legacy MOTD as raw, clean and html" do
    rendered = TextFormat.render("§a§lCraft§r§7 » survival\n  §eNowa edycja!  ")

    assert rendered.raw == "§r§a§lCraft§r§7 » survival\n  §r§eNowa edycja!  "
    assert rendered.clean == ["Craft » survival", "Nowa edycja!"]

    assert rendered.html == [
             ~s(<span style="color: #55FF55; font-weight: bold">Craft</span><span style="color: #AAAAAA"> » survival</span>),
             ~s(<span style="color: #AAAAAA">  </span><span style="color: #FFFF55">Nowa edycja!  </span>)
           ]
  end

  test "flattens chat components, inheriting style and accepting hex colours" do
    rendered =
      TextFormat.render(%{
        "text" => "",
        "extra" => [
          %{
            "text" => "Donut",
            "color" => "aqua",
            "bold" => true,
            "extra" => [%{"text" => "SMP"}]
          },
          %{"text" => "\n"},
          %{"text" => "plain ", "color" => "#ff8800"},
          %{"translate" => "menu.online"}
        ]
      })

    assert rendered.clean == ["DonutSMP", "plain menu.online"]
    assert hd(rendered.html) =~ ~s(<span style="color: #55FFFF; font-weight: bold">SMP</span>)
    assert List.last(rendered.html) =~ ~s(<span style="color: #FF8800">plain </span>)
    assert rendered.raw =~ "§r§b§lDonut"
    assert rendered.raw =~ "§r§x§f§f§8§8§0§0plain "
  end

  test "escapes HTML coming from the server" do
    assert TextFormat.render("<script>alert(1)</script>").html == [
             "<span>&lt;script&gt;alert(1)&lt;/script&gt;</span>"
           ]
  end

  test "understands BungeeCord hex colour codes" do
    assert TextFormat.render("§x§f§f§0§0§0§0Red").html == [
             ~s(<span style="color: #FF0000">Red</span>)
           ]

    assert TextFormat.strip_codes("§x§f§f§0§0§0§0Red §lbold") == "Red bold"
  end
end
