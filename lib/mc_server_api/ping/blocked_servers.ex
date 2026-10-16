defmodule McServerApi.Ping.BlockedServers do
  @moduledoc """
  Mojang's list of servers banned for breaking the EULA. The game refuses to join them.
  """

  @url "https://sessionserver.mojang.com/blockedservers"
  @refresh_after_ms 3_600_000
  @cache_key {__MODULE__, :hashes}

  @doc "Whether the host or IP is blocked, or nil when the list could not be loaded."
  @spec blocked?(String.t(), String.t() | nil, pos_integer()) :: boolean() | nil
  def blocked?(host, ip, timeout) do
    case hashes(timeout) do
      nil ->
        nil

      hashes ->
        [host, ip]
        |> Enum.reject(&is_nil/1)
        |> Enum.flat_map(&patterns/1)
        |> Enum.any?(&MapSet.member?(hashes, sha1(&1)))
    end
  end

  @spec patterns(String.t()) :: [String.t()]
  def patterns(address) do
    parts = address |> String.downcase() |> String.split(".")

    if ipv4?(address) do
      for count <- 4..1//-1,
          do:
            Enum.take(parts, count)
            |> Enum.join(".")
            |> then(&if(count == 4, do: &1, else: &1 <> ".*"))
    else
      [
        address
        | for(
            count <- (length(parts) - 1)..1//-1,
            count > 0,
            do: "*." <> (parts |> Enum.take(-count) |> Enum.join("."))
          )
      ]
    end
  end

  defp hashes(timeout) do
    case :persistent_term.get(@cache_key, nil) do
      {hashes, loaded_at} when is_struct(hashes, MapSet) ->
        if now() - loaded_at < @refresh_after_ms, do: hashes, else: fetch(timeout) || hashes

      _ ->
        fetch(timeout)
    end
  end

  defp fetch(timeout) do
    case HTTPoison.get(@url, [], recv_timeout: timeout, timeout: timeout) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        hashes =
          body |> String.split("\n", trim: true) |> Enum.map(&String.trim/1) |> MapSet.new()

        :persistent_term.put(@cache_key, {hashes, now()})
        hashes

      _ ->
        nil
    end
  end

  defp sha1(text), do: :crypto.hash(:sha, text) |> Base.encode16(case: :lower)

  defp ipv4?(address),
    do: match?({:ok, {_, _, _, _}}, :inet.parse_ipv4strict_address(to_charlist(address)))

  defp now, do: System.monotonic_time(:millisecond)
end
