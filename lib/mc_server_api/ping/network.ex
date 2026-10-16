defmodule McServerApi.Ping.Network do
  @moduledoc """
  What DNS says about a server: all addresses, CNAME, reverse DNS and the network
  (ASN, owner, country) its IP belongs to.

  The network lookup uses Team Cymru's public IP-to-ASN service over DNS, so it needs
  no API key and no HTTP request. See https://www.team-cymru.com/ip-asn-mapping
  """

  @lookup_timeout 800

  @type info :: %{
          ipv4: [String.t()],
          ipv6: [String.t()],
          cname: String.t() | nil,
          reverse_dns: String.t() | nil,
          asn: map() | nil
        }

  @spec info(String.t(), :inet.ip_address()) :: info()
  def info(host, ip) do
    lookups = [
      ipv4: fn -> addresses(host, :a) end,
      ipv6: fn -> addresses(host, :aaaa) end,
      cname: fn -> cname(host) end,
      reverse_dns: fn -> reverse_dns(ip) end,
      asn: fn -> asn(ip) end
    ]

    lookups
    |> Enum.map(fn {key, fun} -> {key, Task.async(fun)} end)
    |> Map.new(fn {key, task} ->
      value =
        case Task.yield(task, @lookup_timeout * 2) || Task.shutdown(task, :brutal_kill) do
          {:ok, value} -> value
          _ -> nil
        end

      {key, value}
    end)
    |> Map.update!(:ipv4, &(&1 || []))
    |> Map.update!(:ipv6, &(&1 || []))
  end

  defp addresses(host, type) do
    if ip_literal?(host) do
      []
    else
      host
      |> to_charlist()
      |> :inet_res.lookup(:in, type, timeout: @lookup_timeout)
      |> Enum.map(&(&1 |> :inet.ntoa() |> to_string()))
      |> Enum.sort()
    end
  end

  defp cname(host) do
    if ip_literal?(host) do
      nil
    else
      case :inet_res.lookup(to_charlist(host), :in, :cname, timeout: @lookup_timeout) do
        [target | _] -> target |> to_string() |> String.trim_trailing(".")
        [] -> nil
      end
    end
  end

  defp reverse_dns(ip) do
    case :inet_res.gethostbyaddr(ip, @lookup_timeout) do
      {:ok, {:hostent, name, _aliases, _type, _length, _addresses}} -> to_string(name)
      _ -> nil
    end
  end

  # "15169 | 8.8.8.0/24 | US | arin | 2023-12-28", then "15169 | US | arin | 2000-03-30 | GOOGLE - Google LLC, US".
  defp asn({a, b, c, d}) do
    with [origin | _] <- txt("#{d}.#{c}.#{b}.#{a}.origin.asn.cymru.com"),
         [number, prefix, country, registry | _] <- fields(origin) do
      # Several ASNs can announce the same prefix; the first one is used.
      number = number |> String.split(" ") |> hd()

      owner =
        case txt("AS#{number}.asn.cymru.com") do
          [description | _] -> description |> fields() |> List.last()
          [] -> nil
        end

      %{
        number: String.to_integer(number),
        name: owner,
        prefix: prefix,
        country: country,
        registry: registry
      }
    else
      _ -> nil
    end
  end

  defp asn(_ipv6), do: nil

  defp txt(name) do
    name
    |> to_charlist()
    |> :inet_res.lookup(:in, :txt, timeout: @lookup_timeout)
    |> Enum.map(&(&1 |> Enum.join() |> to_string()))
  end

  defp fields(text), do: text |> String.split("|") |> Enum.map(&String.trim/1)

  defp ip_literal?(host), do: match?({:ok, _}, :inet.parse_address(to_charlist(host)))
end
