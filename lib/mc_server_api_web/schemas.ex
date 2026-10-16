defmodule McServerApiWeb.Schemas do
  @moduledoc """
  OpenAPI schemas of the status API. They are the API documentation (rendered by Swagger UI
  at `/api/docs`), and tests check real responses against them so the two cannot drift apart.
  """

  require OpenApiSpex

  alias OpenApiSpex.Schema

  defmodule Srv do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Srv",
      description:
        "The `_minecraft._tcp` SRV record, when the address was given without a port and the domain has one. With several records, the one with the lowest priority is used.",
      type: :object,
      nullable: true,
      properties: %{
        target: %Schema{
          type: :string,
          description: "Host from the SRV record.",
          example: "mc.craftmc.pl"
        },
        port: %Schema{type: :integer, description: "Port from the SRV record.", example: 25_565}
      },
      required: [:target, :port]
    })
  end

  defmodule VersionRange do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "VersionRange",
      description:
        "Oldest and newest version found in `name_clean`; `null` when the name contains no version number.",
      type: :object,
      nullable: true,
      properties: %{
        oldest: %Schema{type: :string, description: "Shortened to `major.minor`.", example: "1.8"},
        newest: %Schema{
          type: :string,
          description: "Year-based versions without a number (`26.x`) are returned as `26`.",
          example: "26.3"
        }
      },
      required: [:oldest, :newest]
    })
  end

  defmodule Version do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Version",
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          nullable: true,
          description:
            "Version name exactly as the server reports it, with `§` codes. Often text instead of a number, e.g. `Requires MC 1.8 / 1.21`.",
          example: "1.8 - 26.3"
        },
        name_clean: %Schema{
          type: :string,
          nullable: true,
          description: "`name` without `§` codes."
        },
        protocol: %Schema{
          type: :integer,
          nullable: true,
          description:
            "Protocol number. Proxies with ViaVersion often report the newest one they support.",
          example: 769
        },
        protocol_name: %Schema{
          type: :string,
          nullable: true,
          description:
            "Game release matching `protocol` (e.g. 769 → `1.21.4`, 47 → `1.8–1.8.9`); `null` for snapshots and versions newer than the built-in table (currently up to 1.21.11).",
          example: "1.21.4"
        },
        range: VersionRange
      },
      required: [:name, :name_clean, :protocol, :protocol_name, :range]
    })
  end

  defmodule PlayerSample do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PlayerSample",
      type: :object,
      properties: %{
        name: %Schema{
          type: :string,
          description: "Username (3–16 characters: letters, digits, `_`).",
          example: "Notch"
        },
        id: %Schema{type: :string, nullable: true, description: "Player UUID."}
      },
      required: [:name, :id]
    })
  end

  defmodule Players do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Players",
      type: :object,
      properties: %{
        online: %Schema{
          type: :integer,
          nullable: true,
          description: "Players online, as reported by the server.",
          example: 1910
        },
        max: %Schema{
          type: :integer,
          nullable: true,
          description: "Slots, as reported by the server.",
          example: 3000
        },
        sample: %Schema{
          type: :array,
          items: PlayerSample,
          description:
            "Up to 20 players from the list shown when hovering over the player count. Entries that are not usernames (decorative lines, ads) are skipped; many servers do not send this list at all."
        }
      },
      required: [:online, :max, :sample]
    })
  end

  defmodule Motd do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Motd",
      description: "The server description in three forms.",
      type: :object,
      properties: %{
        raw: %Schema{
          type: :string,
          description:
            "With `§` formatting codes; hex colours as `§x§r§r§g§g§b§b`, lines separated by `\\n`."
        },
        clean: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description:
            "Plain lines, trimmed, without trailing empty lines. At most 10 lines of 256 characters."
        },
        html: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description:
            "Lines as `<span style=\"…\">` with colour, bold, italic, underline and strikethrough. The text is escaped, so it is safe to embed in a page."
        }
      },
      required: [:raw, :clean, :html]
    })
  end

  defmodule Links do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Links",
      description: "Links found in `motd.clean`.",
      type: :object,
      properties: %{
        discord: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description:
            "`discord.gg/…`, `discord.com/invite/…` and `dc.server.com`-style addresses, lowercased.",
          example: ["dc.artmc.pl"]
        },
        websites: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Other website addresses on common domains, without `http(s)://`.",
          example: ["www.craftmc.pl"]
        }
      },
      required: [:discord, :websites]
    })
  end

  defmodule Auth do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Auth",
      description: """
      Whether a premium (paid) account is needed to play.

      With `login=true` the API sends a handshake and Login Start with a random `Ping…` username,
      reads the server's first answer and closes the connection before joining:
      Encryption Request → `online`, Set Compression / Login Success → `offline`,
      Disconnect → `unknown` with `disconnect_reason`.
      The server logs this as a player connection attempt (anti-bot plugins may react), which is why it is opt-in.
      """,
      type: :object,
      properties: %{
        mode: %Schema{
          type: :string,
          enum: ["online", "offline", "unknown"],
          description:
            "`online` — a Mojang/Microsoft account is required (premium); `offline` — playable without a paid account (cracked)."
        },
        source: %Schema{
          type: :string,
          enum: ["login", "player_sample"],
          nullable: true,
          description:
            "`login` — from the login attempt (most reliable); `player_sample` — from the UUID versions in `players.sample` (v4 = premium, v3 = cracked); `null` — no data."
        },
        disconnect_reason: %Schema{
          type: :string,
          nullable: true,
          description:
            "Only with `source: login`: the message the server disconnected the attempt with (whitelist, anti-bot, \"server closed\"…). Plain text, at most 500 characters."
        },
        login_protocol: %Schema{
          type: :integer,
          nullable: true,
          description:
            "Only with `login=true`: protocol used for the attempt. If the server rejects the version it advertised itself, the API retries once with 769 (1.21.4)."
        },
        error: %Schema{
          type: :string,
          description: "Only when the login attempt got no answer at all."
        }
      },
      required: [:mode, :source, :disconnect_reason]
    })
  end

  defmodule Asn do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Asn",
      description: "The network `ip` belongs to, according to Team Cymru (IPv4 only).",
      type: :object,
      nullable: true,
      properties: %{
        number: %Schema{type: :integer, description: "Autonomous system number.", example: 16_276},
        name: %Schema{
          type: :string,
          nullable: true,
          description: "Network owner.",
          example: "OVH - OVH SAS, FR"
        },
        prefix: %Schema{
          type: :string,
          description: "Prefix containing `ip`.",
          example: "141.94.0.0/16"
        },
        country: %Schema{
          type: :string,
          description:
            "Country the prefix is registered in (ISO 3166) — not always where the server physically is.",
          example: "FR"
        },
        registry: %Schema{
          type: :string,
          description: "Regional registry: `ripencc`, `arin`, `apnic`, `lacnic`, `afrinic`.",
          example: "ripencc"
        }
      },
      required: [:number, :name, :prefix, :country, :registry]
    })
  end

  defmodule Network do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Network",
      description: "DNS and network details; `null` with `network=false`.",
      type: :object,
      nullable: true,
      properties: %{
        ipv4: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description:
            "A records of the host the API connected to (from SRV or the address); empty for an IP address."
        },
        ipv6: %Schema{type: :array, items: %Schema{type: :string}, description: "AAAA records."},
        cname: %Schema{
          type: :string,
          nullable: true,
          description:
            "CNAME record — often reveals DDoS protection (e.g. `…infinity-filter.com`)."
        },
        reverse_dns: %Schema{
          type: :string,
          nullable: true,
          description: "Reverse DNS (PTR) of `ip` — often points to the hosting company."
        },
        asn: Asn
      },
      required: [:ipv4, :ipv6, :cname, :reverse_dns, :asn]
    })
  end

  defmodule SecureChat do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SecureChat",
      description:
        "Signed chat settings. Proxies (Velocity, BungeeCord) usually do not send them.",
      type: :object,
      nullable: true,
      properties: %{
        enforced: %Schema{
          type: :boolean,
          nullable: true,
          description: "Requires signed chat messages (`enforce-secure-profile`)."
        },
        previews_chat: %Schema{
          type: :boolean,
          nullable: true,
          description: "Chat preview (1.19–1.19.2 only)."
        },
        prevents_reports: %Schema{
          type: :boolean,
          nullable: true,
          description: "Runs the NoChatReports mod or plugin."
        }
      },
      required: [:enforced, :previews_chat, :prevents_reports]
    })
  end

  defmodule ForgeMod do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ForgeMod",
      type: :object,
      properties: %{
        id: %Schema{type: :string, example: "create"},
        version: %Schema{type: :string, nullable: true, example: "0.5.1"}
      },
      required: [:id, :version]
    })
  end

  defmodule Forge do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Forge",
      description: "Forge/NeoForge server data; `null` for other servers.",
      type: :object,
      nullable: true,
      properties: %{
        type: %Schema{
          type: :string,
          nullable: true,
          description: "`FML` (up to 1.12) or `FML2` (1.13+)."
        },
        network_version: %Schema{
          type: :integer,
          nullable: true,
          description: "Forge network protocol version."
        },
        truncated: %Schema{
          type: :boolean,
          description: "The server sent its mod list compressed — `mods` is incomplete."
        },
        mods: %Schema{type: :array, items: ForgeMod, description: "Up to 300 mods."}
      },
      required: [:type, :network_version, :truncated, :mods]
    })
  end

  defmodule Modpack do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Modpack",
      description: "CurseForge modpack (`modpackData`), when the server reports one.",
      type: :object,
      nullable: true,
      properties: %{
        name: %Schema{type: :string, nullable: true},
        version: %Schema{type: :string, nullable: true},
        project_id: %Schema{type: :integer, nullable: true, description: "CurseForge project ID."},
        release_type: %Schema{type: :string, nullable: true, example: "Release"}
      },
      required: [:name, :version, :project_id, :release_type]
    })
  end

  defmodule Query do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Query",
      description:
        "UDP Query on the game port — only servers with `enable-query=true`; large networks usually turn it off, so this is mostly `null`.",
      type: :object,
      nullable: true,
      properties: %{
        software: %Schema{type: :string, nullable: true, example: "Paper on 1.21.4"},
        plugins: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Up to 300 plugins as `Name version`.",
          example: ["LuckPerms 5.4"]
        },
        map: %Schema{type: :string, nullable: true, description: "World name."},
        game_type: %Schema{type: :string, nullable: true, example: "SMP"},
        version: %Schema{type: :string, nullable: true},
        host_port: %Schema{type: :integer, nullable: true},
        players: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Up to 100 usernames of online players."
        }
      },
      required: [:software, :plugins, :map, :game_type, :version, :host_port, :players]
    })
  end

  defmodule Bedrock do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Bedrock",
      description:
        "Bedrock ping (RakNet, UDP) on port 19132 and on the game port — usually means phones and consoles can join (Geyser).",
      type: :object,
      nullable: true,
      properties: %{
        edition: %Schema{type: :string, enum: ["Bedrock", "Education"]},
        motd: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Up to two lines, without `§` codes."
        },
        version: %Schema{type: :string, nullable: true, example: "1.21.40"},
        protocol: %Schema{
          type: :integer,
          nullable: true,
          description: "Bedrock protocol (numbered differently from Java)."
        },
        players: %Schema{
          type: :object,
          properties: %{
            online: %Schema{type: :integer, nullable: true},
            max: %Schema{type: :integer, nullable: true}
          },
          required: [:online, :max]
        },
        game_mode: %Schema{type: :string, nullable: true, example: "Survival"},
        port: %Schema{type: :integer, description: "The port that answered."},
        verified: %Schema{
          type: :boolean,
          description:
            "`true` when the answer certainly belongs to this server (came from the game port, or the Bedrock MOTD contains the name from the domain). Servers behind DDoS protection share an IP with other customers — with `false`, port 19132 may belong to someone else."
        }
      },
      required: [:edition, :motd, :version, :protocol, :players, :game_mode, :port, :verified]
    })
  end

  defmodule Timings do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Timings",
      description: "Duration of each step in milliseconds.",
      type: :object,
      properties: %{
        dns_ms: %Schema{type: :integer, description: "SRV record and IP address lookup."},
        connect_ms: %Schema{type: :integer, nullable: true, description: "TCP connection."},
        status_ms: %Schema{
          type: :integer,
          nullable: true,
          description: "From the request to receiving the status."
        },
        latency_ms: %Schema{
          type: :integer,
          nullable: true,
          description: "Ping/pong; `null` when the server closed the connection after the status."
        },
        total_ms: %Schema{
          type: :integer,
          description: "The whole request, including the parallel UDP, DNS and login checks."
        }
      },
      required: [:dns_ms, :connect_ms, :status_ms, :latency_ms, :total_ms]
    })
  end

  defmodule StatusResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "StatusResponse",
      description: """
      Server status from the `ping` client (the default). The data comes from the server and its owner:
      the API checks and trims it but cannot vouch for it (e.g. more players than slots).

      When `legacy` is `true` (a pre-1.7 server), these are `null`: `favicon`, `favicon_sha1`, `secure_chat`,
      `forge`, `modpack`, `timings.connect_ms`, `timings.status_ms`, `timings.latency_ms`, and `players.sample` is empty.
      """,
      type: :object,
      properties: %{
        online: %Schema{type: :boolean, description: "Always `true` in a 200 response."},
        legacy: %Schema{
          type: :boolean,
          description: "The server answered only with the pre-1.7 protocol."
        },
        hostname: %Schema{
          type: :string,
          description: "Address from the request, lowercased, without the port.",
          example: "craftmc.pl"
        },
        ip: %Schema{
          type: :string,
          description: "IP the API connected to.",
          example: "141.94.231.68"
        },
        port: %Schema{
          type: :integer,
          description: "Game port (from SRV, the address, or 25565).",
          example: 25_565
        },
        srv: Srv,
        software: %Schema{
          type: :string,
          nullable: true,
          description:
            "Detected server software or proxy: Velocity, BungeeCord, Waterfall, Folia, Purpur, Pufferfish, Leaf, Paper, Spigot, Bukkit, NeoForge, Forge, Fabric, Quilt, Vanilla — from Query, otherwise from the version name. An unknown name from Query is returned as is.",
          example: "Velocity"
        },
        version: Version,
        players: Players,
        motd: Motd,
        favicon: %Schema{
          type: :string,
          nullable: true,
          description: "Icon as `data:image/png;base64,…` (64×64). Icons over 256 KB are skipped."
        },
        favicon_sha1: %Schema{
          type: :string,
          nullable: true,
          description: "SHA-1 of the `favicon` field (hex) — to detect icon changes."
        },
        links: Links,
        auth: Auth,
        eula_blocked: %Schema{
          type: :boolean,
          nullable: true,
          description:
            "The address or IP is on Mojang's list of servers blocked for breaking the EULA (the game refuses to join); `null` when the list could not be loaded."
        },
        network: Network,
        secure_chat: SecureChat,
        forge: Forge,
        modpack: Modpack,
        query: Query,
        bedrock: Bedrock,
        timings: Timings
      },
      required: [
        :online,
        :legacy,
        :hostname,
        :ip,
        :port,
        :srv,
        :software,
        :version,
        :players,
        :motd,
        :favicon,
        :favicon_sha1,
        :links,
        :auth,
        :eula_blocked,
        :network,
        :secure_chat,
        :forge,
        :modpack,
        :query,
        :bedrock,
        :timings
      ]
    })
  end

  defmodule McsrvstatResponse do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "McsrvstatResponse",
      description: "Status with `client=mcsrvstat` — data from mcsrvstat.us in a flat format.",
      type: :object,
      properties: %{
        online: %Schema{type: :boolean},
        ip: %Schema{type: :string, nullable: true},
        port: %Schema{type: :integer, nullable: true},
        version: %Schema{type: :string, nullable: true},
        online_players: %Schema{type: :integer, nullable: true},
        max_players: %Schema{type: :integer, nullable: true},
        motd: %Schema{
          type: :array,
          nullable: true,
          items: %Schema{type: :string},
          description: "Plain lines; surrounding spaces are not trimmed."
        },
        hostname: %Schema{type: :string, nullable: true, description: "Always `null`."},
        protocol: %Schema{type: :integer, nullable: true, description: "Always `null`."},
        latency: %Schema{type: :integer, nullable: true, description: "Always `null`."},
        favicon: %Schema{type: :string, nullable: true, description: "Always `null`."},
        players_sample: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "Always empty."
        },
        mods: %Schema{type: :array, items: %Schema{type: :string}, description: "Always empty."}
      },
      required: [:online]
    })
  end

  defmodule Offline do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Offline",
      description: "The server is offline, does not exist, or did not answer within 5 seconds.",
      type: :object,
      properties: %{online: %Schema{type: :boolean, enum: [false]}},
      required: [:online],
      example: %{online: false}
    })
  end

  defmodule Error do
    @moduledoc false
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Error",
      type: :object,
      properties: %{
        error: %Schema{
          type: :string,
          enum: ["invalid_address", "unknown_client"],
          description:
            "`invalid_address` — the address is in an unsupported form; `unknown_client` — unknown `client` value."
        },
        clients: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "With `unknown_client`: the available values."
        }
      },
      required: [:error]
    })
  end
end
