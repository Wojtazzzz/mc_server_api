defmodule McServerApi.ServerStatus do
  @moduledoc """
  Entry point for checking a server's status. The actual client is chosen in config
  (`config :mc_server_api, :status_client, ...`), so mcsrvstat.us and our own ping can be
  swapped without touching callers. Clients return their own data; there is no shared shape.
  """

  @callback call(address :: String.t()) :: term()

  @default_client McServerApi.Ping.Client

  @doc """
  Asks the configured client (or the one given as `client`) for the status of `address`.
  `opts` reach only clients that accept them (`call/2`); the rest ignore them.
  """
  @spec call(String.t(), module() | nil, keyword()) :: term()
  def call(address, client \\ nil, opts \\ []) do
    client = client || client()
    Code.ensure_loaded(client)

    if function_exported?(client, :call, 2),
      do: client.call(address, opts),
      else: client.call(address)
  end

  @spec client() :: module()
  def client, do: Application.get_env(:mc_server_api, :status_client, @default_client)
end
