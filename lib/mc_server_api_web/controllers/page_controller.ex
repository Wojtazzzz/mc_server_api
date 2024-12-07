defmodule McServerApiWeb.PageController do
  use McServerApiWeb, :controller

  alias McServerApi.McsrvstatClient

  def home(conn, params) do
    ip = Map.get(params, "ip", "")

    server =
      if String.length(ip) > 0 do
        McsrvstatClient.call(ip)
      end

    render(conn, :home, layout: false, query: ip, server: server)
  end
end
