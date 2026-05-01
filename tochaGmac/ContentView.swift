import SwiftUI
import NetworkExtension
import AppKit

struct ContentView: View {
    @StateObject private var store = MacConfigStore()

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 500)
                .navigationTitle("tochkaG")
        } detail: {
            detail
        }
        .sheet(item: $store.addMode) { mode in
            AddConfigMacView(store: store, mode: mode)
        }
        .frame(minWidth: 800, idealWidth: 900, minHeight: 600, idealHeight: 700)
    }

    @ViewBuilder
    private var sidebar: some View {
        if store.configs.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Нет конфигураций")
                    .foregroundStyle(.secondary)
                Menu("Добавить") {
                    Button("Добавить по URL")     { store.addMode = .url }
                    Button("Добавить подписку")   { store.addMode = .subscription }
                    Button("Добавить файл .conf") { store.addMode = .importFile }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(store.configs, selection: $store.selectedID) { config in
                ConfigRowView(config: config, store: store)
                    .tag(config.id)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    AddConfigSidebarButton(store: store)
                        .background(.bar)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let id = store.selectedID,
           let config = store.configs.first(where: { $0.id == id }) {
            ConfigDetailMacView(config: config, store: store)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Выберите конфигурацию")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct ConfigRowView: View {
    let config: VPNConfig
    @ObservedObject var store: MacConfigStore

    var statusColor: Color {
        guard config.isActive else { return .secondary }
        switch store.vpnStatus {
        case .connected:                  return .green
        case .connecting, .disconnecting: return .orange
        default:                          return .secondary
        }
    }

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name).fontWeight(.medium)
                Text(config.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(config.protocolType.rawValue.uppercased())
                .font(.caption2)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.vertical, 2)
    }
}

struct ConfigDetailMacView: View {
    let config: VPNConfig
    @ObservedObject var store: MacConfigStore
    @StateObject private var ping = PingService()

    var statusLabel: String {
        guard config.isActive else { return "Отключено" }
        switch store.vpnStatus {
        case .connected:     return "Подключено"
        case .connecting:    return "Подключение..."
        case .disconnecting: return "Отключение..."
        default:             return "Отключено"
        }
    }

    var isConnected: Bool { config.isActive && store.vpnStatus == .connected }
    var isLoading:   Bool { config.isActive && (store.vpnStatus == .connecting || store.vpnStatus == .disconnecting) }

    var body: some View {
        VStack(spacing: 24) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .saturation(isConnected ? 1.0 : 0.0)
                .opacity(isConnected ? 1.0 : 0.55)
                .animation(.easeInOut(duration: 0.25), value: isConnected)
                .symbolEffect(.pulse, isActive: isLoading)
            Text(config.name).font(.title2).fontWeight(.semibold)
            Text(statusLabel).foregroundStyle(isConnected ? .green : .secondary)
            pingLabel
            Button(action: { store.toggle(config) }) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text(isConnected ? "Отключить" : "Подключить").frame(width: 120)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(isConnected ? .red : .blue)
            .disabled(isLoading)
            Divider().padding(.horizontal, 40)
            GroupBox { configDetails }.padding(.horizontal, 40)
            Button("Удалить конфигурацию", role: .destructive) { store.delete(config) }
                .padding(.top, 8)
        }
        .padding(.top, 40)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { startPing() }
        .onChange(of: config.id) { _, _ in startPing() }
        .onDisappear { ping.stop() }
    }

    private var pingTarget: (String, UInt16, PingService.Proto)? {
        switch config {
        case .vless(let v):
            return (v.address, UInt16(v.port) ?? 443, .tcp)
        case .wireguard(let w):
            let parts = w.endpoint.split(separator: ":")
            guard parts.count == 2,
                  let port = UInt16(parts[1]) else { return nil }
            return (String(parts[0]), port, .udp)
        }
    }

    private func startPing() {
        guard let (host, port, proto) = pingTarget else { return }
        ping.start(host: host, port: port, proto: proto)
    }

    @ViewBuilder
    private var pingLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "wave.3.right")
                .font(.caption)
            if ping.isMeasuring && ping.latencyMs == nil {
                Text("измерение…")
            } else if let ms = ping.latencyMs {
                Text("\(ms) мс")
                    .foregroundStyle(pingColor(ms))
            } else {
                Text("нет ответа")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func pingColor(_ ms: Int) -> Color {
        switch ms {
        case ..<100:  return .green
        case ..<250:  return .orange
        default:      return .red
        }
    }

    @ViewBuilder
    var configDetails: some View {
        switch config {
        case .vless(let vl):
            VStack(alignment: .leading, spacing: 6) {
                DetailRow(label: "Адрес",       value: "\(vl.address):\(vl.port)")
                DetailRow(label: "UUID",         value: vl.uuid)
                DetailRow(label: "Сеть",         value: vl.network)
                DetailRow(label: "Безопасность", value: vl.security)
                if !vl.sni.isEmpty  { DetailRow(label: "SNI",  value: vl.sni) }
                if !vl.flow.isEmpty { DetailRow(label: "Flow", value: vl.flow) }
            }
        case .wireguard(let wg):
            VStack(alignment: .leading, spacing: 6) {
                DetailRow(label: "Endpoint",    value: wg.endpoint)
                DetailRow(label: "Адрес",       value: wg.address)
                DetailRow(label: "DNS",         value: wg.dns)
                DetailRow(label: "AllowedIPs",  value: wg.allowedIPs)
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
            Text(value).fontWeight(.medium).textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
    }
}

struct AddConfigSidebarButton: View {
    @ObservedObject var store: MacConfigStore
    @State private var isHovered = false

    var body: some View {
        Menu {
            Button("Добавить по URL")     { store.addMode = .url }
            Button("Добавить подписку")   { store.addMode = .subscription }
            Button("Добавить файл .conf") { store.addMode = .importFile }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.tint)
                Text("Добавить")
                    .foregroundStyle(.primary)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.secondary.opacity(0.15) : Color.clear)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .onHover { isHovered = $0 }
    }
}
