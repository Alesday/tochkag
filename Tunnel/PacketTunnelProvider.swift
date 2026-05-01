import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var xrayRunning = false

    private func flog(_ msg: String) {
        let appGroup = "group.com.tochkag.vpn"
        if let ud = UserDefaults(suiteName: appGroup) {
            var logs = ud.stringArray(forKey: "tunnel_logs") ?? []
            logs.append("\(Date()) \(msg)")
            if logs.count > 100 { logs = Array(logs.suffix(100)) }
            ud.set(logs, forKey: "tunnel_logs")
            ud.synchronize()
        }
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return }
        let file = dir.appendingPathComponent("tunnel.log")
        let line = "\(Date()) \(msg)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: file.path) {
                if let fh = try? FileHandle(forWritingTo: file) {
                    fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
                }
            } else { try? data.write(to: file) }
        }
    }

    private func cgoCallStr(_ fn: (UnsafeMutablePointer<CChar>?) -> UnsafeMutablePointer<CChar>?, _ input: String) -> String {
        var result = ""
        let bytes = Array(input.utf8) + [0]
        bytes.withUnsafeBytes { ptr in
            let mutable = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
            mutable.initialize(from: ptr.bindMemory(to: CChar.self).baseAddress!, count: bytes.count)
            defer { mutable.deallocate() }
            if let ret = fn(mutable) { result = String(cString: ret) }
        }
        return result
    }

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        flog("START TUNNEL CALLED")
        guard
            let proto = protocolConfiguration as? NETunnelProviderProtocol,
            let cfg   = proto.providerConfiguration,
            let type  = cfg["type"] as? String
        else {
            flog("MISSING CONFIG")
            completionHandler(TunnelError.missingConfig)
            return
        }

        flog("CONFIG TYPE: \(type)")

        if type == "vless" {
            startVless(cfg: cfg, completionHandler: completionHandler)
        } else {
            flog("UNKNOWN TYPE: \(type)")
            completionHandler(TunnelError.missingConfig)
        }
    }





    // MARK: - VLESS

    private func startVless(cfg: [String: Any], completionHandler: @escaping (Error?) -> Void) {
        guard
            let uuid     = cfg["uuid"]     as? String,
            let address  = cfg["address"]  as? String,
            let port     = cfg["port"]     as? String,
            let network  = cfg["network"]  as? String,
            let security = cfg["security"] as? String,
            let sni      = cfg["sni"]      as? String,
            let path     = cfg["path"]     as? String
        else {
            flog("VLESS: MISSING FIELDS")
            completionHandler(TunnelError.missingConfig)
            return
        }
        let pbk     = cfg["pbk"]     as? String ?? ""
        let sid     = cfg["sid"]     as? String ?? ""
        let flow    = cfg["flow"]    as? String ?? ""
        let fp      = cfg["fp"]      as? String ?? "chrome"
        let routing = cfg["routing"] as? String ?? ""

        flog("VLESS: \(address):\(port) net=\(network) sec=\(security)")
        let xrayJSON = makeVlessConfig(uuid: uuid, address: address, port: port,
                                       network: network, security: security, sni: sni,
                                       path: path, pbk: pbk, sid: sid, flow: flow,
                                       fp: fp, routing: routing)

        // Build network settings
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: address)
        settings.mtu = NSNumber(value: 1500)
        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dns.matchDomains = [""]
        dns.matchDomainsNoSearch = false
        settings.dnsSettings = dns
        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        // Exclude the VPN server itself so its packets don't route into the tunnel
        ipv4.excludedRoutes = [
            NEIPv4Route(destinationAddress: address, subnetMask: "255.255.255.255"),
            NEIPv4Route(destinationAddress: "1.1.1.1", subnetMask: "255.255.255.255"),
            NEIPv4Route(destinationAddress: "1.0.0.1", subnetMask: "255.255.255.255"),
            NEIPv4Route(destinationAddress: "8.8.8.8", subnetMask: "255.255.255.255"),
            NEIPv4Route(destinationAddress: "8.8.4.4", subnetMask: "255.255.255.255")
        ]
        settings.ipv4Settings = ipv4
        let ipv6 = NEIPv6Settings(addresses: ["fdfe:dcba:9876::1"], networkPrefixLengths: [126])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        flog("VLESS: applying TUN settings")
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            if let e = error {
                self.flog("VLESS TUN ERROR: \(e)")
                completionHandler(e)
                return
            }
            self.flog("VLESS TUN SETTINGS OK")
            self.runXray(configJSON: xrayJSON)
            self.flog("VLESS: completionHandler OK")
            completionHandler(nil)
        }
    }



    // MARK: - Xray runner

    private func getTunFd() -> Int32 {
        for key in ["socket.fileDescriptor", "fileDescriptor", "tunnelFileDescriptor"] {
            if let val = safeValueForKeyPath(packetFlow, key) as? Int32, val >= 0 {
                flog("TUN FD via KVC[\(key)]=\(val)")
                return val
            }
        }
        // scan
        for candidate in 3..<512 {
            var ifname = [CChar](repeating: 0, count: 32)
            var len = socklen_t(32)
            let fd = Int32(candidate)
            if getsockopt(fd, 2, 2, &ifname, &len) == 0 {
                let name = String(cString: ifname)
                if name.hasPrefix("utun") {
                    flog("Found utun fd=\(fd) name=\(name)")
                    return fd
                }
            }
        }
        return -1
    }

    private func runXray(configJSON: String) {
        flog("XRAY: starting")
        let tunFd = getTunFd()
        flog("TUN FD final: \(tunFd)")
        CGoSetTunFd(tunFd)

        let appGroup = "group.com.tochkag.vpn"
        let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        try? FileManager.default.removeItem(atPath: groupURL.appendingPathComponent("xray.log").path)

        let request: [String: Any] = [
            "datDir": groupURL.path,
            "mphCachePath": groupURL.appendingPathComponent("mph.cache").path,
            "configJSON": configJSON
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              String(data: jsonData, encoding: .utf8) != nil else {
            flog("XRAY: request build failed"); return
        }
        let xrayLogPath = groupURL.appendingPathComponent("xray.log").path
        let configFixed = configJSON.replacingOccurrences(of: "%XRAY_LOG%", with: xrayLogPath)
        var req2 = request; req2["configJSON"] = configFixed
        guard let jd2 = try? JSONSerialization.data(withJSONObject: req2),
              let js2 = String(data: jd2, encoding: .utf8) else { flog("XRAY req2 fail"); return }
        let base64 = Data(js2.utf8).base64EncodedString()
        flog("Calling CGoRunXrayFromJSON...")
        let result = cgoCallStr(CGoRunXrayFromJSON, base64)
        flog("CGoRunXrayFromJSON result: \(result)")
        xrayRunning = true
        flog("XRAY STARTED — tunFd=\(tunFd)")
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        flog("STOP TUNNEL reason=\(reason.rawValue)")
        if xrayRunning {
            if let ret = CGoStopXray() {
                flog("XRAY STOP: \(String(cString: ret))")
            }
            xrayRunning = false
        }
        completionHandler()
    }

    // MARK: - Helpers



    private func makeVlessConfig(uuid: String, address: String, port: String,
                                 network: String, security: String, sni: String,
                                 path: String, pbk: String, sid: String,
                                 flow: String, fp: String, routing: String = "") -> String {
        let portInt = Int(port) ?? 443
        let fpSafe = fp.isEmpty ? "chrome" : fp
        let flowPart = flow.isEmpty ? "" : ",\"flow\":\"\(flow)\""
        let tlsStr: String
        switch security {
        case "reality":
            tlsStr = "\"security\":\"reality\",\"realitySettings\":{\"serverName\":\"\(sni)\",\"fingerprint\":\"\(fpSafe)\",\"publicKey\":\"\(pbk)\",\"shortId\":\"\(sid)\"}"
        case "tls":
            tlsStr = "\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"\(sni)\",\"fingerprint\":\"\(fpSafe)\"}"
        default:
            tlsStr = "\"security\":\"none\""
        }
        let streamStr: String
        switch network {
        case "ws":
            streamStr = "\"streamSettings\":{\"network\":\"ws\",\(tlsStr),\"wsSettings\":{\"path\":\"\(path)\",\"headers\":{\"Host\":\"\(sni)\"}}}"
        case "grpc":
            let svc = path.hasPrefix("/") ? String(path.dropFirst()) : path
            streamStr = "\"streamSettings\":{\"network\":\"grpc\",\(tlsStr),\"grpcSettings\":{\"serviceName\":\"\(svc)\"}}"
        case "httpupgrade":
            streamStr = "\"streamSettings\":{\"network\":\"httpupgrade\",\(tlsStr),\"httpupgradeSettings\":{\"path\":\"\(path)\",\"host\":\"\(sni)\"}}"
        default:
            streamStr = "\"streamSettings\":{\"network\":\"tcp\",\(tlsStr)}"
        }
        let inbound = "{\"tag\":\"tun-in\",\"protocol\":\"tun\",\"settings\":{\"mtu\":1500},\"sniffing\":{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\"],\"routeOnly\":false}}"
        let quicBlock = "{\"type\":\"field\",\"network\":\"udp\",\"port\":\"443\",\"outboundTag\":\"block\"}"
        let routingRules = routing.isEmpty ? quicBlock : routing
        return "{\"log\":{\"loglevel\":\"debug\",\"error\":\"%XRAY_LOG%\"},\"dns\":{\"servers\":[\"https+local://1.1.1.1/dns-query\",\"https+local://8.8.8.8/dns-query\",\"1.1.1.1\"],\"queryStrategy\":\"UseIPv4\",\"disableCache\":false,\"tag\":\"dns_inbound\"},\"inbounds\":[\(inbound)],\"outbounds\":[{\"tag\":\"vless-out\",\"protocol\":\"vless\",\"settings\":{\"vnext\":[{\"address\":\"\(address)\",\"port\":\(portInt),\"users\":[{\"id\":\"\(uuid)\",\"encryption\":\"none\"\(flowPart)}]}]},\(streamStr)},{\"tag\":\"direct\",\"protocol\":\"freedom\"},{\"tag\":\"block\",\"protocol\":\"blackhole\"}],\"routing\":{\"domainStrategy\":\"AsIs\",\"rules\":[\(routingRules)]}}"
    }
}

enum TunnelError: LocalizedError {
    case missingConfig
    var errorDescription: String? { "Missing config" }
}
