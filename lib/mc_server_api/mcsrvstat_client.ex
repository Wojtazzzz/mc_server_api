defmodule McServerApi.McsrvstatClient do
  alias McServerApi.ServerData

  def call(ip) do
    case HTTPoison.get("https://api.mcsrvstat.us/3/#{ip}") do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, json} = Jason.decode(body)

        case json do
          %{"online" => true} ->
            %ServerData{
              online: json |> Map.get("online"),
              ip: json |> Map.get("ip"),
              port: json |> Map.get("port"),
              max_players: json |> Map.get("players") |> Map.get("max"),
              online_players: json |> Map.get("players") |> Map.get("online"),
              version: json |> Map.get("version"),
              motd: json |> Map.get("motd") |> Map.get("clean")
            }

          _ ->
            %ServerData{
              online: false
            }
        end

      _ ->
        %ServerData{}
        # {:ok, %HTTPoison.Response{status_code: 404}} ->
        #   IO.puts("Not found :(")

        # {:error, %HTTPoison.Error{reason: reason}} ->
        #   IO.inspect(reason)
    end
  end
end
