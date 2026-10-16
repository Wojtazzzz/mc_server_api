defmodule McServerApiWeb.StatusControllerTest do
  use McServerApiWeb.ConnCase, async: false

  import OpenApiSpex.TestAssertions

  defmodule OnlineClient do
    @behaviour McServerApi.ServerStatus

    @impl McServerApi.ServerStatus
    def call(address) do
      %McServerApi.ServerData{
        online: true,
        hostname: address,
        online_players: 5,
        favicon: "data:image/png;base64,AAAA"
      }
    end
  end

  defmodule OfflineClient do
    @behaviour McServerApi.ServerStatus

    @impl McServerApi.ServerStatus
    def call(_address), do: %McServerApi.ServerData{online: false}
  end

  defp use_client(client) do
    previous = Application.get_env(:mc_server_api, :status_client)
    Application.put_env(:mc_server_api, :status_client, client)
    on_exit(fn -> Application.put_env(:mc_server_api, :status_client, previous) end)
  end

  test "returns the status of an online server, favicon included", %{conn: conn} do
    use_client(OnlineClient)

    body = conn |> get(~p"/api/status/artmc.pl") |> json_response(200)

    assert %{"online" => true, "hostname" => "artmc.pl", "online_players" => 5} = body
    assert body["favicon"] == "data:image/png;base64,AAAA"
  end

  test "returns 404 for a server that is offline", %{conn: conn} do
    use_client(OfflineClient)

    body = conn |> get(~p"/api/status/artmc.pl:25570") |> json_response(404)

    assert body == %{"online" => false}
    assert_schema(body, "Offline", McServerApiWeb.ApiSpec.spec())
  end

  test "returns 400 for an invalid address or client", %{conn: conn} do
    body = conn |> get("/api/status/a%20b") |> json_response(400)
    assert body == %{"error" => "invalid_address"}
    assert_schema(body, "Error", McServerApiWeb.ApiSpec.spec())

    assert %{"error" => "unknown_client"} =
             conn |> get(~p"/api/status/artmc.pl?client=nope") |> json_response(400)
  end

  test "documents the mcsrvstat-style response", %{conn: conn} do
    use_client(OnlineClient)

    body = conn |> get(~p"/api/status/artmc.pl") |> json_response(200)
    assert_schema(body, "McsrvstatResponse", McServerApiWeb.ApiSpec.spec())
  end

  test "serves the OpenAPI spec and Swagger UI", %{conn: conn} do
    spec = conn |> get(~p"/api/openapi") |> json_response(200)

    assert spec["openapi"] =~ "3."
    assert Map.has_key?(spec["paths"], "/api/status/{address}")
    assert Map.has_key?(spec["components"]["schemas"], "StatusResponse")

    assert conn |> get(~p"/api/docs") |> html_response(200) =~ "swagger-ui"
  end
end
