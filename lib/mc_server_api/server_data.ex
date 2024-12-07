defmodule McServerApi.ServerData do
  @derive Jason.Encoder
  defstruct [:ip, :port, :max_players, :online_players, :version, :motd, online: false]
end
