defmodule McServerApiWeb.PageControllerTest do
  use McServerApiWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Check any Minecraft server's status"
  end
end
