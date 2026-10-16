//
//  MacSubscription.swift
//  tochaGmac
//
//  Подписочный слой: перенос из iOS-ConfigStore.
//  Логика парсинга/синхронизации — verbatim, адаптированы только
//  HWID (IOKit вместо UIDevice) и заголовки устройства (macOS).
//

import Foundation
import AppKit
import NetworkExtension
import IOKit

// MARK: - Данные подписки из HTTP-заголовков панели

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

// MARK: - Подписки

extension MacConfigStore {

    // ── Хранение URL подписки ─────────────────────────────

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

    // ── Добавление / удаление подписки ────────────────────

    /// Добавляет все VLESS-конфиги из подписки скопом, помечая их URL подписки.
    func addSubscription(_ vless: [VlessConfig], url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespaces)

        // Приложение работает с одной подпиской: конфиги всех остальных удаляем,
        // иначе в списке копятся дубли, а карточка показывает не ту подписку.
        if !trimmed.isEmpty {
            let before = configs.count
            configs.removeAll { c in
                guard case .vless(let v) = c, let u = v.subscriptionURL, !u.isEmpty else { return false }
                return u != trimmed
            }
            let diff = before - configs.count
            if diff > 0 { appLog("SUB: удалено \(diff) конфигов старой подписки") }
        }

        var firstAdded: UUID? = nil
        for var cfg in vless {
            cfg.subscriptionURL = trimmed
            if firstAdded == nil { firstAdded = cfg.id }
            configs.append(.vless(cfg))
        }
        if !trimmed.isEmpty { saveSubscriptionURL(trimmed) }
        save()
        DispatchQueue.main.async {
            if self.selectedID == nil { self.selectedID = firstAdded }
            self.fetchSubscriptionInfo()
        }
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
        if selectedID != nil, !configs.contains(where: { $0.id == selectedID }) {
            selectedID = configs.first?.id
        }
        save()

        // Гасим туннель и убираем VPN-профиль из системных настроек,
        // иначе запись висит в «Настройки → VPN» даже без конфигов.
        tearDownVlessTunnelIfUnused()
    }

    /// Если VLESS-конфигов не осталось — останавливаем туннель и удаляем его профиль.
    func tearDownVlessTunnelIfUnused() {
        let stillHasVless = configs.contains { if case .vless = $0 { return true }; return false }
        guard !stillHasVless else { return }

        NETunnelProviderManager.loadAllFromPreferences { managers, _ in
            guard let managers else { return }
            for m in managers {
                let bundle = (m.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
                guard bundle == "com.tochkag.app.mac.tunnel" else { continue }
                let st = m.connection.status
                if st != .disconnected && st != .invalid { m.connection.stopVPNTunnel() }
                m.removeFromPreferences { _ in }
            }
        }
    }

    // ── Автообновление подписки ───────────────────────────

    /// Стабильный идентификатор машины для x-hwid.
    /// IOPlatformUUID; если недоступен (sandbox) — постоянный UUID в App Group.
    var machineHWID: String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice")
        )
        if service != 0 {
            defer { IOObjectRelease(service) }
            if let cf = IORegistryEntryCreateCFProperty(
                service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String, !cf.isEmpty {
                return cf.lowercased()
            }
        }
        let ud = UserDefaults(suiteName: "group.com.tochkag.vpn") ?? UserDefaults.standard
        if let saved = ud.string(forKey: "mac_hwid"), !saved.isEmpty { return saved }
        let fresh = UUID().uuidString.lowercased()
        ud.set(fresh, forKey: "mac_hwid")
        return fresh
    }

    /// Тихо обновляет подписку в фоне — добавляет новые серверы, обновляет существующие,
    /// удаляет пропавшие из ответа панели (кроме активной ноды).
    func refreshSubscription() {
        let effective = subscriptionURL ?? subscriptionURLs.first
        guard let urlStr = effective, !urlStr.isEmpty, let url = URL(string: urlStr) else {
            appLog("нет URL подписки — пропуск refresh")
            return
        }
        if subscriptionURL == nil { subscriptionURL = urlStr }
        if isRefreshingSubscription { return }
        isRefreshingSubscription = true

        var req = URLRequest(url: url)
        req.timeoutInterval = 15

        let osv        = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion  = "\(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)"
        let hwid       = machineHWID
        let model      = macModelIdentifier
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let locale     = Locale.current.language.languageCode?.identifier ?? "en"
        let userAgent  = "TochkaG/\(appVersion) (macOS \(osVersion); \(model))"

        req.setValue(hwid,       forHTTPHeaderField: "x-hwid")
        req.setValue("macOS",    forHTTPHeaderField: "x-device-os")
        req.setValue(osVersion,  forHTTPHeaderField: "x-ver-os")
        req.setValue(model,      forHTTPHeaderField: "x-device-model")
        req.setValue(locale,     forHTTPHeaderField: "x-device-locale")
        req.setValue(userAgent,  forHTTPHeaderField: "User-Agent")

        #if DEBUG
        print("[AUTO-REFRESH] hwid=\(hwid) ua=\(userAgent)")
        #endif

        URLSession.shared.dataTask(with: req) { [weak self] data, resp, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isRefreshingSubscription = false

                if let http = resp as? HTTPURLResponse {
                    print("[AUTO-REFRESH] HTTP \(http.statusCode)")
                    self.parseSubscriptionHeaders(http)
                }

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

    /// Идентификатор модели Mac (Mac15,7 и т.п.) для x-device-model.
    var macModelIdentifier: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        let s = String(cString: buf)
        return s.isEmpty ? "Mac" : s
    }

    // ── Разбор и синхронизация ────────────────────────────

    /// Парсит одну vless:// строку в VlessConfig
    func parseVlessLine(_ raw: String) -> VlessConfig? {
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

    /// Полная синхронизация подписки: добавляет новые, обновляет существующие,
    /// удаляет пропавшие из ответа панели.
    /// Трогает ТОЛЬКО конфиги текущей подписки — ручные VLESS и WireGuard не затрагиваются.
    /// Активную (подключённую) ноду не удаляем, чтобы не рвать VPN.
    func syncVlessConfigs(_ incoming: [VlessConfig]) {
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
            if self.selectedID != nil, !self.configs.contains(where: { $0.id == self.selectedID }) {
                self.selectedID = self.configs.first?.id
            }
            self.save()
        }
    }

    /// Мерджит новые VLESS-конфиги в существующий список по UUID+address+port.
    /// Новые добавляются, существующие обновляют параметры (но сохраняют id и isActive).
    func mergeVlessConfigs(_ incoming: [VlessConfig]) {
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

    // ── Метаданные подписки ───────────────────────────────

    /// Отдельный лёгкий запрос только за метаданными подписки.
    /// Не зависит от refreshSubscription — свой URLSession, свой разбор.
    func fetchSubscriptionInfo() {
        let effective = subscriptionURL ?? subscriptionURLs.first
        guard let urlStr = effective, !urlStr.isEmpty, let url = URL(string: urlStr) else {
            appLog("нет URL подписки")
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(machineHWID, forHTTPHeaderField: "x-hwid")
        req.setValue("macOS",     forHTTPHeaderField: "x-device-os")
        req.setValue("TochkaG/1.0 (macOS)", forHTTPHeaderField: "User-Agent")

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
            let keys = http.allHeaderFields.map { "\($0.key)" }.joined(separator: ",")
            self.appLog("HTTP \(http.statusCode) HDRS: \(keys)")
            self.parseSubscriptionHeaders(http)
        }.resume()
    }

    func parseSubscriptionHeaders(_ http: HTTPURLResponse) {
        var info = SubscriptionInfo()

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

    // ── Хелперы ───────────────────────────────────────────

    /// Панель отдаёт часть заголовков как "base64:...."
    func decodePanelBase64(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("base64:") else { return t }
        let body = String(t.dropFirst("base64:".count))
        let padded = body + String(repeating: "=", count: (4 - body.count % 4) % 4)
        if let d = Data(base64Encoded: padded), let s = String(data: d, encoding: .utf8) {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

    /// Декодер base64 (включая URL-safe)
    func decodeBase64IfNeeded(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("vless://") || trimmed.hasPrefix("vmess://") ||
           trimmed.hasPrefix("trojan://") || trimmed.hasPrefix("ss://") {
            return trimmed
        }
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

    /// Пишет в App Group — общий лог приложения и туннелей.
    func appLog(_ msg: String) {
        guard let ud = UserDefaults(suiteName: "group.com.tochkag.vpn") else { return }
        var l = ud.stringArray(forKey: "tunnel_logs") ?? []
        l.append("\(Date()) [APP] \(msg)")
        ud.set(Array(l.suffix(120)), forKey: "tunnel_logs")
    }

    /// Обновляет подписку после пробуждения Mac из сна.
    /// Сеть после wake поднимается не мгновенно — ждём, прежде чем бить в панель.
    func startWakeRefresh() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.appLog("WAKE: Mac проснулся, обновление подписки через 5 с")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                print("[WAKE] refreshSubscription")
                self.refreshSubscription()
            }
        }
    }

    /// Восстановление состояния подписки при старте + первое обновление.
    func bootstrapSubscription() {
        startWakeRefresh()
        if subscriptionInfo == nil,
           let d = UserDefaults.standard.data(forKey: "subscriptionInfo"),
           let i = try? JSONDecoder().decode(SubscriptionInfo.self, from: d) {
            subscriptionInfo = i
        }
        if subscriptionURL == nil {
            subscriptionURL = UserDefaults.standard.string(forKey: "subscriptionURL")
                ?? subscriptionURLs.first
        }
        refreshSubscription()
    }
}
