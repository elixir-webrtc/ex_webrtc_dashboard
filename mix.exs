defmodule ExWebrtcDashboard.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_webrtc_dashboard,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:ex_webrtc, github: "elixir-webrtc/ex_webrtc", branch: "get-stats"}
    ]
  end
end
