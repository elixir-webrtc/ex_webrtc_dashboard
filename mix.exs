defmodule ExWebRTCDashboard.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/elixir-webrtc/ex_webrtc_dashboard"

  def project do
    [
      app: :ex_webrtc_dashboard,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      description: "ExWebRTC statistics visualization for the Phoenix LiveDashboard",
      package: package(),
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs() do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end

  defp deps do
    [
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:ex_webrtc, github: "elixir-webrtc/ex_webrtc"},
      {:ex_doc, "~> 0.31.0", only: :dev, runtime: false}
    ]
  end
end
