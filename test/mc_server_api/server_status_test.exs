defmodule McServerApi.ServerStatusTest do
  use ExUnit.Case, async: false

  alias McServerApi.ServerStatus

  defmodule FakeClient do
    @behaviour McServerApi.ServerStatus

    @impl McServerApi.ServerStatus
    def call(address), do: {:fake, address}
  end

  test "uses the client set in config" do
    previous = Application.get_env(:mc_server_api, :status_client)
    Application.put_env(:mc_server_api, :status_client, FakeClient)
    on_exit(fn -> Application.put_env(:mc_server_api, :status_client, previous) end)

    assert ServerStatus.call("example.pl") == {:fake, "example.pl"}
  end

  test "lets the caller pick a client for a single call" do
    assert ServerStatus.call("example.pl", FakeClient) == {:fake, "example.pl"}
  end

  test "defaults to the own ping client" do
    assert ServerStatus.client() == McServerApi.Ping.Client
  end
end
