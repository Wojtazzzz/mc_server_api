defmodule McServerApi.ServerData do
  @moduledoc """
  Status of a Minecraft server as returned by `McServerApi.McsrvstatClient`.
  (`McServerApi.Ping.Client` returns its own, richer `McServerApi.Ping.Response`.)
  """

  @derive {Jason.Encoder, except: [:favicon]}
  defstruct [
    :hostname,
    :ip,
    :port,
    :max_players,
    :online_players,
    :version,
    :protocol,
    :motd,
    :latency,
    :favicon,
    players_sample: [],
    mods: [],
    online: false
  ]

  @type t :: %__MODULE__{
          online: boolean(),
          hostname: String.t() | nil,
          ip: String.t() | nil,
          port: :inet.port_number() | nil,
          max_players: non_neg_integer() | nil,
          online_players: non_neg_integer() | nil,
          version: String.t() | nil,
          protocol: integer() | nil,
          motd: [String.t()] | nil,
          latency: non_neg_integer() | nil,
          favicon: String.t() | nil,
          players_sample: [String.t()],
          mods: [String.t()]
        }
end
