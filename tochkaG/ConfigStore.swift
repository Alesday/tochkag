// ConfigStore.swift
// TochkaG

import Foundation
import UIKit
import Combine
import NetworkExtension

/// Данные подписки из HTTP-заголовков панели (subscription-userinfo, profile-title).
struct SubscriptionInfo: Codable, Equatable {
    var title: String = ""
    var upload: Int64 = 0
    var download: Int64 = 0
    var total: Int64 = 0          // 0 = безлимит
    var expire: TimeInterval = 0  // unix, 0 = бессрочно
    var updatedAt: Date = Date()

    var used: Int64 { upload + download }
    var isUnlimited: Bool { total <= 0 }
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(used) / Double(total))
    }
    var expireDate: Date? { expire > 0 ? Date(timeIntervalSince1970: expire) : nil }
    var daysLeft: Int? {
        guard let d = expireDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: d).day
    }
    var isExpired: Bool {
        guard let d = expireDate else { return false }
        return d < Date()
    }
}

class ConfigStore: ObservableObject {
    @Published var configs: [VPNConfig] = []
    @Published var vpnStatus: NEVPNStatus = .disconnected
    @Published var debugText: String = ""
    @Published var configWasAdded: Bool = false
    @Published var pendingSubscriptionURL: String? = nil
    @Published var pendingVlessURL: String? = nil
    @Published var subscriptionURL: String? = nil
    @Published var pingMs: [UUID: Int?] = [:]
    @Published var subscriptionInfo: SubscriptionInfo? = nil    // nil = не доступен / timeout, отсутствует ключ = ещё не пинговался
    @Published var isRefreshingSubscription: Bool = false

    private let saveKey = "tochkag_configs"
    private let appGroup = "group.com.tochkag.vpn"
    private var vpnManager: NETunnelProviderManager?
    private var statusObserver: AnyCancellable?

    init() {
        if let d = UserDefaults.standard.data(forKey: "subscriptionInfo"),
           let i = try? JSONDecoder().decode(SubscriptionInfo.self, from: d) {
            self.subscriptionInfo = i
        }
        load()
        setupVPNManager()
        self.subscriptionURL = UserDefaults.standard.string(forKey: "subscriptionURL")
    }

    func save() {
        let defaults = UserDefaults(suiteName: appGroup) ?? UserDefaults.standard
        if let data = try? JSONEncoder().encode(configs) {
            defaults.set(data, forKey: saveKey)
        }
    }

    func load() {
        let defaults = UserDefaults(suiteName: appGroup) ?? UserDefaults.standard
        guard let data = defaults.data(forKey: saveKey),
              let saved = try? JSONDecoder().decode([VPNConfig].self, from: data)
        else { return }
        configs = saved.map { var c = $0; c.isActive = false; return c }
    }

    func add(_ config: VPNConfig) {
        configs.append(config)
        save()
        DispatchQueue.main.async { self.configWasAdded = true }
    }

    func delete(_ config: VPNConfig) {
        configs.removeAll { $0.id == config.id }
        save()
    }

    /// Добавляет все VLESS-конфиги из подписки скопом, помечая их URL подписки.
    func addSubscription(_ vless: [VlessConfig], url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespaces)

        // Приложение работает с одной подпиской: конфиги всех остальных удаляем,
        // иначе в списке копятся дубли, а карточка показывает не ту подписку.
        if !trimmed.isEmpty {
            let removed = configs.count
            configs.removeAll { c in
                guard case .vless(let v) = c, let u = v.subscriptionURL, !u.isEmpty else { return false }
                return u != trimmed
            }
            let diff = removed - configs.count
            if diff > 0 { appLog("SUB: удалено \(diff) конфигов старой подписки") }
        }

        for var cfg in vless {
            cfg.subscriptionURL = trimmed
            configs.append(.vless(cfg))
        }
        if !trimmed.isEmpty { saveSubscriptionURL(trimmed) }
        save()
        DispatchQueue.main.async {
            self.configWasAdded = true
            self.fetchSubscriptionInfo()
        }
    }

    /// Список уникальных URL подписок, присутствующих в конфигах.
    var subscriptionURLs: [String] {
        var seen: [String] = []
        for c in configs {
            if case .vless(let v) = c, let u = v.subscriptionURL, !u.isEmpty, !seen.contains(u) {
                seen.append(u)
            }
        }
        return seen
    }

    /// Удаляет все VLESS-конфиги, привязанные к данной подписке.
    func deleteSubscription(url: String) {
        configs.removeAll { c in
            if case .vless(let v) = c { return v.subscriptionURL == url }
            return false
        }
        if subscriptionURL == url { clearSubscriptionURL() }
        subscriptionInfo = nil
        UserDefaults.standard.removeObject(forKey: "subscriptionInfo")
        save()

        // Гасим туннель и убираем VPN-профиль из настроек телефона,
        // иначе запись висит в Настройках даже без конфигов.
        tearDownVlessTunnelIfUnused()
    }

    /// Останавливает VLESS-туннель и удаляет его профиль,
    /// если VLESS-конфигов больше не осталось.
    private func tearDownVlessTunnelIfUnused() {
        let stillHasVless = configs.contains { if case .vless = $0 { return true }; return false }
        guard !stillHasVless else { return }

        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            guard let self else { return }
            let vlessManagers = (managers ?? []).filter { m in
                guard let p = m.protocolConfiguration as? NETunnelProviderProtocol else { return false }
                return p.providerBundleIdentifier == "com.tochkag.app.tunnel"
            }
            guard !vlessManagers.isEmpty else { return }

            for m in vlessManagers where m.connection.status != .disconnected {
                m.connection.stopVPNTunnel()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.removeAll(managers: vlessManagers) {
                    DispatchQueue.main.async {
                        for i in self.configs.indices { self.configs[i].isActive = false }
                        self.vpnStatus = .disconnected
                        self.save()
                        self.appLog("SUB: профиль VLESS удалён из системы")
                    }
                }
            }
        }
    }

    func hasConfig(ofType type: VPNProtocol) -> Bool {
        configs.contains { $0.protocolType == type }
    }

    func toggle(_ config: VPNConfig) {
        print("TOGGLE CALLED", config.name)
        let isOn = config.isActive
        for i in configs.indices { configs[i].isActive = false }
        if !isOn {
            if let idx = configs.firstIndex(where: { $0.id == config.id }) {
                configs[idx].isActive = true
                connect(config: configs[idx])
            }
        } else {
            disconnect()
        }
        save()
    }

    private func setupVPNManager() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.vpnManager = managers?.first ?? NETunnelProviderManager()
                self.observeStatus()
                self.vpnStatus = self.vpnManager?.connection.status ?? .disconnected
                self.syncActiveStateWithSystem()
            }
        }
    }

    /// Сверяет isActive конфигов с реальным состоянием туннеля в системе.
    /// Нужен потому, что при загрузке из UserDefaults все конфиги сбрасываются в false,
    /// а туннель мог остаться поднятым (сворачивание, перезапуск приложения).
    func syncActiveStateWithSystem() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                let all = managers ?? []
                let statuses = all.map { "\($0.connection.status.rawValue)" }.joined(separator: ",")
                self.appLog("SYNC: managers=\(all.count) statuses=[\(statuses)]")
                let live = all.first {
                    $0.connection.status == .connected || $0.connection.status == .connecting
                }
                guard let live,
                      let proto = live.protocolConfiguration as? NETunnelProviderProtocol,
                      let pc = proto.providerConfiguration else {
                    // туннеля нет — гасим все тумблеры
                    if self.configs.contains(where: { $0.isActive }) {
                        self.appLog("SYNC: туннеля нет — гашу тумблеры")
                        for i in self.configs.indices { self.configs[i].isActive = false }
                        self.save()
                    }
                    self.vpnStatus = .disconnected
                    return
                }

                // ищем конфиг, который соответствует поднятому туннелю
                let isWG = proto.providerBundleIdentifier == "com.tochkag.app.tunnelwg"
                let addr = pc["address"] as? String
                let uuid = pc["uuid"] as? String
                let wgPub = pc["publicKey"] as? String
                let wgEnd = pc["endpoint"] as? String
                func isMine(_ c: VPNConfig) -> Bool {
                    switch c {
                    case .vless(let v):
                        return !isWG && addr != nil && v.address == addr && (uuid == nil || v.uuid == uuid)
                    case .wireguard(let w):
                        return isWG && ((wgPub != nil && w.publicKey == wgPub) ||
                                        (wgEnd != nil && w.endpoint == wgEnd))
                    }
                }
                var changed = false
                if self.configs.contains(where: isMine) {
                    for i in self.configs.indices {
                        let m = isMine(self.configs[i])
                        if self.configs[i].isActive != m { self.configs[i].isActive = m; changed = true }
                    }
                } else {
                    self.appLog("SYNC: туннель поднят, но конфиг не опознан — тумблеры не трогаю")
                }
                self.vpnStatus = live.connection.status
                if changed { self.save() }
            }
        }
    }

    private var activeObserver: AnyCancellable?

    private func observeAppActive() {
        activeObserver = NotificationCenter.default
            .publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.appLog("SYNC: приложение активно")
                self?.syncActiveStateWithSystem()
                self?.fetchSubscriptionInfo()
            }
    }

    private func observeStatus() {
        observeAppActive()
        statusObserver = NotificationCenter.default
            .publisher(for: .NEVPNStatusDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.vpnStatus = self?.vpnManager?.connection.status ?? .disconnected
            }
    }

    private func connect(config: VPNConfig) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            guard let self = self else { return }
            let all = managers ?? []
            #if DEBUG
            print("CONNECT: found \(all.count) existing manager(s)")
            #endif

            let targetBundle: String = {
                switch config {
                case .vless:     return "com.tochkag.app.tunnel"
                case .wireguard: return "com.tochkag.app.tunnelwg"
                }
            }()

            let existing = all.first { m in
                guard let p = m.protocolConfiguration as? NETunnelProviderProtocol else { return false }
                return p.providerBundleIdentifier == targetBundle
            }

            // ─── HOT-SWITCH: VLESS → VLESS на работающем туннеле ───
            if case .vless(let vl) = config,
               let m = existing,
               (m.connection.status == .connected || m.connection.status == .connecting),
               let session = m.connection as? NETunnelProviderSession {

                // Обновляем preferences (на случай перезапуска iOS)
                self.applyConfigToManager(manager: m, config: config)

                // Шлём сообщение для горячей замены Xray-конфига
                let payload: [String: Any] = [
                    "action": "switchServer",
                    "uuid": vl.uuid, "address": vl.address, "port": vl.port,
                    "path": vl.path, "network": vl.network, "security": vl.security,
                    "sni": vl.sni, "pbk": vl.publicKey, "sid": vl.shortId,
                    "flow": vl.flow, "fp": vl.fingerprint, "routing": vl.routing
                ]
                if let data = try? JSONSerialization.data(withJSONObject: payload) {
                    do {
                        try session.sendProviderMessage(data) { reply in
                            #if DEBUG
                            let r = reply.flatMap { String(data: $0, encoding: .utf8) } ?? "nil"
                            print("HOT-SWITCH reply: \(r)")
                            #endif
                        }
                        DispatchQueue.main.async { self.vpnStatus = .connected }
                        #if DEBUG
                        print("HOT-SWITCH: sent for \(vl.address):\(vl.port)")
                        #endif
                        return
                    } catch {
                        #if DEBUG
                        print("HOT-SWITCH failed: \(error) — fallback to full restart")
                        #endif
                    }
                }
            }

            // ─── Полный путь: останавливаем чужие туннели и запускаем ───
            let others = all.filter { $0 !== existing }
            var needWait = false
            for m in others {
                let st = m.connection.status
                if st != .disconnected && st != .invalid {
                    m.connection.stopVPNTunnel()
                    needWait = true
                }
            }

            let waitTime: TimeInterval = needWait ? 3.0 : 0.0
            self.waitForAllDisconnected(managers: others, maxWait: waitTime) {
                self.proceedConnect(config: config, existing: existing)
            }
        }
    }

    /// Записывает новые параметры в preferences без запуска (для hot-switch)
    private func applyConfigToManager(manager: NETunnelProviderManager, config: VPNConfig) {
        let proto = (manager.protocolConfiguration as? NETunnelProviderProtocol) ?? NETunnelProviderProtocol()
        switch config {
        case .vless:     proto.providerBundleIdentifier = "com.tochkag.app.tunnel"
        case .wireguard: proto.providerBundleIdentifier = "com.tochkag.app.tunnelwg"
        }
        switch config {
        case .wireguard(let wg):
            proto.serverAddress = wg.endpoint
            proto.providerConfiguration = [
                "type": "wireguard", "privateKey": wg.privateKey,
                "address": wg.address, "dns": wg.dns,
                "publicKey": wg.publicKey, "endpoint": wg.endpoint,
                "allowedIPs": wg.allowedIPs, "presharedKey": wg.presharedKey,
                "awg": wg.awgParams ?? [:],
            ]
        case .vless(let vl):
            proto.serverAddress = vl.address
            proto.providerConfiguration = [
                "type": "vless", "uuid": vl.uuid,
                "address": vl.address, "port": vl.port,
                "path": vl.path, "network": vl.network,
                "security": vl.security, "sni": vl.sni,
                "pbk": vl.publicKey, "sid": vl.shortId,
                "flow": vl.flow, "fp": vl.fingerprint,
                "routing": vl.routing,
            ]
        }
        manager.protocolConfiguration = proto
        manager.localizedDescription = "Tochka G"
        manager.isEnabled = true
        manager.saveToPreferences { _ in }
    }


    private func proceedConnect(config: VPNConfig, existing: NETunnelProviderManager?) {
        if let existing = existing {
            DispatchQueue.main.async {
                self.debugText = "reuse: " + (existing.localizedDescription ?? "?")
            }
            if self.isManagerUpToDate(existing, config: config) {
                // Параметры идентичны — но всё равно save() нужен чтобы iOS "освежил" manager
                // (после того как другой manager был активен, текущий становится stale)
                print("CONNECT: reuse existing manager, save + start")
                self.vpnManager = existing
                existing.isEnabled = true
                existing.saveToPreferences { [weak self] err in
                    guard let self = self else { return }
                    if let err = err {
                        print("CONNECT: save error: \(err.localizedDescription)")
                        return
                    }
                    existing.loadFromPreferences { _ in
                        do {
                            try existing.connection.startVPNTunnel()
                            DispatchQueue.main.async { self.vpnStatus = .connecting }
                            print("CONNECT: startVPNTunnel OK")
                        } catch {
                            print("CONNECT: startVPNTunnel error: \(error.localizedDescription)")
                        }
                    }
                }
            } else {
                // Параметры изменились — save на том же manager (без пароля)
                print("CONNECT: config changed, save existing manager")
                self.applyAndStart(manager: existing, config: config)
            }
        } else {
            DispatchQueue.main.async {
                self.debugText = "creating NEW manager"
            }
            // Нет manager'а для этого UUID → создаём новый (iOS запросит пароль ОДИН раз)
            print("CONNECT: no existing manager for this config, creating new")
            let freshManager = NETunnelProviderManager()
            self.applyAndStart(manager: freshManager, config: config)
        }
    }

    // Возвращает UUID конфига (для vless) или публичный ключ (для wireguard)
    private func configUUID(_ config: VPNConfig) -> String {
        switch config {
        case .vless(let vl):     return vl.uuid
        case .wireguard(let wg): return wg.publicKey
        }
    }

    // Сравнивает поля manager'а с config — true если совпадают все значимые поля
    private func isManagerUpToDate(_ manager: NETunnelProviderManager, config: VPNConfig) -> Bool {
        guard let proto = manager.protocolConfiguration as? NETunnelProviderProtocol,
              let cfg = proto.providerConfiguration else { return false }
        switch config {
        case .vless(let vl):
            return (cfg["type"] as? String) == "vless" &&
                   (cfg["uuid"] as? String) == vl.uuid &&
                   (cfg["address"] as? String) == vl.address &&
                   (cfg["port"] as? String) == vl.port &&
                   (cfg["sni"] as? String) == vl.sni &&
                   (cfg["pbk"] as? String) == vl.publicKey &&
                   (cfg["sid"] as? String) == vl.shortId &&
                   (cfg["flow"] as? String) == vl.flow &&
                   (cfg["fp"] as? String) == vl.fingerprint &&
                   (cfg["network"] as? String) == vl.network &&
                   (cfg["security"] as? String) == vl.security &&
                   (cfg["path"] as? String) == vl.path &&
                   proto.serverAddress == vl.address
        case .wireguard(let wg):
            return (cfg["type"] as? String) == "wireguard" &&
                   (cfg["privateKey"] as? String) == wg.privateKey &&
                   (cfg["publicKey"] as? String) == wg.publicKey &&
                   (cfg["endpoint"] as? String) == wg.endpoint &&
                   (cfg["address"] as? String) == wg.address &&
                   (cfg["dns"] as? String) == wg.dns &&
                   (cfg["allowedIPs"] as? String) == wg.allowedIPs &&
                   proto.serverAddress == wg.endpoint
        }
    }

    private func waitForAllDisconnected(managers: [NETunnelProviderManager],
                                        maxWait: TimeInterval,
                                        _ done: @escaping () -> Void) {
        let start = Date()
        func poll() {
            let allDown = managers.allSatisfy {
                $0.connection.status == .disconnected || $0.connection.status == .invalid
            }
            if allDown {
                done()
                return
            }
            if Date().timeIntervalSince(start) > maxWait {
                print("CONNECT: timeout waiting for all to disconnect")
                done()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
        }
        poll()
    }

    private func removeAll(managers: [NETunnelProviderManager],
                           _ done: @escaping () -> Void) {
        if managers.isEmpty { done(); return }
        var remaining = managers.count
        for m in managers {
            m.removeFromPreferences { err in
                if let err = err {
                    print("CONNECT: removeFromPreferences error: \(err.localizedDescription)")
                } else {
                    print("CONNECT: removed old manager \(m.localizedDescription ?? "nil")")
                }
                DispatchQueue.main.async {
                    remaining -= 1
                    if remaining == 0 {
                        // небольшая пауза чтобы NE успел зарегистрировать удаление
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done() }
                    }
                }
            }
        }
    }

    private func applyAndStart(manager: NETunnelProviderManager, config: VPNConfig) {
        let proto = NETunnelProviderProtocol()
        switch config {
        case .vless:     proto.providerBundleIdentifier = "com.tochkag.app.tunnel"
        case .wireguard: proto.providerBundleIdentifier = "com.tochkag.app.tunnelwg"
        }

        switch config {
        case .wireguard(let wg):
            proto.serverAddress = wg.endpoint
            proto.providerConfiguration = [
                "type": "wireguard", "privateKey": wg.privateKey,
                "address": wg.address, "dns": wg.dns,
                "publicKey": wg.publicKey, "endpoint": wg.endpoint,
                "allowedIPs": wg.allowedIPs,
                "presharedKey": wg.presharedKey,
            ]
        case .vless(let vl):
            proto.serverAddress = vl.address
            proto.providerConfiguration = [
                "type": "vless", "uuid": vl.uuid,
                "address": vl.address, "port": vl.port,
                "path": vl.path, "network": vl.network,
                "security": vl.security, "sni": vl.sni,
                "pbk": vl.publicKey, "sid": vl.shortId,
                "flow": vl.flow, "fp": vl.fingerprint,
                "routing": vl.routing,
            ]
        }

        manager.protocolConfiguration = proto
        manager.localizedDescription = "Tochka G"
        manager.isEnabled = true

        manager.saveToPreferences { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                print("VPN save error:", error.localizedDescription)
                return
            }
            manager.loadFromPreferences { error in
                if let error = error {
                    print("VPN load error:", error.localizedDescription)
                    return
                }
                self.vpnManager = manager
                DispatchQueue.main.async {
                    do {
                        #if DEBUG
                        print("STARTING TUNNEL")
                        #endif
                        try manager.connection.startVPNTunnel()
                        print("TUNNEL STARTED")
                    } catch {
                        print("TUNNEL ERROR:", error)
                    }
                }
            }
        }
    }

    private func disconnect() {
        vpnManager?.connection.stopVPNTunnel()
    }
    // MARK: - Subscription auto-refresh

    func saveSubscriptionURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        subscriptionURL = trimmed
        UserDefaults.standard.set(trimmed, forKey: "subscriptionURL")
    }

    func clearSubscriptionURL() {
        subscriptionURL = nil
        UserDefaults.standard.removeObject(forKey: "subscriptionURL")
    }

    /// Тихо обновляет подписку в фоне — добавляет новые серверы, обновляет существующие по UUID.
    /// Существующие конфиги, которых уже нет на сервере, НЕ удаляются (на случай временных проблем).
    func refreshSubscription() {
        guard let urlStr = subscriptionURL,
              let url = URL(string: urlStr) else { return }
        if isRefreshingSubscription { return }
        isRefreshingSubscription = true

        var req = URLRequest(url: url)
        req.timeoutInterval = 15

        let device     = UIDevice.current
        let hwid       = device.identifierForVendor?.uuidString.lowercased() ?? "unknown"
        let osVersion  = device.systemVersion
        let model      = device.model
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let locale     = Locale.current.language.languageCode?.identifier ?? "en"
        let userAgent  = "TochkaG/\(appVersion) (iOS \(osVersion); \(model))"

        req.setValue(hwid,       forHTTPHeaderField: "x-hwid")
        req.setValue("iOS",      forHTTPHeaderField: "x-device-os")
        req.setValue(osVersion,  forHTTPHeaderField: "x-ver-os")
        req.setValue(model,      forHTTPHeaderField: "x-device-model")
        req.setValue(locale,     forHTTPHeaderField: "x-device-locale")
        req.setValue(userAgent,  forHTTPHeaderField: "User-Agent")

        #if DEBUG
        print("[AUTO-REFRESH] hwid=\(hwid)")
        #endif

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRefreshingSubscription = false

                guard let data = data,
                      let raw  = String(data: data, encoding: .utf8) else { return }

                let decoded = self.decodeBase64IfNeeded(raw)
                let lines = decoded
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("vless://") }
                    .filter { !$0.contains("0.0.0.0:1") &&
                              !$0.contains("00000000-0000-0000-0000-000000000000") }

                if lines.isEmpty {
                    print("[AUTO-REFRESH] no real configs returned, skipping merge")
                    return
                }

                let parsed = lines.compactMap { self.parseVlessLine($0) }
                guard !parsed.isEmpty else { return }

                self.syncVlessConfigs(parsed)
                print("[AUTO-REFRESH] merged \(parsed.count) configs")
            }
        }.resume()
    }

    /// Парсит одну vless:// строку в VlessConfig
    private func parseVlessLine(_ raw: String) -> VlessConfig? {
        guard let u = URL(string: raw), u.scheme == "vless" else { return nil }
        var p: [String: String] = [:]
        p["uuid"]    = u.user ?? ""
        p["address"] = u.host ?? ""
        p["port"]    = String(u.port ?? 443)
        URLComponents(url: u, resolvingAgainstBaseURL: false)?
            .queryItems?.forEach { if let v = $0.value { p[$0.name] = v } }
        if let frag = u.fragment, !frag.isEmpty {
            p["name"] = frag.removingPercentEncoding ?? frag
        }
        return VlessConfig(
            name:     p["name"] ?? p["sni"] ?? p["address"] ?? "VLESS",
            uuid:     p["uuid"] ?? "",
            address:  p["address"] ?? "",
            port:     p["port"] ?? "443",
            path:     p["path"] ?? "/",
            network:  p["type"] ?? "tcp",
            security: p["security"] ?? "tls",
            sni:      p["sni"] ?? p["address"] ?? "",
            publicKey:   p["pbk"] ?? "",
            shortId:     p["sid"] ?? "",
            flow:        p["flow"] ?? "",
            fingerprint: p["fp"] ?? "chrome"
        )
    }

    /// Мерджит новые VLESS-конфиги в существующий список по UUID+address+port.
    /// Новые добавляются, существующие обновляют параметры (но сохраняют id и isActive).
    /// Полная синхронизация подписки: добавляет новые, обновляет существующие,
    /// удаляет пропавшие из ответа панели.
    /// Трогает ТОЛЬКО конфиги текущей подписки — ручные VLESS и WireGuard не затрагиваются.
    /// Активную (подключённую) ноду не удаляем, чтобы не рвать VPN.
    /// Читает subscription-userinfo и profile-title из ответа панели.
    /// Отдельный лёгкий запрос только за метаданными подписки (HEAD-подобный).
    /// Не зависит от refreshSubscription — свой URLSession, свой разбор.
    func fetchSubscriptionInfo() {
        let effective = subscriptionURL ?? subscriptionURLs.first
        guard let urlStr = effective, !urlStr.isEmpty, let url = URL(string: urlStr) else {
            appLog("нет URL подписки")
            return
        }
        let device     = UIDevice.current
        let hwid       = device.identifierForVendor?.uuidString.lowercased() ?? "unknown"
        let osVersion  = device.systemVersion
        let model      = device.model
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let locale     = Locale.current.language.languageCode?.identifier ?? "en"
        let userAgent  = "TochkaG/\(appVersion) (iOS \(osVersion); \(model))"

        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue(hwid,       forHTTPHeaderField: "x-hwid")
        req.setValue("iOS",      forHTTPHeaderField: "x-device-os")
        req.setValue(osVersion,  forHTTPHeaderField: "x-ver-os")
        req.setValue(model,      forHTTPHeaderField: "x-device-model")
        req.setValue(locale,     forHTTPHeaderField: "x-device-locale")
        req.setValue(userAgent,  forHTTPHeaderField: "User-Agent")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.setValue("no-cache", forHTTPHeaderField: "Pragma")

        URLSession.shared.dataTask(with: req) { [weak self] _, resp, err in
            guard let self else { return }
            if let err {
                self.appLog("info error: \(err.localizedDescription)")
                return
            }
            guard let http = resp as? HTTPURLResponse else {
                self.appLog("info: ответ не HTTP")
                return
            }
            let ui = http.value(forHTTPHeaderField: "subscription-userinfo") ?? "<нет>"
            self.appLog("HTTP \(http.statusCode) userinfo: \(ui)")
            self.parseSubscriptionHeaders(http)
        }.resume()
    }

    /// Пишет в App Group — видно на экране «Логи».
    func appLog(_ msg: String) {
        guard let ud = UserDefaults(suiteName: "group.com.tochkag.vpn") else { return }
        var l = ud.stringArray(forKey: "tunnel_logs") ?? []
        l.append("\(Date()) [APP] \(msg)")
        ud.set(Array(l.suffix(120)), forKey: "tunnel_logs")
    }

    private func parseSubscriptionHeaders(_ http: HTTPURLResponse) {
        var info = SubscriptionInfo()
        // диагностика в App Group (видно на экране Логи)
        let dbg = "HDRS: " + http.allHeaderFields.map { "\($0.key)" }.joined(separator: ",")
        if let ud = UserDefaults(suiteName: "group.com.tochkag.vpn") {
            var logs = ud.stringArray(forKey: "tunnel_logs") ?? []
            logs.append("\(Date()) [APP] \(dbg)")
            ud.set(Array(logs.suffix(100)), forKey: "tunnel_logs")
        }

        if let raw = http.value(forHTTPHeaderField: "profile-title") {
            info.title = decodePanelBase64(raw)
        }

        if let ui = http.value(forHTTPHeaderField: "subscription-userinfo") {
            // формат: upload=0; download=0; total=0; expire=1849046399
            for part in ui.components(separatedBy: ";") {
                let kv = part.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                guard kv.count == 2 else { continue }
                let v = Int64(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
                switch kv[0].trimmingCharacters(in: .whitespaces).lowercased() {
                case "upload":   info.upload = v
                case "download": info.download = v
                case "total":    info.total = v
                case "expire":   info.expire = TimeInterval(v)
                default: break
                }
            }
        }

        info.updatedAt = Date()
        DispatchQueue.main.async {
            self.subscriptionInfo = info
            if let d = try? JSONEncoder().encode(info) {
                UserDefaults.standard.set(d, forKey: "subscriptionInfo")
            }
            print("[SUB-INFO] \(info.title) used=\(info.used) total=\(info.total) expire=\(info.expire)")
        }
    }

    /// Панель отдаёт часть заголовков как "base64:...."
    private func decodePanelBase64(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("base64:") else { return t }
        let body = String(t.dropFirst("base64:".count))
        let padded = body + String(repeating: "=", count: (4 - body.count % 4) % 4)
        if let d = Data(base64Encoded: padded), let s = String(data: d, encoding: .utf8) {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    private func syncVlessConfigs(_ incoming: [VlessConfig]) {
        guard !incoming.isEmpty else { return }
        guard let subURL = self.subscriptionURL, !subURL.isEmpty else {
            self.mergeVlessConfigs(incoming)
            return
        }

        self.mergeVlessConfigs(incoming)

        let freshKeys = Set(incoming.map { "\($0.uuid)|\($0.address)|\($0.port)" })
        var removed = 0
        var keptActive = 0

        self.configs.removeAll { c in
            guard case .vless(let v) = c else { return false }
            guard v.subscriptionURL == subURL else { return false }
            let key = "\(v.uuid)|\(v.address)|\(v.port)"
            if freshKeys.contains(key) { return false }
            if v.isActive {
                keptActive += 1
                return false
            }
            self.pingMs.removeValue(forKey: v.id)
            removed += 1
            return true
        }

        if removed > 0 || keptActive > 0 {
            print("[SYNC] removed \(removed), kept active \(keptActive)")
            self.save()
        }
    }

    private func mergeVlessConfigs(_ incoming: [VlessConfig]) {
        for fresh in incoming {
            let key = "\(fresh.uuid)|\(fresh.address)|\(fresh.port)"
            if let idx = self.configs.firstIndex(where: { c in
                if case .vless(let existing) = c {
                    return "\(existing.uuid)|\(existing.address)|\(existing.port)" == key
                }
                return false
            }) {
                if case .vless(let existing) = self.configs[idx] {
                    var updated = fresh
                    updated.id = existing.id        // сохраняем стабильный id
                    updated.isActive = existing.isActive
                    // ВАЖНО: fresh приходит без subscriptionURL — не теряем привязку
                    updated.subscriptionURL = existing.subscriptionURL ?? self.subscriptionURL
                    self.configs[idx] = .vless(updated)
                }
            } else {
                var tagged = fresh
                tagged.subscriptionURL = self.subscriptionURL
                self.configs.append(.vless(tagged))
            }
        }
        self.save()
    }

    /// Декодер base64 (включая URL-safe)
    private func decodeBase64IfNeeded(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("vless://") { return trimmed }
        let cleaned = trimmed.filter { !$0.isWhitespace }
        let padded = cleaned + String(repeating: "=", count: (4 - cleaned.count % 4) % 4)
        if let data = Data(base64Encoded: padded),
           let decoded = String(data: data, encoding: .utf8),
           decoded.contains("://") {
            return decoded
        }
        let urlSafe = cleaned
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let urlSafePadded = urlSafe + String(repeating: "=", count: (4 - urlSafe.count % 4) % 4)
        if let data = Data(base64Encoded: urlSafePadded),
           let decoded = String(data: data, encoding: .utf8),
           decoded.contains("://") {
            return decoded
        }
        return trimmed
    }

}
