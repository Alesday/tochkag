import SwiftUI
import NetworkExtension
import AppKit

struct ContentView: View {
    @StateObject private var store = MacConfigStore()

    private let sidebarWidth: CGFloat = 320

    var body: some View {
        ZStack {
            AuroraBackground()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: sidebarWidth)
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 1)
                detail
            }
        }
        .task { store.bootstrapSubscription() }
        .sheet(item: $store.addMode) { mode in
            AddConfigMacView(store: store, mode: mode)
        }
        .frame(minWidth: 800, idealWidth: 900, minHeight: 600, idealHeight: 700)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        ZStack {
            if store.configs.isEmpty {
                emptySidebar
            } else {
                configScroll
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            AddConfigSidebarButton(store: store)
        }
    }

    private var emptySidebar: some View {
        VStack(spacing: 14) {
            Image(systemName: "plus.circle")
                .font(.system(size: 44))
                .foregroundStyle(Brand.faint)
            Text("Нет конфигураций")
                .font(.system(size: 14))
                .foregroundStyle(Brand.muted)
            Text("Добавьте сервер по ссылке,\nподписке или файлу .conf")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(Brand.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// VLESS-конфиги, пришедшие из подписки.
    private var subscriptionConfigs: [VPNConfig] {
        store.configs.filter {
            if case .vless(let v) = $0, let u = v.subscriptionURL, !u.isEmpty { return true }
            return false
        }
    }

    /// Всё, что добавлено вручную — WireGuard и отдельные VLESS.
    private var ownConfigs: [VPNConfig] {
        store.configs.filter {
            if case .vless(let v) = $0, let u = v.subscriptionURL, !u.isEmpty { return false }
            return true
        }
    }

    private func sectionHeader(_ title: String, _ count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
            Text("\(count)")
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            Spacer()
        }
        .foregroundStyle(Brand.faint)
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func configRow(_ config: VPNConfig) -> some View {
        ConfigRowView(config: config, store: store)
            .contentShape(Rectangle())
            .onTapGesture { store.selectedID = config.id }
            .contextMenu {
                Button(config.isActive ? "Отключить" : "Подключить") {
                    store.toggle(config)
                }
                Divider()
                Button("Удалить", role: .destructive) { store.delete(config) }
            }
    }

    private var configScroll: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if !subscriptionConfigs.isEmpty {
                    sectionHeader("Подписка", subscriptionConfigs.count)
                    ForEach(subscriptionConfigs) { configRow($0) }
                }
                if !ownConfigs.isEmpty {
                    sectionHeader("Мои конфиги", ownConfigs.count)
                    ForEach(ownConfigs) { configRow($0) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 34)
            .padding(.bottom, 8)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        ZStack {
            if let id = store.selectedID,
               let config = store.configs.first(where: { $0.id == id }) {
                ConfigDetailMacView(config: config, store: store)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "shield")
                        .font(.system(size: 46))
                        .foregroundStyle(Brand.faint)
                    Text("Выберите конфигурацию")
                        .font(.system(size: 14))
                        .foregroundStyle(Brand.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Значок состояния

/// Щит конфига. В подключённом состоянии — градиентная заливка со свечением
/// и медленно вращающийся ободок из конического градиента.
struct ShieldBadge: View {
    let isConnected: Bool
    let isBusy: Bool
    let tint: Color

    @State private var spin = false

    private let size: CGFloat = 34
    private let corner: CGFloat = 11

    var body: some View {
        ZStack {
            // подложка
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    isConnected
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Brand.cyan.opacity(0.38), Brand.blue.opacity(0.30)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color.white.opacity(0.08))
                )

            // статичная рамка — только когда не подключено
            if !isConnected {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Brand.edge, lineWidth: 1)
            }

            // вращающийся ободок
            if isConnected {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        AngularGradient(
                            colors: [Brand.cyan.opacity(0.0), Brand.cyan,
                                     Brand.blue, Brand.cyan.opacity(0.0)],
                            center: .center
                        ),
                        lineWidth: 1.6
                    )
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 3.2).repeatForever(autoreverses: false),
                               value: spin)
            }

            Image(systemName: isConnected ? "shield.fill" : "shield")
                .font(.system(size: 15, weight: isConnected ? .semibold : .regular))
                .foregroundStyle(
                    isConnected
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Color.white, Brand.cyan],
                        startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(tint)
                )
        }
        .frame(width: size, height: size)
        .shadow(color: isConnected ? Brand.cyan.opacity(0.45) : .clear, radius: 9)
        .shadow(color: isConnected ? Brand.blue.opacity(0.25) : .clear, radius: 18)
        .animation(.easeInOut(duration: 0.28), value: isConnected)
        .onAppear { if isConnected { spin = true } }
        .onChange(of: isConnected) { _, now in spin = now }
    }
}

// MARK: - Строка списка

struct ConfigRowView: View {
    let config: VPNConfig
    @ObservedObject var store: MacConfigStore

    private var isSelected: Bool { store.selectedID == config.id }

    private var isConnected: Bool {
        config.isActive && store.vpnStatus == .connected
    }

    private var isBusy: Bool {
        config.isActive && (store.vpnStatus == .connecting || store.vpnStatus == .disconnecting)
    }

    private var badgeColor: Color {
        if isConnected { return Brand.cyan }
        if isBusy      { return Brand.amber }
        return Brand.faint
    }

    var body: some View {
        HStack(spacing: 12) {
            ShieldBadge(isConnected: isConnected, isBusy: isBusy, tint: badgeColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text(config.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text(config.protocolType.rawValue.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.4)
                .foregroundStyle(Brand.faint)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                )
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .brandGlass(
            cornerRadius: 16,
            tint: isSelected ? Brand.cyan.opacity(0.14) : Brand.glassFill,
            stroke: isSelected ? Brand.cyan.opacity(0.5) : Color.white.opacity(0.08)
        )
        .shadow(color: isSelected ? Brand.blue.opacity(0.20) : .clear, radius: 18, y: 6)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
    }
}

// MARK: - Detail-вью конфигурации

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
        ScrollView {
            VStack(spacing: 18) {
                icon

                VStack(spacing: 5) {
                    Text(config.name)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Brand.text)
                    Text(statusLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(isConnected ? Brand.cyan : Brand.muted)
                }

                pingLabel

                actionButton
                    .frame(maxWidth: 260)
                    .padding(.top, 2)

                infoCard
                    .frame(maxWidth: 460)
                    .padding(.top, 6)

                LockNote()
                    .padding(.top, 2)

                Button {
                    store.delete(config)
                } label: {
                    Text("Удалить конфигурацию")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Brand.disconnect)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .brandGlass(cornerRadius: 11, tint: Color.white.opacity(0.05))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.bottom, 30)
            }
            .padding(.top, 38)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .onAppear { startPing() }
        .onChange(of: config.id) { _, _ in startPing() }
        .onDisappear { ping.stop() }
    }

    private var icon: some View {
        ZStack {
            if isConnected {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Brand.cyan.opacity(0.30), .clear],
                            center: .center, startRadius: 0, endRadius: 96
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 12)
            }
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .saturation(isConnected ? 1.0 : 0.0)
                .opacity(isConnected ? 1.0 : 0.55)
                .animation(.easeInOut(duration: 0.25), value: isConnected)
                .symbolEffect(.pulse, isActive: isLoading)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if isLoading {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("Подождите…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Brand.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .brandGlass(cornerRadius: 12, tint: Color.white.opacity(0.05))
        } else if isConnected {
            BrandDisconnectButton { store.toggle(config) }
        } else {
            BrandPrimaryButton(title: "Подключить", systemIcon: "bolt.fill") {
                store.toggle(config)
            }
        }
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
        HStack(spacing: 7) {
            Image(systemName: "wave.3.right")
                .font(.system(size: 11))
                .foregroundStyle(Brand.faint)
            if ping.isMeasuring && ping.latencyMs == nil {
                Text("измерение…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.faint)
            } else if let ms = ping.latencyMs {
                PingPill(ms: ms)
            } else {
                Text("нет ответа")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Brand.faint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.white.opacity(0.05))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        )
    }

    /// Карточка подписки для конфигов из подписки; для ручных — параметры сервера.
    @ViewBuilder
    private var infoCard: some View {
        if let info = subscriptionForThisConfig {
            VStack(spacing: 10) {
                SubscriptionCard(
                    info: info,
                    isRefreshing: store.isRefreshingSubscription
                ) {
                    store.refreshSubscription()
                    store.fetchSubscriptionInfo()
                }
                serverDetailsDisclosure
            }
        } else {
            GroupBox { configDetails }
                .groupBoxStyle(.brandPlain)
        }
    }

    /// Подписка показывается только для VLESS-конфигов, привязанных к ней.
    private var subscriptionForThisConfig: SubscriptionInfo? {
        guard case .vless(let v) = config,
              let u = v.subscriptionURL, !u.isEmpty else { return nil }
        return store.subscriptionInfo
    }

    private var serverDetailsDisclosure: some View {
        DisclosureGroup {
            configDetails
                .padding(.top, 10)
        } label: {
            Text("Параметры сервера")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Brand.muted)
        }
        .tint(Brand.faint)
        .padding(14)
        .brandGlass(cornerRadius: 16)
    }

    /// Только безопасное: без ключей, UUID и списка маршрутов.
    @ViewBuilder
    var configDetails: some View {
        switch config {
        case .vless(let vl):
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Сервер",   value: "\(vl.address):\(vl.port)")
                DetailRow(label: "Протокол", value: "VLESS")
            }
        case .wireguard(let wg):
            VStack(alignment: .leading, spacing: 8) {
                DetailRow(label: "Сервер",   value: wg.endpoint)
                DetailRow(label: "Протокол",
                          value: wg.awgParams?["Jc"] != nil ? "AmneziaWG" : "WireGuard")
            }
        }
    }
}

// MARK: - Строка параметра

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Brand.faint)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(hex: "8FC6F0"))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Стиль GroupBox

struct BrandPlainGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .brandGlass(cornerRadius: 16)
    }
}

extension GroupBoxStyle where Self == BrandPlainGroupBoxStyle {
    static var brandPlain: BrandPlainGroupBoxStyle { BrandPlainGroupBoxStyle() }
}

// MARK: - Кнопка добавления внизу сайдбара

struct AddConfigSidebarButton: View {
    @ObservedObject var store: MacConfigStore
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            Menu {
                Button("Добавить подписку")   { store.addMode = .subscription }
                Button("Добавить файл .conf") { store.addMode = .importFile }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Brand.cyan)
                    Text("Добавить")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Brand.text)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isHovered ? Color.white.opacity(0.09) : Color.clear)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .onHover { isHovered = $0 }
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Карточка подписки

struct SubscriptionCard: View {
    let info: SubscriptionInfo
    var isRefreshing: Bool = false
    var onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            trafficRow
            expiryRow
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .brandGlass(cornerRadius: 18)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Brand.grad)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1).blendMode(.overlay))
                Text(String(info.title.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(info.title.isEmpty ? "Подписка" : info.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Brand.text)
                Text("Подписка")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.faint)
            }
            Spacer(minLength: 8)
            statusBadge
        }
    }

    private var statusBadge: some View {
        let expired = info.isExpired
        return Text(expired ? "Истекла" : "Активна")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(expired ? Brand.disconnect : Brand.cyan)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill((expired ? Brand.disconnect : Brand.cyan).opacity(0.14))
                    .overlay(
                        Capsule().strokeBorder(
                            (expired ? Brand.disconnect : Brand.cyan).opacity(0.45),
                            lineWidth: 1
                        )
                    )
            )
    }

    @ViewBuilder
    private var trafficRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label {
                    Text("Трафик").font(.system(size: 12)).foregroundStyle(Brand.faint)
                } icon: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.faint)
                }
                Spacer()
                if info.isUnlimited {
                    Text("Безлимит")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Brand.cyan)
                } else {
                    Text("\(fmtBytes(info.used)) из \(fmtBytes(info.total))")
                        .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(Brand.text)
                }
            }

            if info.isUnlimited {
                Text("Использовано \(fmtBytes(info.used))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Brand.faint)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(info.progress > 0.9 ? Brand.gradWarm : Brand.grad)
                            .frame(width: max(4, geo.size.width * info.progress))
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private var expiryRow: some View {
        HStack {
            Label {
                Text("Действует до").font(.system(size: 12)).foregroundStyle(Brand.faint)
            } icon: {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.faint)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(expireText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Brand.text)
                if let d = info.daysLeft, d >= 0 {
                    Text("осталось \(d) \(plural(d, "день", "дня", "дней"))")
                        .font(.system(size: 11))
                        .foregroundStyle(d <= 7 ? Brand.pingMid : Brand.faint)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onRefresh) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isRefreshing ? "Обновление…" : "Обновить")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(isRefreshing ? Brand.faint : Brand.cyan)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)

            Spacer()

            Text("обновлено \(updatedText)")
                .font(.system(size: 10.5))
                .foregroundStyle(Brand.faint)
        }
    }

    private func fmtBytes(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowedUnits = [.useGB, .useMB, .useKB]
        f.zeroPadsFractionDigits = false
        return f.string(fromByteCount: max(0, b))
    }

    private var expireText: String {
        guard let d = info.expireDate else { return "Бессрочно" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: d)
    }

    private var updatedText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        if Calendar.current.isDateInToday(info.updatedAt) {
            f.dateFormat = "HH:mm"
        } else {
            f.dateFormat = "d MMM, HH:mm"
        }
        return f.string(from: info.updatedAt)
    }

    private func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }
}
