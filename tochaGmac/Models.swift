// Models.swift
// TochkaG

import Foundation

enum VPNProtocol: String, Codable {
    case wireguard = "wireguard"
    case vless     = "vless"
}

// ── WireGuard ─────────────────────────────────────────────
struct WireGuardConfig: Codable, Identifiable {
    var id       = UUID()
    var name:       String
    var privateKey: String
    var address:    String
    var dns:        String
    var publicKey:  String
    var endpoint:   String
    var allowedIPs: String
    var presharedKey: String = ""
    var isActive:   Bool = false
}

// ── VLESS ─────────────────────────────────────────────────
struct VlessConfig: Codable, Identifiable {
    var id       = UUID()
    var name:     String
    var uuid:     String
    var address:  String
    var port:     String
    var path:     String
    var network:  String  // ws | tcp | grpc | httpupgrade
    var security: String  // tls | none | reality
    var sni:      String
    var publicKey:   String = ""   // Reality pbk
    var shortId:     String = ""   // Reality sid
    var flow:        String = ""   // xtls-rprx-vision (optional)
    var fingerprint: String = "chrome" // utls fp
    var routing:  String = ""   // custom Xray routing JSON (optional)
    var isActive: Bool = false
}

// ── Unified wrapper ───────────────────────────────────────
enum VPNConfig: Identifiable, Codable {
    case wireguard(WireGuardConfig)
    case vless(VlessConfig)

    var id: UUID {
        switch self {
        case .wireguard(let c): return c.id
        case .vless(let c):     return c.id
        }
    }

    var name: String {
        switch self {
        case .wireguard(let c): return c.name
        case .vless(let c):     return c.name
        }
    }

    var isActive: Bool {
        get {
            switch self {
            case .wireguard(let c): return c.isActive
            case .vless(let c):     return c.isActive
            }
        }
        set {
            switch self {
            case .wireguard(var c): c.isActive = newValue; self = .wireguard(c)
            case .vless(var c):     c.isActive = newValue; self = .vless(c)
            }
        }
    }

    var protocolType: VPNProtocol {
        switch self {
        case .wireguard: return .wireguard
        case .vless:     return .vless
        }
    }

    var subtitle: String {
        switch self {
        case .wireguard(let c): return c.endpoint
        case .vless(let c):     return "\(c.address):\(c.port)"
        }
    }
}
