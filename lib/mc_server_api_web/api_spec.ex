defmodule McServerApiWeb.ApiSpec do
  @moduledoc "OpenAPI specification of the API, served at `/api/openapi` and shown in Swagger UI at `/api/docs`."

  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.Info
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Paths
  alias OpenApiSpex.Server

  @impl OpenApiSpex.OpenApi
  def spec do
    %OpenApi{
      servers: [Server.from_endpoint(McServerApiWeb.Endpoint)],
      info: %Info{
        title: "Server Api",
        version: to_string(Application.spec(:mc_server_api, :vsn)),
        description: """
        Status of any Minecraft server: our own Server List Ping (TCP), UDP Query, Bedrock ping,
        DNS and network details, Mojang's EULA blocklist and — optionally — premium/cracked mode.
        No API key needed. Requests are limited to 30 per minute per IP address (with a short burst
        allowance); above that the API answers `429 Too Many Requests`.
        """
      },
      paths: Paths.from_router(McServerApiWeb.Router)
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
