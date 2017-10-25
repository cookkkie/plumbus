defmodule Plumbus.Mixfile do
  use Mix.Project

  def project do
    [app: :plumbus,
     version: "0.1.1",
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [extra_applications: [:logger, :mnesia]]
  end

  defp deps do
    [{:websocket_client, github: "mee6/websocket_client"},
     {:poison, "~> 3.1"}]
  end
end
