import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "com.tochkag.app.tunnel", category: "VLESSTunnel")
    private var xrayRunning = false

    /// LibXray возвращает base64 от JSON вида {"success":true} — декодируем.
    /// Копирует geosite.dat из бандла в App Group и строит MPH-кеш,
    /// без которого Xray не может загрузить geodata.
    private func ensureGeoAssets(into groupURL: URL) {
        let fm = FileManager.default
        for base in ["geosite", "geoip"] {
            let dst = groupURL.appendingPathComponent("\(base).dat")
            guard let src = Bundle.main.url(forResource: base, withExtension: "dat") else {
                flog("GEO: \(base).dat not found in bundle")
                continue
            }
            let sz = (try? fm.attributesOfItem(atPath: src.path)[.size] as? Int) ?? 0
            let dz = (try? fm.attributesOfItem(atPath: dst.path)[.size] as? Int) ?? 0
            if fm.fileExists(atPath: dst.path), sz == dz, sz > 0 {
                flog("GEO: \(base).dat up to date (\(dz))")
                continue
            }
            try? fm.removeItem(at: dst)
            do { try fm.copyItem(at: src, to: dst); flog("GEO: copied \(base).dat (\(sz))") }
            catch { flog("GEO: copy \(base) failed: \(error)") }
        }
        return
        let dst = groupURL.appendingPathComponent("geosite.dat")
        guard let src = Bundle.main.url(forResource: "geosite", withExtension: "dat") else {
            flog("GEO: geosite.dat not found in bundle")
            return
        }
        let srcSize = (try? fm.attributesOfItem(atPath: src.path)[.size] as? Int) ?? 0
        let dstSize = (try? fm.attributesOfItem(atPath: dst.path)[.size] as? Int) ?? 0
        if !(fm.fileExists(atPath: dst.path) && srcSize == dstSize && srcSize > 0) {
            try? fm.removeItem(at: dst)
            do {
                try fm.copyItem(at: src, to: dst)
                flog("GEO: copied geosite.dat (\(srcSize) bytes)")
            } catch {
                flog("GEO: copy failed: \(error)")
                return
            }
        } else {
            flog("GEO: geosite.dat up to date (\(dstSize) bytes)")
        }

        // MPH-кеш НЕ строим вручную: LibXrayBuildMphCache на 11 МБ geosite
        // роняет Network Extension по памяти. Xray строит индекс сам.
        flog("GEO: ready, skipping manual MPH build")
    }

    private func decodeXrayResult(_ raw: String) -> (ok: Bool, text: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let padded = t + String(repeating: "=", count: (4 - t.count % 4) % 4)
        if let d = Data(base64Encoded: padded),
           let json = String(data: d, encoding: .utf8) {
            return (json.contains("\"success\":true"), json)
        }
        return (t.contains("success"), t)
    }

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
            let type  = cfg["type"] as? String
        else {
            flog("MISSING CONFIG")
            completionHandler(TunnelError.missingConfig)
            return
        }

        flog("CONFIG TYPE: \(type)")

        if type == "wireguard" {
            startWireGuard(cfg: cfg, completionHandler: completionHandler)
        } else if type == "vless" {
            startVless(cfg: cfg, completionHandler: completionHandler)
        } else {
            flog("UNKNOWN TYPE: \(type)")
            completionHandler(TunnelError.missingConfig)
        }
    }

    private func startWireGuard(cfg: [String: Any], completionHandler: @escaping (Error?) -> Void) {
        guard
            let privateKey  = cfg["privateKey"]  as? String,
            let publicKey   = cfg["publicKey"]   as? String,
            let endpoint    = cfg["endpoint"]    as? String,
            let address     = cfg["address"]     as? String,
            let dns         = cfg["dns"]         as? String,
            let allowedIPs  = cfg["allowedIPs"]  as? String
        else {
            flog("WG: MISSING FIELDS")
            completionHandler(TunnelError.missingConfig)
            return
        }
        let presharedKey = cfg["presharedKey"] as? String ?? ""
        flog("WG: endpoint=\(endpoint) addr=\(address)")

        let addrParts = address.split(separator: "/")
        let tunAddr = String(addrParts.first ?? "10.0.0.2")
        let prefix = Int(addrParts.last ?? "24") ?? 24

        let endpointHost = String(endpoint.split(separator: ":").first ?? "127.0.0.1")
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: endpointHost)
        settings.mtu = NSNumber(value: 1420)
        settings.dnsSettings = NEDNSSettings(servers: dns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })

        let mask = prefix == 0 ? "0.0.0.0" : {
            let m = (~0 << (32 - prefix))
            return "\((m >> 24) & 0xFF).\((m >> 16) & 0xFF).\((m >> 8) & 0xFF).\(m & 0xFF)"
        }()
        let ipv4 = NEIPv4Settings(addresses: [tunAddr], subnetMasks: [mask])
        var included: [NEIPv4Route] = []
        for cidr in allowedIPs.split(separator: ",") {
            let s = cidr.trimmingCharacters(in: .whitespaces)
            if s.contains(":") { continue }
            let parts = s.split(separator: "/")
            let ip = String(parts.first ?? "0.0.0.0")
            let pfx = Int(parts.last ?? "0") ?? 0
            if ip == "0.0.0.0" && pfx == 0 {
                included.append(NEIPv4Route.default())
            } else {
                let pm = pfx == 0 ? "0.0.0.0" : {
                    let m = (~0 << (32 - pfx))
                    return "\((m >> 24) & 0xFF).\((m >> 16) & 0xFF).\((m >> 8) & 0xFF).\(m & 0xFF)"
                }()
                included.append(NEIPv4Route(destinationAddress: ip, subnetMask: pm))
            }
        }
        if included.isEmpty { included = [NEIPv4Route.default()] }
        ipv4.includedRoutes = included
        settings.ipv4Settings = ipv4

        completionHandler(nil)
        flog("WG: completionHandler OK")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let sem = DispatchSemaphore(value: 0)
            self.setTunnelNetworkSettings(settings) { error in
                if let e = error { self.flog("WG TUN ERROR: \(e)") }
                else { self.flog("WG TUN SETTINGS OK") }
                sem.signal()
            }
            sem.wait()
            self.runWireGuard(privateKey: privateKey, publicKey: publicKey,
                              endpoint: endpoint, allowedIPs: allowedIPs,
                              presharedKey: presharedKey, dns: dns)
        }
    }

    private func runWireGuard(privateKey: String, publicKey: String,
                              endpoint: String, allowedIPs: String,
                              presharedKey: String, dns: String) {
        flog("WG: runWireGuard — using WireGuardAdapter not available in this target")
        flog("WG: this tunnel target uses Xray, not WireGuardKit")
        // WireGuard через Xray не поддерживается в TochkaGTunnel
        // Нужен отдельный таргет TochkaGTunnelWG с bundle com.tochkag.app.tunnelwg
    }

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
        let pbk  = cfg["pbk"]  as? String ?? ""
        let sid  = cfg["sid"]  as? String ?? ""
        let flow = cfg["flow"] as? String ?? ""
        let fp      = cfg["fp"]      as? String ?? "chrome"
        let routing = cfg["routing"] as? String ?? ""

        flog("VLESS: \(address):\(port) net=\(network) sec=\(security)")

        let xrayJSON = makeXrayConfig(uuid: uuid, address: address, port: port,
                                       network: network, security: security, sni: sni,
                                       path: path, pbk: pbk, sid: sid, flow: flow, fp: fp, routing: routing)

        completionHandler(nil)
        flog("VLESS: completionHandler OK")

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

        ensureGeoAssets(into: groupURL)

        // Очищаем старый лог
        let xrayLogPath = groupURL.appendingPathComponent("xray.log").path
        try? FileManager.default.removeItem(atPath: xrayLogPath)

        let request: [String: Any] = [
            "datDir": groupURL.path,
            "mphCachePath": "",
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

        let decoded = decodeXrayResult(result)
        flog("XRAY decoded: \(decoded.text)")
        if decoded.ok {
            xrayRunning = true
            flog("XRAY STARTED OK — tunFd=\(tunFd)")
        } else {
            flog("XRAY FAILED: \(decoded.text)")
        }
    }


    // MARK: - Hot-Switch VLESS server (без остановки туннеля)

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        guard let payload = try? JSONSerialization.jsonObject(with: messageData) as? [String: Any],
              let action  = payload["action"] as? String else {
            completionHandler?(Data("invalid".utf8))
            return
        }

        switch action {
        case "switchServer":
            flog("HOT-SWITCH: incoming switchServer")
            hotSwitchVless(payload: payload) { ok in
                completionHandler?(Data((ok ? "ok" : "fail").utf8))
            }
        case "ping":
            completionHandler?(Data("pong".utf8))
        default:
            completionHandler?(Data("unknown".utf8))
        }
    }

    /// Пересоздаёт Xray-инстанс с новыми параметрами VLESS-сервера.
    /// TUN-интерфейс и сетевые настройки НЕ трогаются — только outbound в Xray.
    private func hotSwitchVless(payload: [String: Any], completion: @escaping (Bool) -> Void) {
        guard
            let uuid     = payload["uuid"]     as? String,
            let address  = payload["address"]  as? String,
            let port     = payload["port"]     as? String,
            let network  = payload["network"]  as? String,
            let security = payload["security"] as? String,
            let sni      = payload["sni"]      as? String,
            let path     = payload["path"]     as? String
        else {
            flog("HOT-SWITCH: missing fields")
            completion(false)
            return
        }
        let pbk     = payload["pbk"]     as? String ?? ""
        let sid     = payload["sid"]     as? String ?? ""
        let flow    = payload["flow"]    as? String ?? ""
        let fp      = payload["fp"]      as? String ?? "chrome"
        let routing = payload["routing"] as? String ?? ""

        flog("HOT-SWITCH: \(address):\(port) net=\(network)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { completion(false); return }

            // 1) Останавливаем текущий Xray instance
            if self.xrayRunning {
                let r = LibXrayStopXray()
                self.flog("HOT-SWITCH: LibXrayStopXray => \(r)")
                self.xrayRunning = false
            }

            // 2) Краткая пауза чтобы Go освободил порты/сокеты
            Thread.sleep(forTimeInterval: 0.1)

            // 2.5) КРИТИЧНО: заново отдаём ядру TUN fd (как в runXray).
            // Без этого новый инстанс Xray не может открыть tun inbound → RunXrayFromJSON => fail.
            var tunFd: Int32 = -1
            for key in ["socket.fileDescriptor", "fileDescriptor", "tunnelFileDescriptor"] {
                if let val = safeValueForKeyPath(self.packetFlow, key) as? Int32, val >= 0 {
                    tunFd = val
                    self.flog("HOT-SWITCH: TUN FD via KVC[\(key)]=\(val)")
                    break
                }
            }
            if tunFd < 0 { tunFd = self.scanUtunFd() }
            self.flog("HOT-SWITCH: TUN FD final=\(tunFd)")
            LibXraySetTunFd(tunFd)

            // 3) Собираем новый Xray JSON
            let newJSON = self.makeXrayConfig(
                uuid: uuid, address: address, port: port,
                network: network, security: security, sni: sni,
                path: path, pbk: pbk, sid: sid, flow: flow, fp: fp,
                routing: routing
            )

            // 4) Запускаем Xray с новым конфигом
            //    TUN FD уже установлен при первом startTunnel — НЕ переустанавливаем
            let appGroup = "group.com.tochkag.vpn"
            let groupURL = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
                ?? URL(fileURLWithPath: NSTemporaryDirectory())

            let request: [String: Any] = [
                "datDir": groupURL.path,
                "mphCachePath": "",
                "configJSON": newJSON
            ]
            guard let jsonData = try? JSONSerialization.data(withJSONObject: request),
                  let jsonStr  = String(data: jsonData, encoding: .utf8) else {
                self.flog("HOT-SWITCH: request build failed")
                completion(false)
                return
            }
            let base64 = Data(jsonStr.utf8).base64EncodedString()
            self.flog("HOT-SWITCH: RunXrayFromJSON...")
            let result: String = LibXrayRunXrayFromJSON(base64)
            self.flog("HOT-SWITCH: RunXrayFromJSON => \(result)")

            let decodedHS = self.decodeXrayResult(result)
            self.flog("HOT-SWITCH decoded: \(decodedHS.text)")
            if decodedHS.ok {
                self.xrayRunning = true
                self.flog("HOT-SWITCH: SUCCESS — switched to \(address):\(port)")
                completion(true)
            } else {
                self.flog("HOT-SWITCH: FAILED — \(result)")
                completion(false)
            }
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
        let groupPath = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.tochkag.vpn")?.path
            ?? NSTemporaryDirectory()
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
        let sniff = ",\"sniffing\":{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"],\"routeOnly\":false}"
        let inbound = "{\"tag\":\"tun-in\",\"protocol\":\"tun\",\"settings\":{\"name\":\"utun5\",\"mtu\":1500,\"userLevel\":0}\(sniff)}"

        let defaultRules = "[{\"type\":\"field\",\"outboundTag\":\"direct\",\"port\":\"53\"},{\"type\":\"field\",\"outboundTag\":\"direct\",\"port\":\"53\"},{\"type\":\"field\",\"outboundTag\":\"block\",\"network\":\"udp\",\"port\":\"443\"},{\"type\":\"field\",\"outboundTag\":\"direct\",\"domain\":[\"geosite:category-ru\",\"geosite:yandex\",\"domain:ru\",\"domain:su\",\"domain:yandex.net\",\"domain:yastatic.net\",\"domain:maps.yandex.net\",\"domain:mc.yandex.ru\",\"domain:vk.com\",\"domain:vk-cdn.net\",\"domain:userapi.com\",\"domain:mail.ru\",\"domain:sberbank.ru\",\"domain:gosuslugi.ru\",\"domain:ozon.ru\",\"domain:wildberries.ru\",\"domain:wbbasket.ru\",\"domain:avito.ru\",\"domain:avito.st\",\"domain:tinkoff.ru\",\"domain:tbank.ru\",\"domain:2gis.com\",\"domain:2gis.ru\",\"domain:alfabank.st\",\"domain:sberbank.com\",\"domain:sber.pro\",\"domain:tinkoff.ai\",\"domain:tinkoff.com\",\"domain:nspk.ru\",\"domain:mirconnect.ru\",\"domain:yandex.net\",\"domain:yastatic.net\",\"domain:yandexcloud.net\",\"domain:yandex-team.ru\",\"domain:ya.ru\",\"domain:yandexmaps.ru\",\"domain:maps.me\",\"domain:tracker.yandex.net\",\"domain:tanker.yandex.ru\",\"domain:tst.mobile.yandex.net\",\"domain:pay.yandex.ru\",\"domain:yoomoney.ru\",\"domain:money.yandex.ru\",\"domain:passport.yandex.ru\",\"domain:appmetrica.yandex.ru\",\"domain:mobile.yandexmaps.ru\"]},{\"type\":\"field\",\"outboundTag\":\"direct\",\"ip\":[\"geoip:ru\",\"geoip:private\"]}]"
        let routingRules = routing.isEmpty ? defaultRules : routing
        return "{\"log\":{\"loglevel\":\"warning\",\"access\":\"\(groupPath)/xray.log\"},\"dns\":{\"servers\":[\"1.1.1.1\",\"8.8.8.8\"]},\"inbounds\":[\(inbound)],\"outbounds\":[{\"tag\":\"vless-out\",\"protocol\":\"vless\",\"settings\":{\"vnext\":[{\"address\":\"\(address)\",\"port\":\(portInt),\"users\":[{\"id\":\"\(uuid)\",\"encryption\":\"none\"\(flowPart)}]}]},\(streamStr)},{\"tag\":\"direct\",\"protocol\":\"freedom\"},{\"tag\":\"block\",\"protocol\":\"blackhole\"}],\"routing\":{\"domainStrategy\":\"IPIfNonMatch\",\"rules\":\(routingRules)}}"
    }
}

enum TunnelError: LocalizedError {
    case missingConfig
    var errorDescription: String? { "Отсутствуют параметры конфигурации" }
}
