defmodule McServerApiWeb.PageController do
  use McServerApiWeb, :controller

  alias McServerApi.ServerStatus

  def home(conn, params) do
    ip = Map.get(params, "ip", "")

    # Measured here, so the time is shown for every client and for offline servers too.
    {request_us, server} =
      if String.length(ip) > 0 do
        :timer.tc(fn -> ServerStatus.call(ip) end)
      else
        {nil, nil}
      end

    render(conn, :home,
      layout: false,
      query: ip,
      server: server,
      request_ms: request_us && div(request_us, 1000)
    )
  end
end
