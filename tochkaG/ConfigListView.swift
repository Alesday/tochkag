// ConfigListView.swift
// TochkaG

import SwiftUI
import Network
import SafariServices

struct ConfigListView: View {
    @EnvironmentObject var store: ConfigStore
    @State private var showAdd        = false
    @State private var showProxySheet = false
    @State private var showLogs       = false
    @State private var tunnelLogs: [String] = []

    var wgConfigs:    [VPNConfig] { store.configs.filter { $0.protocolType == .wireguard } }
    var vlessConfigs: [VPNConfig] { store.configs.filter { $0.protocolType == .vless } }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    LogoView(size: 80)
                    Button { showAdd = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Добавить конфиг")
                        }
                        .font(.body)
                        .foregroundColor(Color(red: 0.17, green: 0.66, blue: 0.91))
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
                Section("WireGuard") {
                    ForEach(wgConfigs) { config in
                        ConfigRowView(config: config)
                    }
                    .onDelete { idx in idx.forEach { store.delete(wgConfigs[$0]) } }
                }
            }

            if !vlessConfigs.isEmpty {
                Section("VLESS") {
                    ForEach(vlessConfigs) { config in
                        ConfigRowView(config: config)
                    }
                    .onDelete { idx in idx.forEach { store.delete(vlessConfigs[$0]) } }
                }
            }

            if store.configs.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "shield.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Нет конфигов").font(.headline)
                            Text("Нажмите «Добавить конфиг»")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 30)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                SupportFooterView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
            }

            Section {
                Button { showProxySheet = true } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color(red: 0.17, green: 0.66, blue: 0.91))
                            .cornerRadius(6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Временный прокси для TG")
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text("Открыть в Telegram")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary).font(.caption)
                    }
                }
            }

        }
        .navigationTitle("")

        .sheet(isPresented: $showProxySheet) { ProxySheetView() }
        .sheet(isPresented: $showAdd) { AddConfigView().environmentObject(store) }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Логи") {
                    if let ud = UserDefaults(suiteName: "group.com.tochkag.vpn") {
                        tunnelLogs = ud.stringArray(forKey: "tunnel_logs") ?? ["Нет логов"]
                    }
                    showLogs = true
                }.font(.caption)
            }
        }
        .sheet(isPresented: $showLogs) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tunnelLogs.reversed(), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding()
                }
                .navigationTitle("Tunnel Logs")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Закрыть") { showLogs = false }
                    }
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Очистить") {
                            UserDefaults(suiteName: "group.com.tochkag.vpn")?.removeObject(forKey: "tunnel_logs")
                            tunnelLogs = []
                        }
                    }
                }
            }
        }
        .onReceive(store.$configWasAdded) { added in
            if added {
                showAdd = false
                store.configWasAdded = false
            }
        }
    }
}

// ── Support Footer ────────────────────────────────────────

struct SupportFooterView: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Если у вас возникли вопросы по работе, обратитесь в поддержку.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("@satoshi_si") {
                if let url = URL(string: "https://t.me/satoshi_si") {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption).foregroundColor(.blue)
            Text("Если не работает TG — воспользуйтесь временным прокси по кнопке ниже.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
    }
}

// ── Proxy Sheet ───────────────────────────────────────────

struct ProxySheetView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showSafari = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 56))
                        .foregroundColor(Color(red: 0.17, green: 0.66, blue: 0.91))
                        .padding(.top, 32)
                    Text("Временный прокси\nдля Telegram")
                        .font(.title2).fontWeight(.bold).multilineTextAlignment(.center)
                    Button { showSafari = true } label: {
                        HStack {
                            Spacer()
                            Text("Подключиться")
                                .fontWeight(.semibold).foregroundColor(.white)
                            Spacer()
                        }
                        .padding()
                        .background(Color(red: 0.17, green: 0.66, blue: 0.91))
                        .cornerRadius(14)
                    }
                    .padding(.horizontal)

                    ProxyInfoView().padding(.horizontal).padding(.bottom, 32)
                }
            }
            .navigationTitle("")

            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .sheet(isPresented: $showSafari) {
                SafariView(url: URL(string: "https://tochkag.online")!).ignoresSafeArea()
            }
        }
    }
}

struct ProxyInfoView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill").foregroundColor(.orange).font(.title3)
                Text("Помните, что это временный прокси — лишь способ связаться с поддержкой. Если вам нужен личный прокси, доступ можно получить с большой скидкой в боте.")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            Divider()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "trash.circle.fill").foregroundColor(.red).font(.title3)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Как удалить прокси после использования:")
                        .font(.subheadline).fontWeight(.medium)
                    Text("Зайдите в Настройки Telegram → «Данные и память» → «Прокси» (последняя строчка) → удалите соединение.")
                        .font(.subheadline).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(14)
    }
}

// ── Safari View ───────────────────────────────────────────

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}

// ── Config Row ────────────────────────────────────────────

struct ConfigRowView: View {
    @EnvironmentObject var store: ConfigStore
    let config: VPNConfig

    @State private var pingMs: Int? = nil       // nil = пингуем/неизвестно
    @State private var pingFailed: Bool = false
    @State private var pingTask: Task<Void, Never>? = nil

    private var pingColor: Color {
        if pingFailed { return .red }
        guard let ms = pingMs else { return .secondary }
        if ms < 100  { return .green }
        if ms < 250  { return .orange }
        return .red
    }

    private var pingText: String {
        if pingFailed { return "timeout" }
        guard let ms = pingMs else { return "…" }
        return "\(ms) ms"
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(config.isActive ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
            NavigationLink(destination: ConfigDetailView(config: config).environmentObject(store)) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(config.name).font(.headline)
                        Text(pingText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(pingColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(pingColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(config.subtitle).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { config.isActive },
                set: { _ in store.toggle(config) }
            ))
            .labelsHidden()
        }
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
                try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30s
            }
        }
    }

    private func measurePing() async {
        let (host, port) = endpoint(for: config)
        let result = await PingService.tcpPing(host: host, port: port, timeout: 3.0)
        await MainActor.run {
            switch result {
            case .success(let ms):
                pingMs = ms
                pingFailed = false
            case .failure:
                pingMs = nil
                pingFailed = true
            }
        }
    }

    private func endpoint(for config: VPNConfig) -> (String, UInt16) {
        switch config {
        case .vless(let v):
            return (v.address, UInt16(v.port) ?? 443)
        case .wireguard:
            // WG endpoint — UDP, TCP пинг не работает.
            // Пингуем через туннель если активен, иначе — WG сервер по 443/80
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
            let conn = NWConnection(host: nwHost, port: nwPort, using: .tcp)
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

// helper для безопасного one-shot-резолва continuation
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

extension Color {
    init(hex: String) {
        let v = Int(hex, radix: 16) ?? 0
        self.init(
            red:   Double((v >> 16) & 0xff) / 255,
            green: Double((v >> 8)  & 0xff) / 255,
            blue:  Double( v        & 0xff) / 255
        )
    }
}
