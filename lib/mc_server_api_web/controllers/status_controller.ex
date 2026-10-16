defmodule McServerApiWeb.StatusController do
  use McServerApiWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias McServerApi.Ping.Client
  alias McServerApi.ServerStatus
  alias McServerApiWeb.Schemas

  # Lets a single request compare sources without changing the configured client.
  @clients %{
    "ping" => McServerApi.Ping.Client,
    "mcsrvstat" => McServerApi.McsrvstatClient
  }

  tags(["Status"])

  operation(:show,
    summary: "Minecraft server status",
    description: """
    Everything a server reveals about itself. The default `ping` client asks the server directly;
    the UDP Query, Bedrock, DNS and EULA checks run in parallel and stretch the response from
    about 150 ms to about 1–1.8 s — turn them off with the parameters below when speed matters.
    """,
    parameters: [
      address: [
        in: :path,
        type: :string,
        required: true,
        description:
          "`domain` (the `_minecraft._tcp` SRV record first, then port 25565), `domain:port`, `ip`, `ip:port` or `[ipv6]:port`.",
        example: "craftmc.pl"
      ],
      client: [
        in: :query,
        schema: %OpenApiSpex.Schema{type: :string, enum: Map.keys(@clients)},
        description:
          "Data source; defaults to the configured one (`ping`). `mcsrvstat` returns the `McsrvstatResponse` format."
      ],
      login: [
        in: :query,
        type: :boolean,
        description:
          "Checks premium/cracked with a login attempt (see `Auth`). The server logs it as a player connection attempt."
      ],
      query: [in: :query, type: :boolean, description: "`false` skips the UDP Query."],
      bedrock: [in: :query, type: :boolean, description: "`false` skips the Bedrock ping."],
      network: [
        in: :query,
        type: :boolean,
        description: "`false` skips CNAME, reverse DNS and ASN lookups."
      ],
      blocked: [
        in: :query,
        type: :boolean,
        description: "`false` skips Mojang's blocked servers list."
      ]
    ],
    responses: [
      ok:
        {"The server answered", "application/json",
         %OpenApiSpex.Schema{oneOf: [Schemas.StatusResponse, Schemas.McsrvstatResponse]}},
      not_found: {"The server is offline or unreachable", "application/json", Schemas.Offline},
      bad_request: {"Invalid address or client", "application/json", Schemas.Error},
      too_many_requests:
        {"More than 30 requests per minute from this IP address", "text/html", nil}
    ]
  )

  def show(conn, %{"address" => address} = params) do
    with {:ok, _host, _port} <- Client.parse_address(address),
         {:ok, client} <- client(params["client"]) do
      case ServerStatus.call(address, client, options(params)) do
        %{online: true} = status ->
          json(conn, to_map(status))

        _offline ->
          conn |> put_status(:not_found) |> json(%{online: false})
      end
    else
      {:error, :invalid_address} ->
        conn |> put_status(:bad_request) |> json(%{error: "invalid_address"})

      {:error, :unknown_client} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "unknown_client", clients: Map.keys(@clients)})
    end
  end

  defp options(params) do
    [login: params["login"] == "true"] ++
      for key <- ~w(query bedrock network blocked),
          params[key] == "false",
          do: {String.to_existing_atom(key), false}
  end

  defp client(nil), do: {:ok, ServerStatus.client()}

  defp client(name) do
    case Map.fetch(@clients, name) do
      {:ok, client} -> {:ok, client}
      :error -> {:error, :unknown_client}
    end
  end

  # Unlike the page, the API returns the favicon too.
  defp to_map(%_{} = struct), do: Map.from_struct(struct)
  defp to_map(map), do: map
end
