// PacketTunnelProvider.swift
// TochkaGTunnelWG — нативный WireGuardKit (исходники встроены), без Libbox

import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.tochkag.app.tunnel.wg", category: "WGTunnel")
    private var adapter: WireGuardAdapter?

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        os_log("WG START TUNNEL CALLED", log: log, type: .error)

        guard
            let proto = protocolConfiguration as? NETunnelProviderProtocol,
            let cfg   = proto.providerConfiguration
        else {
            os_log("WG MISSING CONFIG", log: log, type: .error)
            completionHandler(WGTunnelError.missingConfig)
            return
        }

        guard
            let privateKey  = cfg["privateKey"]  as? String,
            let publicKey   = cfg["publicKey"]   as? String,
            let endpoint    = cfg["endpoint"]    as? String,
            let address     = cfg["address"]     as? String,
            let dns         = cfg["dns"]         as? String,
            let allowedIPs  = cfg["allowedIPs"]  as? String
        else {
            os_log("WG MISSING FIELDS", log: log, type: .error)
            completionHandler(WGTunnelError.missingConfig)
            return
        }
        let presharedKey = cfg["presharedKey"] as? String ?? ""
        let extra = cfg["awg"] as? [String: String] ?? [:]

        os_log("WG CONFIG: endpoint=%{public}@ addr=%{public}@",
               log: log, type: .error, endpoint, address)

        let wgQuick = buildWgQuick(
            privateKey: privateKey, address: address, dns: dns,
            publicKey: publicKey, endpoint: endpoint,
            allowedIPs: allowedIPs, presharedKey: presharedKey,
            extra: extra
        )
        os_log("WG QUICK: %d bytes, awg keys: %{public}@", log: log, type: .error,
               wgQuick.count, extra.keys.sorted().joined(separator: ","))

        let tunnelConfig: TunnelConfiguration
        do {
            tunnelConfig = try TunnelConfiguration(fromWgQuickConfig: wgQuick, called: "tochkag")
        } catch {
            os_log("WG PARSE ERROR: %{public}@", log: log, type: .error, error.localizedDescription)
            completionHandler(error)
            return
        }

        let wgAdapter = WireGuardAdapter(with: self) { [weak self] logLevel, message in
            guard let self = self else { return }
            os_log("WGKIT: %{public}@", log: self.log, type: .error, message)
        }
        self.adapter = wgAdapter

        wgAdapter.start(tunnelConfiguration: tunnelConfig) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                os_log("WG START ERROR: %{public}@", log: self.log, type: .error,
                       error.localizedDescription)
                completionHandler(error)
                return
            }
            os_log("WG TUNNEL STARTED OK", log: self.log, type: .error)
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        os_log("WG STOP TUNNEL reason=%d", log: log, type: .error, reason.rawValue)
        adapter?.stop { [weak self] error in
            if let error = error {
                os_log("WG STOP ERROR: %{public}@",
                       log: self?.log ?? OSLog.disabled, type: .error,
                       error.localizedDescription)
            }
            completionHandler()
        }
    }

    private func buildWgQuick(privateKey: String, address: String, dns: String,
                               publicKey: String, endpoint: String,
                               allowedIPs: String, presharedKey: String,
                               extra: [String: String]) -> String {
        func list(_ s: String) -> String {
            s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: ", ")
        }
        let addrList = list(address), dnsList = list(dns), allowedList = list(allowedIPs)
        // AWG 1.0 — то, что понимает текущий парсер WireGuardKit из amneziawg-apple
        let awgKeys = ["Jc", "Jmin", "Jmax", "S1", "S2", "H1", "H2", "H3", "H4"]

        var iface = ["[Interface]",
                     "PrivateKey = \(privateKey)",
                     "Address = \(addrList.isEmpty ? address : addrList)"]
        if !dnsList.isEmpty { iface.append("DNS = \(dnsList)") }
        if let mtu = extra["MTU"], !mtu.isEmpty { iface.append("MTU = \(mtu)") }
        for k in awgKeys { if let v = extra[k], !v.isEmpty { iface.append("\(k) = \(v)") } }

        var peer = ["[Peer]", "PublicKey = \(publicKey)"]
        if !presharedKey.isEmpty { peer.append("PresharedKey = \(presharedKey)") }
        peer.append("Endpoint = \(endpoint)")
        peer.append("AllowedIPs = \(allowedList.isEmpty ? "0.0.0.0/0" : allowedList)")
        if let ka = extra["PersistentKeepalive"], !ka.isEmpty { peer.append("PersistentKeepalive = \(ka)") }

        return (iface + [""] + peer).joined(separator: "\n")
    }
}

enum WGTunnelError: LocalizedError {
    case missingConfig
    var errorDescription: String? { "Отсутствуют параметры WireGuard конфигурации" }
}
