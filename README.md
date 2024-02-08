# ExWebRTCDashboard

[![Hex.pm](https://img.shields.io/hexpm/v/ex_webrtc_dashboard.svg)](https://hex.pm/packages/ex_webrtc_dashboard)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/ex_webrtc_dashboard)

[ExWebRTC](https://github.com/elixir-webrtc/ex_webrtc) statistics visualization for the [Phoenix LiveDashboard](https://github.com/phoenixframework/phoenix_live_dashboard).

<p align="center">
  <img src="https://raw.githubusercontent.com/elixir-webrtc/ex_webrtc_dashboard/1958992207fb6badffe386c8eb4ecad288acf981/dashboard.gif" alt="ExWebRTC Dashboard" />
</p>

## Installation

1. Enable `LiveDashboard` by following these [instructions](https://github.com/phoenixframework/phoenix_live_dashboard?tab=readme-ov-file#installation).
In most cases you can skip this step as `Phoenix` comes with `LiveDashboard` enabled by default.

2. Add `:ex_webrtc_dashboard` to your list of dependencies

```elixir
def deps do
  [
    {:ex_webrtc_dashboard, "~> 0.1.1"}
  ]
end
```

3. Add `ExWebRTCDashboard` as an additional `LiveDashboard` page

```elixir
live_dashboard "/dashboard",
  additional_pages: [exwebrtc: ExWebRTCDashboard]
```

That's it!
`ExWebRTCDashboard` will automatically discover all of your peer connections and visualize their statistics.
