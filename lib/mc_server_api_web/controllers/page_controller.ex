defmodule McServerApiWeb.PageController do
  use McServerApiWeb, :controller

  alias McServerApi.McsrvstatClient

  def home(conn, _params) do
    render(conn, :home, layout: false, server: nil)
  end

  def status(conn, %{"ip" => ip}) do
    server = McsrvstatClient.call(ip)

    render(conn, :home, layout: false, server: server)
  end
end
