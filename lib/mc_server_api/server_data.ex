defmodule McServerApi.ServerData do
  defstruct [:ip, :port, :max_players, :online_players, :version, :motd, online: false]
end
