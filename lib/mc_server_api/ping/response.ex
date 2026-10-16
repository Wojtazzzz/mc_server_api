defmodule McServerApi.Ping.Response do
  @moduledoc """
  Everything `McServerApi.Ping.Client` learns about a server: the status ping,
  and — when the server answers them — the UDP Query and the Bedrock ping.
  The favicon is left out of the JSON shown on the page (it is a long base64 string);
  the API adds it back.
  """

  @derive {Jason.Encoder, except: [:favicon]}
  defstruct online: false,
            legacy: false,
            hostname: nil,
            ip: nil,
            port: nil,
            srv: nil,
            software: nil,
            version: nil,
            players: nil,
            motd: nil,
            favicon: nil,
            favicon_sha1: nil,
            links: nil,
            auth: nil,
            eula_blocked: nil,
            network: nil,
            secure_chat: nil,
            forge: nil,
            modpack: nil,
            query: nil,
            bedrock: nil,
            timings: nil

  @type t :: %__MODULE__{}
end
