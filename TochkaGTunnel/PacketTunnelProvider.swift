// PacketTunnelProvider.swift
// TochkaGTunnel

import NetworkExtension
import Libbox
import Network
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {
    private var commandServer: LibboxCommandServer?
    private lazy var platformInterface = ExtensionPlatformInterface(self)

    private let log = OSLog(subsystem: "com.tochkag.app.tunnel", category: "Tunnel")

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        os_log("START TUNNEL CALLED", log: log, type: .error)

        guard
            let proto = protocolConfiguration as? NETunnelProviderProtocol,
            let cfg   = proto.providerConfiguration,
            let type  = cfg["type"] as? String
        else {
            os_log("MISSING CONFIG", log: log, type: .error)
            completionHandler(TunnelError.missingConfig)
            return
        }

        os_log("TYPE: %{public}@", log: log, type: .error, type)
        if type == "vless" {
            let dbgServer = (cfg["address"] as? String) ?? "?"
            let dbgSni    = (cfg["sni"] as? String) ?? "?"
            let dbgPbk    = (cfg["pbk"] as? String) ?? "?"
            os_log("RECEIVED CONFIG: server=%{public}@ sni=%{public}@ pbk=%{public}@",
                   log: log, type: .error, dbgServer, dbgSni, dbgPbk)
        }

        let config: String
        if type == "vless" {
            guard
                let uuid     = cfg["uuid"]     as? String,
            let address  = cfg["address"]  as? String,
            let port     = cfg["port"]     as? String,
            let network  = cfg["network"]  as? String,
            let security = cfg["security"] as? String,
            let sni      = cfg["sni"]      as? String,
            let path     = cfg["path"]     as? String
        else {
            completionHandler(TunnelError.missingConfig)
            return
        }
        let pbk  = cfg["pbk"]  as? String ?? ""
        let sid  = cfg["sid"]  as? String ?? ""
        let flow = cfg["flow"] as? String ?? ""
        let fp   = cfg["fp"]   as? String ?? "chrome"
            config = makeVlessConfig(uuid: uuid, address: address, port: port,
                                     network: network, security: security,
                                     sni: sni, path: path,
                                     pbk: pbk, sid: sid, flow: flow, fp: fp)
        } else if type == "wireguard" {
            guard
                let privateKey = cfg["privateKey"] as? String,
                let publicKey  = cfg["publicKey"]  as? String,
                let endpoint   = cfg["endpoint"]   as? String,
                let address    = cfg["address"]    as? String,
                let dns        = cfg["dns"]        as? String,
                let allowedIPs = cfg["allowedIPs"] as? String
            else {
                completionHandler(TunnelError.missingConfig)
                return
            }
            let presharedKey = cfg["presharedKey"] as? String ?? ""
            os_log("RECEIVED WG CONFIG: endpoint=%{public}@ addr=%{public}@",
                   log: log, type: .error, endpoint, address)
            config = makeWireguardConfig(privateKey: privateKey,
                                         publicKey: publicKey,
                                         endpoint: endpoint,
                                         address: address,
                                         dns: dns,
                                         allowedIPs: allowedIPs,
                                         presharedKey: presharedKey)
        } else {
            completionHandler(TunnelError.unsupportedProtocol)
            return
        }
        os_log("SINGBOX CONFIG: %{public}@", log: log, type: .error, config)

        // Libbox Setup — ОБЯЗАТЕЛЬНО первым делом
        let appGroup = "group.com.tochkag.vpn"
        let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let setupOpts = LibboxSetupOptions()
        setupOpts.basePath = groupURL.path
        setupOpts.workingPath = groupURL.appendingPathComponent("working").path
        setupOpts.tempPath = groupURL.appendingPathComponent("tmp").path
        setupOpts.logMaxLines = 3000
        setupOpts.debug = false
        setupOpts.crashReportSource = "NetworkExtension"
        setupOpts.oomKillerEnabled = true

        try? FileManager.default.createDirectory(atPath: setupOpts.workingPath,
                                                 withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: setupOpts.tempPath,
                                                 withIntermediateDirectories: true)

        var setupErr: NSError?
        LibboxSetup(setupOpts, &setupErr)
        if let setupErr {
            os_log("LIBBOX SETUP FAILED: %{public}@", log: log, type: .error,
                   setupErr.localizedDescription)
            completionHandler(setupErr)
            return
        }
        os_log("LIBBOX SETUP OK", log: log, type: .error)

        var checkErr: NSError?
        let checkOK = LibboxCheckConfig(config, &checkErr)
        os_log("CONFIG CHECK OK=%{public}@ err=%{public}@", log: log, type: .error,
               checkOK ? "YES" : "NO",
               checkErr?.localizedDescription ?? "nil")
        if !checkOK {
            completionHandler(checkErr ?? TunnelError.singboxInitFailed)
            return
        }

        // Создаём command server (platformInterface — обе роли сразу)
        var err: NSError?
        guard let server = LibboxNewCommandServer(platformInterface, platformInterface, &err) else {
            os_log("SINGBOX INIT FAILED: %{public}@", log: log, type: .error,
                   err?.localizedDescription ?? "unknown")
            completionHandler(err ?? TunnelError.singboxInitFailed)
            return
        }
        self.commandServer = server
        os_log("STARTING SINGBOX", log: log, type: .error)

        // Completion вызываем сразу (iOS убьёт extension через 30сек если нет)
        completionHandler(nil)
        os_log("TUNNEL COMPLETION CALLED (early)", log: log, type: .error)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            do {
                try server.start()
                os_log("SINGBOX COMMAND SERVER STARTED", log: self.log, type: .error)
                try server.startOrReloadService(config, options: LibboxOverrideOptions())
                os_log("SINGBOX STARTED", log: self.log, type: .error)
            } catch {
                os_log("SINGBOX ERROR: %{public}@", log: self.log, type: .error,
                       error.localizedDescription)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        os_log("STOP TUNNEL reason=%d", log: log, type: .error, reason.rawValue)
        if let server = commandServer {
            try? server.closeService()
            server.close()
            commandServer = nil
        }
        platformInterface.reset()
        completionHandler()
    }

    fileprivate func writeMessage(_ message: String) {
        if let commandServer {
            commandServer.writeMessage(2, message: message)
        }
    }

    private func makeVlessConfig(uuid: String, address: String, port: String,
                                  network: String, security: String,
                                  sni: String, path: String,
                                  pbk: String, sid: String,
                                  flow: String, fp: String) -> String {
        let portInt = Int(port) ?? 443
        let transport: String
        switch network {
        case "ws":
            transport = "\"transport\":{\"type\":\"ws\",\"path\":\"\(path)\",\"headers\":{\"Host\":\"\(sni)\"}},"
        case "grpc":
            let s = path.hasPrefix("/") ? String(path.dropFirst()) : path
            transport = "\"transport\":{\"type\":\"grpc\",\"service_name\":\"\(s)\"},"
        case "httpupgrade":
            transport = "\"transport\":{\"type\":\"httpupgrade\",\"path\":\"\(path)\",\"headers\":{\"Host\":\"\(sni)\"}},"
        default:
            transport = ""
        }
        let fpSafe = fp.isEmpty ? "chrome" : fp
        let tls: String
        switch security {
        case "tls":
            tls = "\"tls\":{\"enabled\":true,\"server_name\":\"\(sni)\",\"utls\":{\"enabled\":true,\"fingerprint\":\"\(fpSafe)\"},\"insecure\":false}"
        case "reality":
            tls = "\"tls\":{\"enabled\":true,\"server_name\":\"\(sni)\",\"utls\":{\"enabled\":true,\"fingerprint\":\"\(fpSafe)\"},\"reality\":{\"enabled\":true,\"public_key\":\"\(pbk)\",\"short_id\":\"\(sid)\"}}"
        default:
            tls = "\"tls\":{\"enabled\":false}"
        }
        let flowPart = flow.isEmpty ? "" : "\"flow\":\"\(flow)\","
        return """
        {"log":{"level":"info"},"dns":{"servers":[{"tag":"remote","type":"https","server":"1.1.1.1","detour":"vless-out"},{"tag":"local","type":"udp","server":"223.5.5.5"}],"rules":[{"outbound":"any","server":"local"}]},"inbounds":[{"type":"tun","tag":"tun-in","address":["172.19.0.1/30","fdfe:dcba:9876::1/126"],"mtu":9000,"auto_route":true,"strict_route":false,"stack":"gvisor"}],"outbounds":[{"type":"vless","tag":"vless-out","server":"\(address)","server_port":\(portInt),"uuid":"\(uuid)",\(flowPart)\(transport)\(tls)},{"type":"direct","tag":"direct"}],"route":{"rules":[{"action":"sniff"},{"protocol":"dns","action":"hijack-dns"},{"ip_is_private":true,"outbound":"direct"}],"final":"vless-out","auto_detect_interface":true}}
        """
    }

    private func makeWireguardConfig(privateKey: String, publicKey: String,
                                     endpoint: String, address: String,
                                     dns: String, allowedIPs: String,
                                     presharedKey: String = "") -> String {
        // endpoint: "host:port"
        let epParts = endpoint.split(separator: ":", maxSplits: 1).map(String.init)
        let wgHost = epParts.first ?? endpoint
        let wgPort = Int(epParts.count > 1 ? epParts[1] : "51820") ?? 51820

        // address может быть "10.0.0.2/32, fd00::2/128"
        let addrPart = address.split(separator: ",").first.map(String.init) ?? address
        let cleanAddr = addrPart.trimmingCharacters(in: .whitespaces)
                                .split(separator: "/").first.map(String.init) ?? addrPart

        // dns: "1.1.1.1, 1.0.0.1" -> первый
        let dnsList = dns.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let dnsServer = dnsList.first ?? "1.1.1.1"

        // allowedIPs -> JSON array "[\"0.0.0.0/0\"]"
        let allowedArr = allowedIPs.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let allowedJson = allowedArr.isEmpty
            ? "[\"0.0.0.0/0\"]"
            : "[" + allowedArr.map { "\"\($0)\"" }.joined(separator: ",") + "]"

        return """
        {"log":{"level":"trace"},\
        "dns":{"servers":[\
        {"tag":"remote","type":"udp","server":"\(dnsServer)","detour":"wg-ep"},\
        {"tag":"local","type":"udp","server":"223.5.5.5"}\
        ],"rules":[{"outbound":"any","server":"local"}]},\
        "inbounds":[{"type":"tun","tag":"tun-in","address":["172.19.0.1/30","fdfe:dcba:9876::1/126"],"mtu":1420,"auto_route":true,"strict_route":false,"stack":"gvisor"}],\
        "endpoints":[{\
        "type":"wireguard","tag":"wg-ep","system":false,"mtu":1420,\
        "address":["\(cleanAddr)/32"],\
        "private_key":"\(privateKey)",\
        "peers":[{\
        "address":"\(wgHost)","port":\(wgPort),\
        "public_key":"\(publicKey)",\
        \(presharedKey.isEmpty ? "" : "\"pre_shared_key\":\"\(presharedKey)\",")\
        "allowed_ips":\(allowedJson)\
        }]\
        }],\
        "outbounds":[{"type":"direct","tag":"direct"}],\
        "route":{"rules":[{"action":"sniff"},{"protocol":"dns","action":"hijack-dns"},{"ip_is_private":true,"outbound":"direct"}],"final":"wg-ep","auto_detect_interface":true}}
        """
    }
}

// ─── ExtensionPlatformInterface (based on SagerNet/sing-box-for-apple) ───

class ExtensionPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol, LibboxCommandServerHandlerProtocol {
    private let logObj = OSLog(subsystem: "com.tochkag.app.tunnel", category: "PlatformIface")
    private weak var tunnel: PacketTunnelProvider?
    private var networkSettings: NEPacketTunnelNetworkSettings?
    private var nwMonitor: NWPathMonitor?

    init(_ tunnel: PacketTunnelProvider) {
        self.tunnel = tunnel
    }

    // MARK: - openTun (берёт параметры из LibboxTunOptions, НЕ хардкод)
    func openTun(_ options: (any LibboxTunOptionsProtocol)?,
                 ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options else { throw TunnelError.missingConfig }
        guard let ret0_ else { throw TunnelError.missingConfig }
        guard let tunnel = tunnel else { throw TunnelError.missingConfig }

        os_log("openTun: configuring TUN from libbox options", log: logObj, type: .error)

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

        if options.getAutoRoute() {
            settings.mtu = NSNumber(value: options.getMTU())

            let dnsServer = try options.getDNSServerAddress()
            settings.dnsSettings = NEDNSSettings(servers: [dnsServer.value])

            // IPv4
            var ipv4Addrs: [String] = []
            var ipv4Masks: [String] = []
            if let it = options.getInet4Address() {
                while it.hasNext() {
                    if let p = it.next() {
                        ipv4Addrs.append(p.address())
                        ipv4Masks.append(p.mask())
                    }
                }
            }
            if !ipv4Addrs.isEmpty {
                let ipv4 = NEIPv4Settings(addresses: ipv4Addrs, subnetMasks: ipv4Masks)
                var routes: [NEIPv4Route] = []
                if let it = options.getInet4RouteAddress(), it.hasNext() {
                    while it.hasNext() {
                        if let p = it.next() {
                            routes.append(NEIPv4Route(destinationAddress: p.address(), subnetMask: p.mask()))
                        }
                    }
                } else {
                    routes.append(NEIPv4Route.default())
                }
                ipv4.includedRoutes = routes
                settings.ipv4Settings = ipv4
            }

            // IPv6
            var ipv6Addrs: [String] = []
            var ipv6Prefixes: [NSNumber] = []
            if let it = options.getInet6Address() {
                while it.hasNext() {
                    if let p = it.next() {
                        ipv6Addrs.append(p.address())
                        ipv6Prefixes.append(NSNumber(value: p.prefix()))
                    }
                }
            }
            if !ipv6Addrs.isEmpty {
                let ipv6 = NEIPv6Settings(addresses: ipv6Addrs, networkPrefixLengths: ipv6Prefixes)
                var routes: [NEIPv6Route] = []
                if let it = options.getInet6RouteAddress(), it.hasNext() {
                    while it.hasNext() {
                        if let p = it.next() {
                            routes.append(NEIPv6Route(destinationAddress: p.address(),
                                                      networkPrefixLength: NSNumber(value: p.prefix())))
                        }
                    }
                } else {
                    routes.append(NEIPv6Route.default())
                }
                ipv6.includedRoutes = routes
                settings.ipv6Settings = ipv6
            }
        }

        networkSettings = settings

        let sem = DispatchSemaphore(value: 0)
        var setErr: Error?
        tunnel.setTunnelNetworkSettings(settings) { err in
            setErr = err
            sem.signal()
        }
        sem.wait()
        if let e = setErr { throw e }

        // Сначала пробуем получить FD через packetFlow (iOS 17+)
        if let tunFd = tunnel.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32, tunFd >= 0 {
            ret0_.pointee = tunFd
            os_log("openTun: got FD from packetFlow = %d", log: logObj, type: .error, tunFd)
            return
        }

        // Fallback через Libbox
        let fd = LibboxGetTunnelFileDescriptor()
        if fd >= 0 {
            ret0_.pointee = fd
            os_log("openTun: got FD from LibboxGetTunnelFileDescriptor = %d", log: logObj, type: .error, fd)
            return
        }

        os_log("openTun: FAILED to get FD", log: logObj, type: .error)
        throw TunnelError.tunFailed
    }

    // MARK: - Interface monitoring (НАСТОЯЩИЙ NWPathMonitor)

    func startDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        guard let listener else { return }
        os_log("startDefaultInterfaceMonitor", log: logObj, type: .error)
        let monitor = NWPathMonitor()
        nwMonitor = monitor
        let sem = DispatchSemaphore(value: 0)
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onPathUpdate(listener, path)
            sem.signal()
            monitor.pathUpdateHandler = { [weak self] p in
                self?.onPathUpdate(listener, p)
            }
        }
        monitor.start(queue: DispatchQueue.global())
        sem.wait()
    }

    private func onPathUpdate(_ listener: any LibboxInterfaceUpdateListenerProtocol, _ path: Network.NWPath) {
        guard path.status != .unsatisfied, let iface = path.availableInterfaces.first else {
            listener.updateDefaultInterface("", interfaceIndex: -1, isExpensive: false, isConstrained: false)
            return
        }
        os_log("path update: iface=%{public}@ idx=%d expensive=%{public}@",
               log: logObj, type: .error,
               iface.name, iface.index,
               path.isExpensive ? "yes" : "no")
        listener.updateDefaultInterface(iface.name, interfaceIndex: Int32(iface.index),
                                        isExpensive: path.isExpensive,
                                        isConstrained: path.isConstrained)
    }

    func closeDefaultInterfaceMonitor(_: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        nwMonitor?.cancel()
        nwMonitor = nil
    }

    // MARK: - getInterfaces (возвращаем реальные)

    func getInterfaces() throws -> any LibboxNetworkInterfaceIteratorProtocol {
        guard let nwMonitor else {
            return NetworkInterfaceArray([])
        }
        let path = nwMonitor.currentPath
        if path.status == .unsatisfied {
            return NetworkInterfaceArray([])
        }
        var result: [LibboxNetworkInterface] = []
        for it in path.availableInterfaces {
            let ni = LibboxNetworkInterface()
            ni.name = it.name
            ni.index = Int32(it.index)
            switch it.type {
            case .wifi:          ni.type = LibboxInterfaceTypeWIFI
            case .cellular:      ni.type = LibboxInterfaceTypeCellular
            case .wiredEthernet: ni.type = LibboxInterfaceTypeEthernet
            default:             ni.type = LibboxInterfaceTypeOther
            }
            result.append(ni)
        }
        return NetworkInterfaceArray(result)
    }

    class NetworkInterfaceArray: NSObject, LibboxNetworkInterfaceIteratorProtocol {
        private var iter: IndexingIterator<[LibboxNetworkInterface]>
        private var nextValue: LibboxNetworkInterface?
        init(_ arr: [LibboxNetworkInterface]) {
            self.iter = arr.makeIterator()
        }
        func hasNext() -> Bool {
            nextValue = iter.next()
            return nextValue != nil
        }
        func next() -> LibboxNetworkInterface? { nextValue }
    }

    // MARK: - PlatformInterface прочие методы
    func autoDetectControl(_ fd: Int32) throws {}
    func usePlatformAutoDetectControl() -> Bool { false }   // ← false, не true!
    func useProcFS() -> Bool { false }
    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }
    func clearDNSCache() {}
    func registerMyInterface(_ name: String?) {}
    func localDNSTransport() -> (any LibboxLocalDNSTransportProtocol)? { nil }
    func readWIFIState() -> LibboxWIFIState? { nil }
    func systemCertificates() -> (any LibboxStringIteratorProtocol)? { nil }
    func send(_ notification: LibboxNotification?) throws {}
    func startNeighborMonitor(_: (any LibboxNeighborUpdateListenerProtocol)?) throws {}
    func closeNeighborMonitor(_: (any LibboxNeighborUpdateListenerProtocol)?) throws {}

    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32,
                             destinationAddress: String?, destinationPort: Int32) throws -> LibboxConnectionOwner {
        throw TunnelError.missingConfig
    }

    // MARK: - CommandServerHandler (пишет логи sing-box через os_log)
    func writeLog(_ message: String?) {
        guard let message else { return }
        os_log("SINGBOX: %{public}@", log: logObj, type: .error, message)
    }
    func writeDebugMessage(_ message: String?) {
        guard let message else { return }
        os_log("SINGBOX-DBG: %{public}@", log: logObj, type: .error, message)
    }
    func serviceStop() throws {}
    func serviceReload() throws {}
    func getSystemProxyStatus() throws -> LibboxSystemProxyStatus { LibboxSystemProxyStatus() }
    func setSystemProxyEnabled(_ enabled: Bool) throws {}
    func triggerNativeCrash() throws {}

    func reset() {
        networkSettings = nil
        nwMonitor?.cancel()
        nwMonitor = nil
    }
}

// ─── Ошибки ───

enum TunnelError: LocalizedError {
    case missingConfig, singboxInitFailed, tunFailed, unsupportedProtocol
    var errorDescription: String? {
        switch self {
        case .missingConfig:       return "Отсутствуют параметры конфигурации"
        case .singboxInitFailed:   return "Не удалось инициализировать sing-box"
        case .tunFailed:           return "Не удалось открыть TUN интерфейс"
        case .unsupportedProtocol: return "Неподдерживаемый протокол"
        }
    }
}
