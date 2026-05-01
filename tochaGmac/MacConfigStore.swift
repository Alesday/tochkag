import Foundation
import Combine
import NetworkExtension
import SwiftUI

enum AddMode: Identifiable, Hashable {
    case url, subscription, manualVless, manualWG, importFile
    var id: Self { self }
}

class MacConfigStore: ObservableObject {
    @Published var configs: [VPNConfig] = []
    @Published var vpnStatus: NEVPNStatus = .disconnected
    @Published var selectedID: UUID? = nil
    @Published var showAddMenu = false
    @Published var addMode: AddMode? = nil

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
        selectedID = config.id
        save()
    }

    func delete(_ config: VPNConfig) {
        if config.isActive { disconnect() }
        configs.removeAll { $0.id == config.id }
        if selectedID == config.id { selectedID = configs.first?.id }
        save()
    }

    func toggle(_ config: VPNConfig) {
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
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            DispatchQueue.main.async {
                self?.vpnManager = managers?.first ?? NETunnelProviderManager()
                self?.observeStatus()
                self?.vpnStatus = self?.vpnManager?.connection.status ?? .disconnected
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
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            guard let self = self else { return }
            let all = managers ?? []
            let targetBundle: String = {
                switch config {
                case .vless:     return "com.tochkag.app.mac.tunnel"
                case .wireguard: return "com.tochkag.app.mac.tunnelwg"
                }
            }()
            let existing = all.first {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == targetBundle
            }
            let others = all.filter { $0 !== existing }
            for m in others {
                let st = m.connection.status
                if st != .disconnected && st != .invalid { m.connection.stopVPNTunnel() }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.applyAndStart(manager: existing ?? NETunnelProviderManager(), config: config)
            }
        }
    }

    private func applyAndStart(manager: NETunnelProviderManager, config: VPNConfig) {
        let proto = NETunnelProviderProtocol()
        switch config {
        case .vless:     proto.providerBundleIdentifier = "com.tochkag.app.mac.tunnel"
        case .wireguard: proto.providerBundleIdentifier = "com.tochkag.app.mac.tunnelwg"
        }
        switch config {
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
        case .wireguard(let wg):
            proto.serverAddress = wg.endpoint
            proto.providerConfiguration = [
                "type": "wireguard", "privateKey": wg.privateKey,
                "address": wg.address, "dns": wg.dns,
                "publicKey": wg.publicKey, "endpoint": wg.endpoint,
                "allowedIPs": wg.allowedIPs, "presharedKey": wg.presharedKey,
            ]
        }
        manager.protocolConfiguration = proto
        manager.localizedDescription = "tochkaG"
        manager.isEnabled = true
        manager.saveToPreferences { [weak self] error in
            guard let self = self else { return }
            if let error = error { print("VPN save error:", error); return }
            manager.loadFromPreferences { error in
                if let error = error { print("VPN load error:", error); return }
                self.vpnManager = manager
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    do { try manager.connection.startVPNTunnel() }
                    catch { print("Tunnel error:", error) }
                }
            }
        }
    }

    private func disconnect() {
        vpnManager?.connection.stopVPNTunnel()
    }
}
