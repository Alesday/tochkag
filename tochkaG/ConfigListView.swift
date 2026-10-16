// ConfigListView.swift
// TochkaG — перекрашен под BrandKit (liquid glass / aurora).
// Логика не изменена: pin-top-6, пинг 30s, store.toggle/delete, NavigationLink в detail.
// Color(hex:) теперь живёт в BrandKit.swift (не дублируем здесь).

import SwiftUI
import Network
import SafariServices

struct ConfigListView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var showAdd  = false
    @State private var showLogs = false
    @State private var subToDelete: String? = nil

    var wgConfigs:    [VPNConfig] { store.configs.filter { $0.protocolType == .wireguard } }
    var vlessConfigs: [VPNConfig] {
        let pinnedTopCount = 6
        let all = store.configs.filter { $0.protocolType == .vless }
        let pinnedCount = min(pinnedTopCount, all.count)
        let pinned = Array(all.prefix(pinnedCount))
        let rest   = Array(all.dropFirst(pinnedCount))

        let restSorted = rest.sorted { a, b in
            let pa = store.pingMs[a.id] ?? nil
            let pb = store.pingMs[b.id] ?? nil
            switch (pa, pb) {
            case (let x?, let y?): return x < y
            case (_?, nil):        return true
            case (nil, _?):        return false
            default:               return a.name < b.name
            }
        }
        return pinned + restSorted
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            list
        }
        .preferredColorScheme(.dark)
        .navigationTitle("")
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            store.fetchSubscriptionInfo()
        }
        .sheet(isPresented: $showAdd) { AddConfigView().environmentObject(store) }
        .overlay(alignment: .bottomTrailing) {
            #if DEBUG
            Button { showLogs = true } label: {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(Circle().fill(Color.black.opacity(0.55)))
            }
            .padding(.trailing, 18).padding(.bottom, 28)
            #endif
        }
        .sheet(isPresented: $showLogs) { LogsView() }
        .alert("Удалить подписку?",
               isPresented: Binding(
                   get: { subToDelete != nil },
                   set: { if !$0 { subToDelete = nil } }
               )) {
            Button("Отмена", role: .cancel) { subToDelete = nil }
            Button("Удалить", role: .destructive) {
                if let url = subToDelete { store.deleteSubscription(url: url) }
                subToDelete = nil
            }
        } message: {
            Text("Все серверы этой подписки будут удалены, VPN отключится.")
        }

        .onReceive(store.$configWasAdded) { added in
            if added {
                showAdd = false
                store.configWasAdded = false
                store.fetchSubscriptionInfo()
            }
        }
    }

    private var list: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    LogoView(size: 80)
                    if let info = store.subscriptionInfo {
                        SubscriptionCard(info: info, onRefresh: {
                            store.refreshSubscription()
                            store.fetchSubscriptionInfo()
                        })
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }
                    Button { showAdd = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Добавить конфиг")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Brand.cyan)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if !wgConfigs.isEmpty {
                Section {
                    ForEach(wgConfigs) { config in
                        ConfigRowView(config: config)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete { idx in idx.forEach { store.delete(wgConfigs[$0]) } }
                } header: { sectionHeader("WireGuard") }
            }

            if !vlessConfigs.isEmpty {
                Section {
                    ForEach(vlessConfigs) { config in
                        ConfigRowView(config: config)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete { idx in idx.forEach { store.delete(vlessConfigs[$0]) } }
                } header: { sectionHeader("VLESS") }
            }

            if !store.subscriptionURLs.isEmpty {
                Section {
                    ForEach(store.subscriptionURLs, id: \.self) { sub in
                        Button(role: .destructive) {
                            subToDelete = sub
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "trash")
                                Text("Удалить подписку")
                                Spacer()
                                Text(URL(string: sub)?.host ?? sub)
                                    .font(.caption).foregroundStyle(Brand.faint)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            .foregroundStyle(Brand.disconnect)
                            .padding(.vertical, 11)
                            .padding(.horizontal, 13)
                            .brandGlass(cornerRadius: 16, tint: Color.white.opacity(0.05))
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                } header: { sectionHeader("Подписки") }
            }

            if store.configs.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "shield.slash")
                                .font(.system(size: 40))
                                .foregroundStyle(Brand.faint)
                            Text("Нет конфигов")
                                .font(.headline)
                                .foregroundStyle(Brand.text)
                            Text("Нажмите «Добавить конфиг»")
                                .font(.caption)
                                .foregroundStyle(Brand.muted)
                        }
                        .padding(.vertical, 30)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            Section {
                SupportFooterView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Brand.muted)
            .textCase(nil)
    }
}

// ── Support Footer ────────────────────────────────────────

struct SupportFooterView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Если у вас возникли вопросы по работе, обратитесь в поддержку.")
                .font(.caption)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
            Button("tchkg.online") {
                if let url = URL(string: "https://tchkg.online") {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption)
            .foregroundStyle(Brand.cyan)
        }
    }
}

// ── Safari View ───────────────────────────────────────────

#if os(iOS)
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
#endif

// ── Config Row ────────────────────────────────────────────

struct ConfigRowView: View {
    @EnvironmentObject var store: ConfigStore
    let config: VPNConfig

    @State private var pingMs: Int? = nil
    @State private var pingFailed: Bool = false
    @State private var pingTask: Task<Void, Never>? = nil

    private var pingColor: Color {
        if pingFailed { return Brand.coral }
        guard let ms = pingMs else { return Brand.faint }
        if ms < 90  { return Brand.pingGood }
        if ms < 130 { return Brand.pingMid }
        return Brand.pingHigh
    }

    private var pingText: String {
        if pingFailed { return "timeout" }
        guard let ms = pingMs else { return "…" }
        return "\(ms) мс"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill((config.isActive ? Brand.cyan : Brand.faint).opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Brand.edge, lineWidth: 1)
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: config.isActive ? "shield.fill" : "shield")
                    .font(.system(size: 15))
                    .foregroundStyle(config.isActive ? Brand.cyan : Brand.faint)
            }

            NavigationLink(destination: ConfigDetailView(config: config).environmentObject(store)) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(config.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Brand.text)
                        if config.protocolType != .wireguard {
                            Text(pingText)
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(pingColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(pingColor.opacity(0.14)))
                        }
                    }
                    Text(config.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Brand.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { config.isActive },
                set: { _ in store.toggle(config) }
            ))
            .labelsHidden()
            .tint(Brand.cyan)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .brandGlass(
            cornerRadius: 18,
            tint:   config.isActive ? Brand.cyan.opacity(0.14) : Brand.glassFill,
            stroke: config.isActive ? Brand.cyan.opacity(0.5)  : Color.white.opacity(0.08)
        )
        .shadow(color: config.isActive ? Brand.blue.opacity(0.18) : .clear, radius: 18, y: 6)
        .onAppear { startPinging() }
        .onDisappear {
            pingTask?.cancel()
            pingTask = nil
        }
    }

    private func startPinging() {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled {
                await measurePing()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func measurePing() async {
        if config.protocolType == .wireguard { return }   // UDP — TCP-пинг невозможен
        let (host, port) = endpoint(for: config)
        let result = await PingService.tcpPing(host: host, port: port, timeout: 3.0)
        await MainActor.run {
            switch result {
            case .success(let ms):
                pingMs = ms
                pingFailed = false
                store.pingMs[config.id] = ms
            case .failure:
                pingMs = nil
                pingFailed = true
                store.pingMs[config.id] = nil
            }
        }
    }

    private func endpoint(for config: VPNConfig) -> (String, UInt16) {
        switch config {
        case .vless(let v):
            return (v.address, UInt16(v.port) ?? 443)
        case .wireguard:
            if config.isActive {
                return ("1.1.1.1", 80)
            } else {
                return ("1.1.1.1", 80)
            }
        }
    }
}

// ── Ping Service (TCP connect-time) ───────────────────────

enum PingService {
    enum PingError: Error { case timeout, failed }

    static func tcpPing(host: String, port: UInt16, timeout: TimeInterval) async -> Result<Int, PingError> {
        await withCheckedContinuation { (continuation: CheckedContinuation<Result<Int, PingError>, Never>) in
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                continuation.resume(returning: .failure(.failed))
                return
            }
            let params = NWParameters.tcp
            params.prohibitedInterfaceTypes = [.other]   // мимо utun — меряем прямую задержку до сервера
            let conn = NWConnection(host: nwHost, port: nwPort, using: params)
            let start = Date()
            let state = PingState(continuation: continuation, conn: conn)

            conn.stateUpdateHandler = { s in
                switch s {
                case .ready:
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    state.finish(.success(ms))
                case .failed, .cancelled:
                    state.finish(.failure(.failed))
                default:
                    break
                }
            }
            conn.start(queue: DispatchQueue.global(qos: .utility))

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                state.finish(.failure(.timeout))
            }
        }
    }
}

nonisolated private final class PingState: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let continuation: CheckedContinuation<Result<Int, PingService.PingError>, Never>
    private let conn: NWConnection

    init(continuation: CheckedContinuation<Result<Int, PingService.PingError>, Never>,
         conn: NWConnection) {
        self.continuation = continuation
        self.conn = conn
    }

    nonisolated func finish(_ r: Result<Int, PingService.PingError>) {
        lock.lock(); defer { lock.unlock() }
        if done { return }
        done = true
        conn.cancel()
        continuation.resume(returning: r)
    }
}

// ── Logo ──────────────────────────────────────────────────

struct LogoView: View {
    var size: CGFloat = 60
    var body: some View {
        Image("AppLogo")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}
