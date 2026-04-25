import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.tochkag.app.tunnel", category: "VLESSTunnel")
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
            } else {
                try? data.write(to: file)
            }
        }
    }

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        flog("START TUNNEL CALLED")

        guard
            let proto = protocolConfiguration as? NETunnelProviderProtocol,
            let cfg   = proto.providerConfiguration,
            let type  = cfg["type"] as? String, type == "vless",
            let uuid     = cfg["uuid"]     as? String,
            let address  = cfg["address"]  as? String,
            let port     = cfg["port"]     as? String,
            let network  = cfg["network"]  as? String,
            let security = cfg["security"] as? String,
            let sni      = cfg["sni"]      as? String,
            let path     = cfg["path"]     as? String
        else {
            flog("MISSING CONFIG")
            completionHandler(TunnelError.missingConfig)
            return
        }
        let pbk  = cfg["pbk"]  as? String ?? ""
        let sid  = cfg["sid"]  as? String ?? ""
        let flow = cfg["flow"] as? String ?? ""
        let fp      = cfg["fp"]      as? String ?? "chrome"
        let routing = cfg["routing"] as? String ?? ""

        flog("CONFIG: \(address):\(port) net=\(network) sec=\(security)")

        let xrayJSON = makeXrayConfig(uuid: uuid, address: address, port: port,
                                       network: network, security: security, sni: sni,
                                       path: path, pbk: pbk, sid: sid, flow: flow, fp: fp, routing: routing)

        completionHandler(nil)
        flog("COMPLETION HANDLER OK")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.setupTunnelAndXray(configJSON: xrayJSON)
        }
    }

    private func setupTunnelAndXray(configJSON: String) {
        flog("SETUP TUN SETTINGS")

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: 1500)
        settings.dnsSettings = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        let ipv4 = NEIPv4Settings(addresses: ["172.19.0.1"], subnetMasks: ["255.255.255.252"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        settings.ipv4Settings = ipv4
        let ipv6 = NEIPv6Settings(addresses: ["fdfe:dcba:9876::1"], networkPrefixLengths: [126])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        settings.ipv6Settings = ipv6

        let sem = DispatchSemaphore(value: 0)
        setTunnelNetworkSettings(settings) { [weak self] error in
            if let e = error { self?.flog("TUN ERROR: \(e)") }
            else { self?.flog("TUN SETTINGS OK") }
            sem.signal()
        }
        sem.wait()

        runXray(configJSON: configJSON)
    }

    private func scanUtunFd() -> Int32 {
        // Сканируем fd через getsockopt UTUN_OPT_IFNAME
        for candidate in 3..<512 {
            var ifname = [CChar](repeating: 0, count: 32)
            var len = socklen_t(32)
            let fd = Int32(candidate)
            if getsockopt(fd, 2, 2, &ifname, &len) == 0 {
                let name = String(cString: ifname)
                if name.hasPrefix("utun") {
                    flog("Found utun: fd=\(fd) name=\(name)")
                    return fd
                }
            }
        }
        return -1
    }

    private func runXray(configJSON: String) {
        flog("XRAY: starting")

        // Пробуем получить TUN FD через SafeKVC
        var tunFd: Int32 = -1
        for key in ["socket.fileDescriptor", "fileDescriptor", "tunnelFileDescriptor"] {
            if let val = safeValueForKeyPath(packetFlow, key) as? Int32, val >= 0 {
                tunFd = val
                flog("TUN FD via KVC[\(key)]=\(val)")
                break
            }
        }

        // Fallback: сканируем utun
        if tunFd < 0 {
            tunFd = scanUtunFd()
        }

        flog("TUN FD final: \(tunFd)")
        LibXraySetTunFd(tunFd)

        let appGroup = "group.com.tochkag.vpn"
        let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        // Очищаем старый лог
        let xrayLogPath = groupURL.appendingPathComponent("xray.log").path
        try? FileManager.default.removeItem(atPath: xrayLogPath)

        let request: [String: Any] = [
            "datDir": groupURL.path,
            "mphCachePath": groupURL.appendingPathComponent("mph.cache").path,
            "configJSON": configJSON
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            flog("XRAY: request build failed")
            return
        }
        let base64 = Data(jsonStr.utf8).base64EncodedString()
        flog("Calling RunXrayFromJSON...")
        let result: String = LibXrayRunXrayFromJSON(base64)
        flog("RunXrayFromJSON result: \(result)")

        if result.contains("success") {
            xrayRunning = true
            flog("XRAY STARTED OK — tunFd=\(tunFd)")
        } else {
            flog("XRAY FAILED: \(result)")
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        flog("STOP TUNNEL reason=\(reason.rawValue)")
        if xrayRunning {
            let r: String = LibXrayStopXray()
            flog("XRAY STOP: \(r)")
            xrayRunning = false
        }
        completionHandler()
    }

    private func makeXrayConfig(uuid: String, address: String, port: String,
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

        // Если TUN FD будет найден — используем tun inbound
        // Иначе dokodemo-door (прокси режим)
        let inbound = "{\"tag\":\"tun-in\",\"protocol\":\"tun\",\"settings\":{\"name\":\"utun5\",\"mtu\":1500,\"userLevel\":0}}"

        let routingRules = routing.isEmpty ? "[]" : routing
        return "{\"log\":{\"loglevel\":\"warning\"},\"dns\":{\"servers\":[\"1.1.1.1\",\"8.8.8.8\"]},\"inbounds\":[\(inbound)],\"outbounds\":[{\"tag\":\"vless-out\",\"protocol\":\"vless\",\"settings\":{\"vnext\":[{\"address\":\"\(address)\",\"port\":\(portInt),\"users\":[{\"id\":\"\(uuid)\",\"encryption\":\"none\"\(flowPart)}]}]},\(streamStr)},{\"tag\":\"direct\",\"protocol\":\"freedom\"}],\"routing\":{\"domainStrategy\":\"AsIs\",\"rules\":\(routingRules)}}"
    }
}

enum TunnelError: LocalizedError {
    case missingConfig
    var errorDescription: String? { "Отсутствуют параметры конфигурации" }
}
