defmodule ExWebRTCDashboard do
  @moduledoc """
  ExWebRTC statistics visualization for the Phoenix LiveDashboard.
  """
  use Phoenix.LiveDashboard.PageBuilder

  alias ExWebRTC.PeerConnection

  @impl true
  def init(_opts) do
    {:ok, %{}, []}
  end

  @impl true
  def menu_link(_session, _caps) do
    {:ok, "WebRTC"}
  end

  @impl true
  def mount(params, _session, socket) do
    Process.send_after(self(), :update_stats, 1_000)

    nav = params["nav"]

    pc_pids =
      PeerConnection.get_all_running()
      |> Map.new(fn pid -> {encode_pid(pid), {pid, nil}} end)

    socket = assign(socket, pc_pids: pc_pids)
    socket = assign(socket, current_pc_str: nil)

    cond do
      nav == nil and pc_pids == %{} ->
        {:ok, socket}

      nav == nil ->
        to = live_dashboard_path(socket, socket.assigns.page, nav: List.first(Map.keys(pc_pids)))
        {:ok, push_navigate(socket, to: to)}

      nav != nil and pc_pids == %{} ->
        # don't do anything, render will inform that we are waiting for peer connections
        {:ok, socket}

      true ->
        with {:ok, {pc, nil}} <- Map.fetch(socket.assigns.pc_pids, nav),
             {:ok, pc_stats} <- fetch_stats(pc) do
          pc_str = encode_pid(pc)

          pc_pids = put_in(socket.assigns.pc_pids, [pc_str], {pc, pc_stats})

          socket =
            socket
            |> assign(current_pc: pc)
            |> assign(current_pc_str: pc_str)
            |> assign(pc_pids: pc_pids)

          {:ok, socket}
        else
          :error ->
            # redirect to any other pc
            nav = List.first(Map.keys(pc_pids))
            to = live_dashboard_path(socket, socket.assigns.page, nav: nav)
            {:ok, push_navigate(socket, to: to)}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @pc_pids == %{} do %>
      Waiting for PeerConnections to be spawned...
    <% else %>
      <.live_nav_bar id="navbar" page={@page}>
        <:item :for={{pc_str, {_pc, pc_stats}} <- @pc_pids} name={pc_str} method="redirect">
          <.summary peer_connection={pc_stats.peer_connection} transport={pc_stats.transport} />
          <.cert title="Local certificate" cert={pc_stats.local_certificate} />
          <.cert title="Remote certificate" cert={pc_stats.remote_certificate} />
          <.desc title="Local description" desc={pc_stats.local_desc} />
          <.desc title="Remote description" desc={pc_stats.remote_desc} />
          <.candidates title="Local candidates" candidates={pc_stats.local_cands} />
          <.candidates title="Remote candidates" candidates={pc_stats.remote_cands} />
          <.transport transport={pc_stats.transport} />

          <.inbound_rtp :for={inbound_rtp <- pc_stats.inbound_rtp} inbound_rtp={inbound_rtp} />
          <.outbound_rtp :for={outbound_rtp <- pc_stats.outbound_rtp} outbound_rtp={outbound_rtp} />
        </:item>
      </.live_nav_bar>
    <% end %>
    """
  end

  @impl true
  def handle_info(:update_stats, socket) do
    Process.send_after(self(), :update_stats, 1_000)
    socket = update_pc_pids(socket)
    pc_pids = socket.assigns.pc_pids

    cond do
      socket.assigns.current_pc_str == nil and pc_pids != %{} ->
        nav = List.first(Map.keys(socket.assigns.pc_pids))
        to = live_dashboard_path(socket, socket.assigns.page, nav: nav)
        {:noreply, push_navigate(socket, to: to)}

      socket.assigns.current_pc_str == nil ->
        {:noreply, socket}

      true ->
        pc = socket.assigns.current_pc
        pc_str = socket.assigns.current_pc_str
        {^pc, old_stats} = Map.fetch!(socket.assigns.pc_pids, pc_str)

        case fetch_stats(pc) do
          {:ok, stats} ->
            update_plots(stats, old_stats)
            pc_pids = put_in(socket.assigns.pc_pids, [pc_str], {pc, stats})
            socket = assign(socket, pc_pids: pc_pids)
            {:noreply, socket}

          :error ->
            pc_pids = Map.delete(socket.assigns.pc_pids, pc_str)

            socket =
              socket
              |> assign(current_pc_str: nil)
              |> assign(current_pc: nil)
              |> assign(pc_pids: pc_pids)

            {:noreply, socket}
        end
    end
  end

  @impl true
  def handle_info(_, socket) do
    {:noreply, socket}
  end

  defp update_pc_pids(socket) do
    pcs = PeerConnection.get_all_running()

    pc_pids =
      Map.new(pcs, fn pc ->
        pc_str = encode_pid(pc)
        {_pc, stats} = Map.get(socket.assigns.pc_pids, pc_str, {nil, nil})
        {pc_str, {pc, stats}}
      end)

    assign(socket, pc_pids: pc_pids)
  end

  defp summary(assigns) do
    ~H"""
    <div class="hidden">
      <.row>
        <:col>
          <.card inner_title="PeerConnection state">
            <%= @peer_connection.connection_state %>
          </.card>
        </:col>
        <:col>
          <.card inner_title="Signaling state">
            <%= @peer_connection.signaling_state %>
          </.card>
        </:col>
        <:col>
          <.card inner_title="Negotiation needed">
            <%= @peer_connection.negotiation_needed %>
          </.card>
        </:col>
      </.row>
      <.row>
        <:col>
          <.card inner_title="DTLS state">
            <%= @transport.dtls_state %>
          </.card>
        </:col>
        <:col>
          <.card inner_title="ICE state">
            <%= @transport.ice_state %>
          </.card>
        </:col>
        <:col>
          <.card inner_title="ICE gathering state">
            <%= @transport.ice_gathering_state %>
          </.card>
        </:col>
      </.row>
    </div>
    """
  end

  defp cert(assigns) do
    ~H"""
    <div class="mt-4">
      <h4><%= @title %></h4>
      <.row_table title="Cretificate" object={@cert}>
        <:row :let={cert} label="Fingerprint">
          <%= cert.fingerprint %>
        </:row>
        <:row :let={cert} label="Algorithm">
          <%= cert.fingerprint_algorithm %>
        </:row>
        <:row :let={cert} label="Base64 certificate">
          <%= cert.base64_certificate %>
        </:row>
      </.row_table>
    </div>
    """
  end

  defp desc(assigns) do
    ~H"""
    <div class="mt-4">
      <h4><%= @title %></h4>
      <.row_table title="Session Description" object={@desc}>
        <:row :let={desc} label="Type">
          <%= if desc do %>
            <%= desc.type %>
          <% end %>
        </:row>
        <:row :let={desc} label="SDP">
          <%= if desc do %>
            <%= desc.sdp %>
          <% end %>
        </:row>
      </.row_table>
    </div>
    """
  end

  defp transport(assigns) do
    ~H"""
    <div class="mt-4">
      <h4>Transport</h4>
      <.row_table title="Transport" object={@transport}>
        <:row :let={transport} label="Bytes sent">
          <%= transport.bytes_sent %>
        </:row>
        <:row :let={transport} label="Bytes received">
          <%= transport.bytes_received %>
        </:row>
        <:row :let={transport} label="Packets sent">
          <%= transport.packets_sent %>
        </:row>
        <:row :let={transport} label="Packets received">
          <%= transport.packets_received %>
        </:row>
        <:row :let={transport} label="ICE role">
          <%= transport.ice_role %>
        </:row>
        <:row :let={transport} label="ICE local ufrag">
          <%= transport.ice_local_ufrag %>
        </:row>
      </.row_table>

      <div class="mt-4 row">
        <.live_chart
          id="transport-bytes_sent"
          title="Bytes sent"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id="transport-bytes_sent_sec"
          title="Bytes sent/s"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id="transport-bytes_received"
          title="Bytes received"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id="transport-bytes_received_sec"
          title="Bytes received/s"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id="transport-packets_sent"
          title="Packets sent"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id="transport-packets_sent_sec"
          title="Packets sent/s"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id="transport-packets_received"
          title="Packets received"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id="transport-packets_received_sec"
          title="Packets received/s"
          kind={:last_value}
          prune_threshold={60}
        />
      </div>
    </div>
    """
  end

  defp candidates(assigns) do
    ~H"""
    <div class="mt-4">
      <h4><%= @title %></h4>
      <div class="card tabular-card mb-4 mt-4">
        <div class="card-body p-0">
          <div class="dash-table-wrapper">
            <table class="table table-hover dash-table">
              <thead>
                <tr>
                  <th>Address</th>
                  <th>Port</th>
                  <th>Protocol</th>
                  <th>Candidate type</th>
                  <th>Priority</th>
                  <th>Foundation</th>
                  <th>Related address</th>
                  <th>Related port</th>
                </tr>
              </thead>
              <tbody>
                <%= for cand <- Enum.sort(@candidates) do %>
                  <tr>
                    <td><%= :inet.ntoa(cand.address) %></td>
                    <td><%= cand.port %></td>
                    <td><%= cand.protocol %></td>
                    <td><%= cand.candidate_type %></td>
                    <td><%= cand.priority %></td>
                    <td><%= cand.foundation %></td>
                    <td>
                      <%= if cand.related_address do %>
                        <%= :inet.ntoa(cand.related_address) %>
                      <% end %>
                    </td>
                    <td><%= cand.related_port %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp inbound_rtp(assigns) do
    ~H"""
    <div class="mt-4">
      <h4>Inbound RTP <%= @inbound_rtp.id %></h4>

      <.row_table title={"Inbound RTP #{@inbound_rtp.id}"} object={@inbound_rtp}>
        <:row :let={inbound_rtp} label="Kind">
          <%= inbound_rtp.kind %>
        </:row>
        <:row :let={inbound_rtp} label="RID">
          <%= if inbound_rtp.rid != nil do %>
            <%= inspect(inbound_rtp.rid) %>
          <% else %>
            -
          <% end %>
        </:row>
        <:row :let={inbound_rtp} label="MID">
          <%= inspect(inbound_rtp.mid) %>
        </:row>
        <:row :let={inbound_rtp} label="SSRC">
          <%= inbound_rtp.ssrc %>
        </:row>
        <:row :let={inbound_rtp} label="Bytes received">
          <%= inbound_rtp.bytes_received %>
        </:row>
        <:row :let={inbound_rtp} label="Packets received">
          <%= inbound_rtp.packets_received %>
        </:row>
        <:row :let={inbound_rtp} label="Markers received">
          <%= inbound_rtp.markers_received %>
        </:row>
        <:row :let={inbound_rtp} label="NACK sent">
          <%= inbound_rtp.nack_count %>
        </:row>
        <:row :let={inbound_rtp} label="PLI sent">
          <%= inbound_rtp.pli_count %>
        </:row>
      </.row_table>

      <div class="mt-4 row">
        <.live_chart
          id={"inbound_rtp-bytes_received-#{@inbound_rtp.id}"}
          title="Bytes received"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"inbound_rtp-bytes_received_sec-#{@inbound_rtp.id}"}
          title="Bytes received/s"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"inbound_rtp-packets_received-#{@inbound_rtp.id}"}
          title="Packets received"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"inbound_rtp-packets_received_sec-#{@inbound_rtp.id}"}
          title="Packets received/s"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"inbound_rtp-markers_received-#{@inbound_rtp.id}"}
          title="Markers received"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"inbound_rtp-markers_received_sec-#{@inbound_rtp.id}"}
          title="Markers received/s"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"inbound_rtp-nack_count-#{@inbound_rtp.id}"}
          title="NACK sent"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"inbound_rtp-pli_count-#{@inbound_rtp.id}"}
          title="PLI sent"
          kind={:last_value}
          prune_threshold={60}
        />
      </div>
    </div>
    """
  end

  defp outbound_rtp(assigns) do
    ~H"""
    <div class="mt-4">
      <h4>Outbound RTP <%= @outbound_rtp.id %></h4>

      <.row_table title={"Outbound RTP #{@outbound_rtp.id}"} object={@outbound_rtp}>
        <:row :let={outbound_rtp} label="Kind">
          <%= outbound_rtp.kind %>
        </:row>
        <:row :let={outbound_rtp} label="MID">
          <%= inspect(outbound_rtp.mid) %>
        </:row>
        <:row :let={outbound_rtp} label="SSRC">
          <%= outbound_rtp.ssrc %>
        </:row>
        <:row :let={outbound_rtp} label="Bytes sent">
          <%= outbound_rtp.bytes_sent %>
        </:row>
        <:row :let={outbound_rtp} label="Packets sent">
          <%= outbound_rtp.packets_sent %>
        </:row>
        <:row :let={outbound_rtp} label="Retransmitted bytes sent">
          <%= outbound_rtp.retransmitted_bytes_sent %>
        </:row>
        <:row :let={outbound_rtp} label="Retransmitted packets sent">
          <%= outbound_rtp.retransmitted_packets_sent %>
        </:row>
        <:row :let={outbound_rtp} label="Markers sent">
          <%= outbound_rtp.markers_sent %>
        </:row>
        <:row :let={outbound_rtp} label="NACK received">
          <%= outbound_rtp.nack_count %>
        </:row>
        <:row :let={outbound_rtp} label="PLI received">
          <%= outbound_rtp.pli_count %>
        </:row>
      </.row_table>

      <div class="mt-4 row">
        <.live_chart
          id={"outbound_rtp-bytes_sent-#{@outbound_rtp.id}"}
          title="Bytes sent"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"outbound_rtp-bytes_sent_sec-#{@outbound_rtp.id}"}
          title="Bytes sent/s"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"outbound_rtp-packets_sent-#{@outbound_rtp.id}"}
          title="Packets sent"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"outbound_rtp-packets_sent_sec-#{@outbound_rtp.id}"}
          title="Packets sent/s"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"outbound_rtp-retransmitted_bytes_sent-#{@outbound_rtp.id}"}
          title="Retransmitted bytes sent"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"outbound_rtp-retransmitted_bytes_sent_sec-#{@outbound_rtp.id}"}
          title="Retransmitted bytes sent/s"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"outbound_rtp-retransmitted_packets_sent-#{@outbound_rtp.id}"}
          title="Retransmitted packets sent"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"outbound_rtp-retransmitted_packets_sent_sec-#{@outbound_rtp.id}"}
          title="Retransmitted packets sent/s"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"outbound_rtp-markers_sent-#{@outbound_rtp.id}"}
          title="Markser sent"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"outbound_rtp-markers_sent_sec-#{@outbound_rtp.id}"}
          title="Markser sent/s"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"outbound_rtp-nack_count-#{@outbound_rtp.id}"}
          title="NACK received"
          kind={:last_value}
          prune_threshold={60}
        />
        <.live_chart
          id={"outbound_rtp-pli_count-#{@outbound_rtp.id}"}
          title="PLI received"
          kind={:last_value}
          prune_threshold={60}
        />
      </div>
    </div>
    """
  end

  defp fetch_stats(pc) do
    try do
      stats = PeerConnection.get_stats(pc)

      local_desc = PeerConnection.get_current_local_description(pc)
      remote_desc = PeerConnection.get_current_remote_description(pc)

      groups = Enum.group_by(Map.values(stats), fn stats -> stats.type end)

      stats =
        %{
          peer_connection: stats.peer_connection,
          local_certificate: stats.local_certificate,
          remote_certificate: stats.remote_certificate,
          local_desc: local_desc,
          remote_desc: remote_desc,
          local_cands: Map.get(groups, :local_candidate, []),
          remote_cands: Map.get(groups, :remote_candidate, []),
          transport: stats.transport,
          inbound_rtp: Map.get(groups, :inbound_rtp, []),
          outbound_rtp: Map.get(groups, :outbound_rtp, [])
        }

      {:ok, stats}
    catch
      :exit, _ ->
        :error
    end
  end

  defp update_plots(stats, old_stats) do
    send_data_to_chart("transport-bytes_sent", [
      {nil, stats.transport.bytes_sent, System.system_time(:microsecond)}
    ])

    send_data_to_chart("transport-bytes_sent_sec", [
      {nil, per_sec_stat(stats.transport, old_stats.transport, :bytes_sent),
       System.system_time(:microsecond)}
    ])

    send_data_to_chart("transport-bytes_received", [
      {nil, stats.transport.bytes_received, System.system_time(:microsecond)}
    ])

    send_data_to_chart("transport-bytes_received_sec", [
      {nil, per_sec_stat(stats.transport, old_stats.transport, :bytes_received),
       System.system_time(:microsecond)}
    ])

    send_data_to_chart("transport-packets_sent", [
      {nil, stats.transport.packets_sent, System.system_time(:microsecond)}
    ])

    send_data_to_chart("transport-packets_sent_sec", [
      {nil, per_sec_stat(stats.transport, old_stats.transport, :packets_sent),
       System.system_time(:microsecond)}
    ])

    send_data_to_chart("transport-packets_received", [
      {nil, stats.transport.packets_received, System.system_time(:microsecond)}
    ])

    send_data_to_chart("transport-packets_received_sec", [
      {nil, per_sec_stat(stats.transport, old_stats.transport, :packets_received),
       System.system_time(:microsecond)}
    ])

    for inbound_rtp <- stats.inbound_rtp do
      old_inbound_rtp = Enum.find(old_stats.inbound_rtp, &(&1.id == inbound_rtp.id))
      timestamp = to_micro(inbound_rtp.timestamp)

      send_data_to_chart("inbound_rtp-bytes_received-#{inbound_rtp.id}", [
        {nil, inbound_rtp.bytes_received, timestamp}
      ])

      send_data_to_chart("inbound_rtp-bytes_received_sec-#{inbound_rtp.id}", [
        {nil, per_sec_stat(inbound_rtp, old_inbound_rtp, :bytes_received), timestamp}
      ])

      send_data_to_chart("inbound_rtp-packets_received-#{inbound_rtp.id}", [
        {nil, inbound_rtp.packets_received, timestamp}
      ])

      send_data_to_chart("inbound_rtp-packets_received_sec-#{inbound_rtp.id}", [
        {nil, per_sec_stat(inbound_rtp, old_inbound_rtp, :packets_received), timestamp}
      ])

      send_data_to_chart("inbound_rtp-markers_received-#{inbound_rtp.id}", [
        {nil, inbound_rtp.markers_received, timestamp}
      ])

      send_data_to_chart("inbound_rtp-markers_received_sec-#{inbound_rtp.id}", [
        {nil, per_sec_stat(inbound_rtp, old_inbound_rtp, :markers_received), timestamp}
      ])

      send_data_to_chart("inbound_rtp-nack_count-#{inbound_rtp.id}", [
        {nil, inbound_rtp.nack_count, timestamp}
      ])

      send_data_to_chart("inbound_rtp-pli_count-#{inbound_rtp.id}", [
        {nil, inbound_rtp.pli_count, timestamp}
      ])
    end

    for outbound_rtp <- stats.outbound_rtp do
      old_outbound_rtp = Enum.find(old_stats.outbound_rtp, &(&1.id == outbound_rtp.id))
      timestamp = to_micro(outbound_rtp.timestamp)

      send_data_to_chart("outbound_rtp-bytes_sent-#{outbound_rtp.id}", [
        {nil, outbound_rtp.bytes_sent, timestamp}
      ])

      send_data_to_chart("outbound_rtp-bytes_sent_sec-#{outbound_rtp.id}", [
        {nil, per_sec_stat(outbound_rtp, old_outbound_rtp, :bytes_sent), timestamp}
      ])

      send_data_to_chart("outbound_rtp-packets_sent-#{outbound_rtp.id}", [
        {nil, outbound_rtp.packets_sent, timestamp}
      ])

      send_data_to_chart("outbound_rtp-packets_sent_sec-#{outbound_rtp.id}", [
        {nil, per_sec_stat(outbound_rtp, old_outbound_rtp, :packets_sent), timestamp}
      ])

      send_data_to_chart("outbound_rtp-retransmitted_bytes_sent-#{outbound_rtp.id}", [
        {nil, outbound_rtp.retransmitted_bytes_sent, timestamp}
      ])

      send_data_to_chart("outbound_rtp-retransmitted_bytes_sent_sec-#{outbound_rtp.id}", [
        {nil, per_sec_stat(outbound_rtp, old_outbound_rtp, :retransmitted_bytes_sent), timestamp}
      ])

      send_data_to_chart("outbound_rtp-retransmitted_packets_sent-#{outbound_rtp.id}", [
        {nil, outbound_rtp.retransmitted_packets_sent, timestamp}
      ])

      send_data_to_chart("outbound_rtp-retransmitted_packets_sent_sec-#{outbound_rtp.id}", [
        {nil, per_sec_stat(outbound_rtp, old_outbound_rtp, :retransmitted_packets_sent),
         timestamp}
      ])

      send_data_to_chart("outbound_rtp-markers_sent-#{outbound_rtp.id}", [
        {nil, outbound_rtp.markers_sent, timestamp}
      ])

      send_data_to_chart("outbound_rtp-markers_sent_sec-#{outbound_rtp.id}", [
        {nil, per_sec_stat(outbound_rtp, old_outbound_rtp, :markers_sent), timestamp}
      ])

      send_data_to_chart("outbound_rtp-nack_count-#{outbound_rtp.id}", [
        {nil, outbound_rtp.nack_count, timestamp}
      ])

      send_data_to_chart("outbound_rtp-pli_count-#{outbound_rtp.id}", [
        {nil, outbound_rtp.pli_count, timestamp}
      ])
    end
  end

  defp to_micro(milliseconds), do: milliseconds * 1_000

  defp per_sec_stat(_new_stats, nil, _key), do: 0

  defp per_sec_stat(new_stats, old_stats, key) do
    ts_diff = (new_stats[:timestamp] - old_stats[:timestamp]) / 1000
    (new_stats[key] - old_stats[key]) / ts_diff
  end

  # Converts a map into two-column table.
  #
  # ach row consists of two columns where the first column is a map key
  # and the second column is a map value.
  slot :row do
    attr :label, :string, required: true
  end

  attr :title, :string,
    required: true,
    doc: "Title of the table. It will appear as the first row taking both columns."

  attr :object, :map, required: true, doc: "Object that will be passed to every row."

  defp row_table(assigns) do
    ~H"""
    <div class="mt-4">
      <div class="card tabular-card mb-4 mt-4">
        <div class="card-body p-0">
          <div class="dash-table-wrapper">
            <table class="table table-hover dash-table">
              <thead>
                <tr>
                  <th colspan="2"><%= @title %></th>
                </tr>
              </thead>
              <tbody>
                <%= for row <- @row do %>
                  <tr>
                    <td><%= row.label %></td>
                    <td class="text-break"><%= render_slot(row, @object) %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
