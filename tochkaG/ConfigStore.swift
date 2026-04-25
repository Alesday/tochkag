// ConfigStore.swift
// TochkaG

import Foundation
import Combine
import NetworkExtension

class ConfigStore: ObservableObject {
    @Published var configs: [VPNConfig] = []
    @Published var vpnStatus: NEVPNStatus = .disconnected
    @Published var debugText: String = ""
    @Published var configWasAdded: Bool = false
    @Published var pendingSubscriptionURL: String? = nil
    @Published var pendingVlessURL: String? = nil

    private let saveKey = "tochkag_configs"
    private let appGroup = "group.com.tochkag.vpn"
    private var vpnManager: NETunnelProviderManager?
    private var statusObserver: AnyCancellable?

    init() {
        load()
        setupVPNManager()
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
            }
        }
    }

    private func observeStatus() {
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
            print("CONNECT: found \(all.count) existing manager(s)")

            let targetUUID = self.configUUID(config)
            print("CONNECT: target type=\(config.protocolType.rawValue) uuid=\(targetUUID)")
            for m in all {
                if let p = m.protocolConfiguration as? NETunnelProviderProtocol,
                   let cfg = p.providerConfiguration {
                    let t = (cfg["type"] as? String) ?? "?"
                    let u = (cfg["uuid"] as? String) ?? (cfg["publicKey"] as? String) ?? "?"
                    print("CONNECT: manager[\(m.localizedDescription ?? "?")] type=\(t) uuid=\(u)")
                }
            }

            // Целевой bundle ID по типу config
            let targetBundle: String = {
                switch config {
                case .vless:     return "com.tochkag.app.tunnel"
                case .wireguard: return "com.tochkag.app.tunnel.wg"
                }
            }()

            // Ищем manager именно с нашим tunnel bundleIdentifier
            let existing = all.first { m in
                guard let p = m.protocolConfiguration as? NETunnelProviderProtocol else { return false }
                return p.providerBundleIdentifier == targetBundle
            }

            // Чужие активные менеджеры — стопаем, но НЕ удаляем (они переиспользуются)
            let others = all.filter { $0 !== existing }
            for m in others {
                let st = m.connection.status
                if st != .disconnected && st != .invalid {
                    m.connection.stopVPNTunnel()
                }
            }

            // Ждём пока чужие активные отсоединятся (макс 5с)
            self.waitForAllDisconnected(managers: others, maxWait: 10.0) {
                // даём iOS время чисто закрыть сетевой стек после stopVPNTunnel
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.proceedConnect(config: config, existing: existing)
                }
            }
        }
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
        case .wireguard: proto.providerBundleIdentifier = "com.tochkag.app.tunnel.wg"
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    do {
                        print("STARTING TUNNEL")
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
}
