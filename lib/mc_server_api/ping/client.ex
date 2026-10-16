defmodule McServerApi.Ping.Client do
  @moduledoc """
  Asks a Minecraft server for its status directly, without any third-party API.

  Three checks run at the same time once the address is resolved:

    * Server List Ping over TCP — required, the server counts as online only if it answers,
    * UDP Query on the same port — software and plugins, only if `enable-query` is on,
    * Bedrock ping on UDP #{McServerApi.Ping.Bedrock.default_port()} — whether phones and consoles can join.

  `status/2` tells an unreachable server (`{:error, reason}`) apart from one that
  answered, which matters for statistics: "could not measure" is not "0 players".
  """

  @behaviour McServerApi.ServerStatus

  alias McServerApi.Ping.Bedrock
  alias McServerApi.Ping.BlockedServers
  alias McServerApi.Ping.Legacy
  alias McServerApi.Ping.Login
  alias McServerApi.Ping.Network
  alias McServerApi.Ping.Protocol
  alias McServerApi.Ping.Query
  alias McServerApi.Ping.Response
  alias McServerApi.Ping.Status
  alias McServerApi.Ping.Versions

  @default_port 25_565
  @default_timeout 5_000
  @extra_timeout 800

  @software [
    {"velocity", "Velocity"},
    {"bungeecord", "BungeeCord"},
    {"waterfall", "Waterfall"},
    {"folia", "Folia"},
    {"purpur", "Purpur"},
    {"pufferfish", "Pufferfish"},
    {"leaf", "Leaf"},
    {"paper", "Paper"},
    {"spigot", "Spigot"},
    {"bukkit", "Bukkit"},
    {"neoforge", "NeoForge"},
    {"forge", "Forge"},
    {"fabric", "Fabric"},
    {"quilt", "Quilt"},
    {"vanilla", "Vanilla"}
  ]

  @type option ::
          {:timeout, pos_integer()}
          | {:resolve_srv, boolean()}
          | {:query, boolean()}
          | {:bedrock, boolean()}
          | {:network, boolean()}
          | {:blocked, boolean()}
          | {:login, boolean()}

  @doc """
  Pings `address` (`host`, `host:port`, `ip:port` or `[ipv6]:port`).

  Without an explicit port, the `_minecraft._tcp` SRV record is tried first and
  port #{@default_port} is the fallback, the same way the game client resolves it.

  Options: `:timeout` — total time budget in ms (default #{@default_timeout});
  `:resolve_srv`, `:query`, `:bedrock`, `:network`, `:blocked` — set to `false` to skip that step;
  `:login` — set to `true` to check online/offline mode with a login attempt (see `McServerApi.Ping.Login`).
  """
  @spec status(String.t(), [option()]) :: {:ok, Response.t()} | {:error, term()}
  def status(address, opts \\ []) do
    started = now()
    deadline = started + Keyword.get(opts, :timeout, @default_timeout)

    with {:ok, host, port} <- parse_address(address),
         {connect_host, connect_port, srv} <-
           resolve(host, port, Keyword.get(opts, :resolve_srv, true)),
         {:ok, ip} <- lookup_ip(connect_host) do
      dns_ms = now() - started
      extras = start_extras(host, connect_host, ip, connect_port, opts, deadline)

      case connect_and_ping(ip, host, connect_port, deadline) do
        {:ok, status, connect_ms, status_ms, latency_ms} ->
          timings = %{
            dns_ms: dns_ms,
            connect_ms: connect_ms,
            status_ms: status_ms,
            latency_ms: latency_ms
          }

          {:ok,
           build(
             status,
             false,
             host,
             ip,
             connect_port,
             srv,
             extras,
             opts,
             deadline,
             timings,
             started
           )}

        {:error, {:protocol, reason}} ->
          case Legacy.ping(ip, connect_port, max(remaining(deadline), 1)) do
            {:ok, status} ->
              status =
                Map.merge(%{favicon: nil, secure_chat: nil, forge: nil, modpack: nil}, status)

              timings = %{dns_ms: dns_ms, connect_ms: nil, status_ms: nil, latency_ms: nil}

              {:ok,
               build(
                 status,
                 true,
                 host,
                 ip,
                 connect_port,
                 srv,
                 extras,
                 opts,
                 deadline,
                 timings,
                 started
               )}

            _legacy_error ->
              shutdown_extras(extras)
              {:error, reason}
          end

        error ->
          shutdown_extras(extras)
          error
      end
    end
  end

  defp build(status, legacy, host, ip, port, srv, extras, opts, deadline, timings, started) do
    login =
      Keyword.get(opts, :login, false) &&
        run(fn ->
          Login.detect(
            ip,
            port,
            host,
            status.version.protocol,
            max(min(@extra_timeout * 2, remaining(deadline)), 1)
          )
        end)

    results = Map.new(extras, fn {key, task} -> {key, await(task)} end)
    login = if login, do: await(login) || :login_failed
    query = results.query

    %Response{
      online: true,
      legacy: legacy,
      hostname: host,
      ip: ip |> :inet.ntoa() |> to_string(),
      port: port,
      srv: srv,
      software: software(query, status.version.name),
      version:
        Map.merge(status.version, %{
          protocol_name: Versions.protocol_name(status.version.protocol),
          range: Versions.range(status.version.name_clean)
        }),
      players: status.players,
      motd: status.motd,
      favicon: status.favicon,
      favicon_sha1:
        status.favicon && :crypto.hash(:sha, status.favicon) |> Base.encode16(case: :lower),
      links: Status.links(status.motd.clean),
      auth: auth(login, status.players.sample),
      eula_blocked: results.blocked,
      network: results.network,
      secure_chat: status.secure_chat,
      forge: status.forge,
      modpack: status.modpack,
      query: query,
      bedrock:
        results.bedrock &&
          Map.put(results.bedrock, :verified, bedrock_verified?(results.bedrock, host, port)),
      timings: Map.put(timings, :total_ms, now() - started)
    }
  end

  # Anti-DDoS front-ends share IPs between customers, so a Bedrock server on port 19132 of the same IP
  # may belong to someone else. It counts as this server's only on the Java port itself, or when the
  # Bedrock MOTD mentions the server's name.
  defp bedrock_verified?(%{port: bedrock_port}, _host, port) when bedrock_port == port, do: true

  defp bedrock_verified?(%{motd: motd}, host, _port) do
    name =
      host
      |> String.split(".")
      |> Enum.reverse()
      |> Enum.at(1, host)
      |> String.replace(~r/[^a-z0-9]/, "")

    motd_text = motd |> Enum.join(" ") |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")

    String.length(name) >= 3 and String.contains?(motd_text, name)
  end

  defp auth(%{mode: mode, disconnect_reason: reason, protocol: protocol}, _sample),
    do: %{mode: mode, source: :login, login_protocol: protocol, disconnect_reason: reason}

  defp auth(:login_failed, sample),
    do:
      Map.merge(auth(nil, sample), %{login_protocol: nil, error: "no answer to the login attempt"})

  defp auth(_no_login, sample) do
    case Status.auth_hint(sample) do
      nil -> %{mode: :unknown, source: nil, disconnect_reason: nil}
      mode -> %{mode: mode, source: :player_sample, disconnect_reason: nil}
    end
  end

  @impl McServerApi.ServerStatus
  @doc "Status for the web page: an unreachable server is reported as offline."
  @spec call(String.t(), [option()]) :: Response.t()
  def call(address, opts \\ []) do
    case status(String.trim(address), opts) do
      {:ok, response} -> response
      {:error, _reason} -> %Response{online: false}
    end
  end

  @doc false
  @spec parse_address(String.t()) ::
          {:ok, String.t(), :inet.port_number() | nil} | {:error, :invalid_address}
  def parse_address(address) do
    case Regex.run(~r/^\[([0-9a-fA-F:]+)\](?::(\d{1,5}))?$|^([^:\s\/]+)(?::(\d{1,5}))?$/, address) do
      [_, ipv6] -> {:ok, ipv6, nil}
      [_, ipv6, port] -> with_port(ipv6, port)
      [_, "", "", host] -> {:ok, String.downcase(host), nil}
      [_, "", "", host, port] -> with_port(String.downcase(host), port)
      _ -> {:error, :invalid_address}
    end
  end

  defp with_port(host, ""), do: {:ok, host, nil}

  defp with_port(host, port) do
    case String.to_integer(port) do
      port when port in 1..65_535 -> {:ok, host, port}
      _ -> {:error, :invalid_address}
    end
  end

  defp resolve(host, port, _resolve_srv) when is_integer(port), do: {host, port, nil}

  defp resolve(host, nil, resolve_srv) do
    if resolve_srv and not ip_address?(host) do
      case :inet_res.lookup(~c"_minecraft._tcp.#{host}", :in, :srv, timeout: 2_000) do
        [_ | _] = records ->
          {_priority, _weight, port, target} = Enum.min_by(records, &elem(&1, 0))
          target = target |> to_string() |> String.trim_trailing(".")
          {target, port, %{target: target, port: port}}

        [] ->
          {host, @default_port, nil}
      end
    else
      {host, @default_port, nil}
    end
  end

  defp ip_address?(host), do: match?({:ok, _ip}, :inet.parse_address(String.to_charlist(host)))

  defp lookup_ip(host) do
    host = String.to_charlist(host)

    case :inet.getaddr(host, :inet) do
      {:ok, ip} -> {:ok, ip}
      {:error, _reason} -> :inet.getaddr(host, :inet6)
    end
  end

  defp connect_and_ping(ip, host, port, deadline) do
    started = now()

    case :gen_tcp.connect(ip, port, [:binary, active: false, packet: :raw], remaining(deadline)) do
      {:ok, socket} ->
        connect_ms = now() - started

        try do
          case ping(socket, host, port, deadline) do
            {:ok, status, status_ms, latency_ms} ->
              {:ok, status, connect_ms, status_ms, latency_ms}

            {:error, :timeout} ->
              {:error, :timeout}

            {:error, reason} ->
              {:error, {:protocol, reason}}
          end
        after
          :gen_tcp.close(socket)
        end

      error ->
        error
    end
  end

  defp ping(socket, host, port, deadline) do
    started = now()
    payload = System.unique_integer([:positive])

    with :ok <- :gen_tcp.send(socket, Protocol.handshake(host, port) <> Protocol.status_request()),
         {:ok, 0x00, response, rest} <- receive_packet(socket, <<>>, deadline),
         {:ok, json, _rest} <- Protocol.decode_string(response),
         {:ok, status} <- Status.parse(json) do
      status_ms = now() - started
      {:ok, status, status_ms, measure_latency(socket, rest, payload, deadline)}
    else
      {:ok, _other_id, _payload, _rest} -> {:error, :unexpected_packet}
      {:error, reason} -> {:error, reason}
    end
  end

  # Latency is a bonus: some servers close the connection after the status response.
  defp measure_latency(socket, buffer, payload, deadline) do
    started = now()

    with :ok <- :gen_tcp.send(socket, Protocol.ping(payload)),
         {:ok, 0x01, <<^payload::signed-64>>, _rest} <- receive_packet(socket, buffer, deadline) do
      now() - started
    else
      _no_pong -> nil
    end
  end

  defp receive_packet(socket, buffer, deadline) do
    case Protocol.decode_packet(buffer) do
      :incomplete ->
        with {:ok, data} <- recv(socket, deadline),
             true <- byte_size(buffer) + byte_size(data) <= Protocol.max_packet_size() + 8 do
          receive_packet(socket, buffer <> data, deadline)
        else
          false -> {:error, :packet_too_large}
          error -> error
        end

      result ->
        result
    end
  end

  defp recv(socket, deadline) do
    case remaining(deadline) do
      0 -> {:error, :timeout}
      timeout -> :gen_tcp.recv(socket, 0, timeout)
    end
  end

  defp start_extras(host, connect_host, ip, port, opts, deadline) do
    timeout = max(min(@extra_timeout, remaining(deadline)), 1)
    ip_text = ip |> :inet.ntoa() |> to_string()
    # Geyser listens either on the Bedrock default port or on the Java port itself.
    bedrock_ports = Enum.uniq([Bedrock.default_port(), port])

    %{
      query: Keyword.get(opts, :query, true) && run(fn -> Query.query(ip, port, timeout) end),
      bedrock:
        Keyword.get(opts, :bedrock, true) &&
          run(fn -> first_bedrock_answer(ip, bedrock_ports, timeout) end),
      network:
        Keyword.get(opts, :network, true) && run(fn -> {:ok, Network.info(connect_host, ip)} end),
      blocked:
        Keyword.get(opts, :blocked, true) &&
          run(fn ->
            case BlockedServers.blocked?(host, ip_text, @extra_timeout * 2) do
              nil -> {:error, :list_unavailable}
              blocked -> {:ok, blocked}
            end
          end)
    }
  end

  defp first_bedrock_answer(ip, ports, timeout) do
    results =
      ports
      |> Enum.map(fn port -> Task.async(fn -> Bedrock.ping(ip, port, timeout) end) end)
      |> Task.yield_many(timeout + 100)
      |> Enum.map(fn {task, result} -> result || Task.shutdown(task, :brutal_kill) end)

    Enum.find_value(results, {:error, :no_answer}, fn
      {:ok, {:ok, result}} -> {:ok, result}
      _ -> nil
    end)
  end

  # A failing optional check must never take the main ping down with it.
  defp run(fun) do
    Task.async(fn ->
      try do
        fun.()
      rescue
        _error -> {:error, :crashed}
      end
    end)
  end

  defp await(false), do: nil

  defp await(task) do
    case Task.yield(task, @extra_timeout * 2 + 300) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, result}} -> result
      _no_answer -> nil
    end
  end

  defp shutdown_extras(extras) do
    for task <- Map.values(extras), task, do: Task.shutdown(task, :brutal_kill)
  end

  defp software(%{software: software}, _version) when is_binary(software),
    do: detect_software(software) || software

  defp software(_query, version), do: version && detect_software(version)

  defp detect_software(text) do
    text = String.downcase(text)

    Enum.find_value(@software, fn {needle, label} -> String.contains?(text, needle) && label end)
  end

  defp remaining(deadline), do: max(deadline - now(), 0)

  defp now, do: System.monotonic_time(:millisecond)
end
