defmodule McServerApi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      McServerApiWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:mc_server_api, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: McServerApi.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: McServerApi.Finch},
      # Start a worker by calling: McServerApi.Worker.start_link(arg)
      # {McServerApi.Worker, arg},
      # Start to serve requests, typically the last entry
      McServerApiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: McServerApi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    McServerApiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
