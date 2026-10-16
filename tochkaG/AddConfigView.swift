// AddConfigView.swift
// TochkaG

import SwiftUI
import UIKit
import UniformTypeIdentifiers

// ── Выбор протокола ───────────────────────────────────────

struct AddConfigView: View {
    @EnvironmentObject var store: ConfigStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AuroraBackground()
                List {
                if !store.hasConfig(ofType: .wireguard) {
                    NavigationLink(destination: AddWireGuardView().environmentObject(store)) {
                        Label("WireGuard", systemImage: "network")
                            .foregroundStyle(Brand.text)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    HStack {
                        Label("WireGuard", systemImage: "network")
                            .foregroundStyle(Brand.faint)
                        Spacer()
                        Text("Уже добавлен").foregroundStyle(Brand.muted).font(.caption)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if !store.hasConfig(ofType: .vless) {
                    NavigationLink(destination: AddVlessView().environmentObject(store)) {
                        Label("VLESS", systemImage: "bolt.shield")
                            .foregroundStyle(Brand.text)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    HStack {
                        Label("VLESS", systemImage: "bolt.shield")
                            .foregroundStyle(Brand.faint)
                        Spacer()
                        Text("Уже добавлен").foregroundStyle(Brand.muted).font(.caption)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                if store.hasConfig(ofType: .wireguard) || store.hasConfig(ofType: .vless) {
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.orange)
                            Text("Чтобы установить новый конфиг, удалите старый в основном меню, смахнув его вправо")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Добавить конфиг")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Brand.cyan)
                }
            }
            #if os(iOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
        }
        .preferredColorScheme(.dark)
    }
}

// ── Add WireGuard ─────────────────────────────────────────

struct AddWireGuardView: View {
    @EnvironmentObject var store: ConfigStore
    @Environment(\.dismiss) var dismiss

    @State private var name           = ""
    @State private var privateKey     = ""
    @State private var address        = ""
    @State private var dns            = "1.1.1.1"
    @State private var publicKey      = ""
    @State private var endpoint       = ""
    @State private var allowedIPs     = "0.0.0.0/0"
    @State private var presharedKey = ""
    @State private var awgParams: [String: String]? = nil
    @State private var showPaste      = false
    @State private var showFilePicker = false
    @State private var fileLoaded     = false
    @State private var errorMessage   = ""

    var canSave: Bool {
        !name.isEmpty && !privateKey.isEmpty && !publicKey.isEmpty && !endpoint.isEmpty
    }

    var body: some View {
        Form {
            Section("Название") {
                TextField("Мой WireGuard", text: $name)
            }

            Section("Загрузить конфиг") {
                Button("Выбрать .conf файл") { showFilePicker = true }
                // Импорт только из файла. Буфер обмена и ручной ввод скрыты.
            }

            if fileLoaded {
                Section("Данные конфига") {
                    row("Endpoint", endpoint)
                    row("Обфускация", (awgParams?["Jc"] != nil) ? "AmneziaWG" : "нет")
                    row("Address", address)
                    row("DNS", dns)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage).foregroundColor(.red).font(.caption)
                    }
                }

                Section {
                    Button(action: save) {
                        HStack {
                            Spacer()
                            Text("Сохранить конфиг")
                                .fontWeight(.semibold)
                                .foregroundColor(canSave ? .white : .secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(canSave ? Color.accentColor : Color.secondary.opacity(0.2))
                    .disabled(!canSave)
                }
            }
        }
        .navigationTitle("WireGuard")
        .sheet(isPresented: $showPaste) {
            PasteConfView(onParse: { parsed in
                applyParsed(parsed)
                if name.isEmpty { name = "WireGuard" }
                fileLoaded = true
            })
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "conf") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            guard let url = try? result.get().first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            let parsed = PasteConfView.parse(text)
            applyParsed(parsed)
            let fileName = url.deletingPathExtension().lastPathComponent
            name = fileName.isEmpty ? "WireGuard" : fileName
            fileLoaded = true
        }
    }

    private func applyParsed(_ parsed: WireGuardConfig) {
        awgParams = parsed.awgParams
        privateKey = parsed.privateKey
        address    = parsed.address
        dns        = parsed.dns
        publicKey  = parsed.publicKey
        endpoint   = parsed.endpoint
        allowedIPs = parsed.allowedIPs
        presharedKey = parsed.presharedKey
        fileLoaded = true
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value.isEmpty ? "—" : value)
                .font(.caption)
                .foregroundColor(value.isEmpty ? .secondary : .primary)
        }
    }

    func save() {
        guard canSave else {
            errorMessage = "Не хватает данных. Проверьте конфиг."
            return
        }
        let cfg = WireGuardConfig(
            name: name, privateKey: privateKey, address: address,
            dns: dns, publicKey: publicKey, endpoint: endpoint, allowedIPs: allowedIPs,
            presharedKey: presharedKey
        )
        var cfgAWG = cfg
        cfgAWG.awgParams = awgParams
        store.add(.wireguard(cfgAWG))
        dismiss()
    }
}

// ── Add VLESS ─────────────────────────────────────────────

struct AddVlessView: View {
    @EnvironmentObject var store: ConfigStore
    @Environment(\.dismiss) var dismiss

    @State private var vlessURL   = ""
    @State private var subURL     = ""
    @State private var uuid       = ""
    @State private var address    = ""
    @State private var port       = "443"
    @State private var path       = "/"
    @State private var network    = "ws"
    @State private var security   = "tls"
    @State private var sni        = ""
    @State private var mode       = 1   // только подписка (0=URL, 2=Manual отключены)
    @State private var urlError   = ""
    @State private var isLoading  = false
    @State private var subConfigs: [VlessConfig] = []
    @State private var routing     = ""

    let networks   = ["ws", "tcp", "grpc", "httpupgrade"]
    let securities = ["tls", "none", "reality"]

    var body: some View {
        Form {
            // Добавление только по подписке (mode = 1).
            // Ветки VLESS URL (mode 0) и Вручную (mode 2) отключены,
            // код оставлен на случай возврата.

            // ── VLESS URL ──────────────────────────────────
            if false, mode == 0 {
                Section("Вставьте VLESS URL") {
                    TextField("vless://uuid@host:port?...", text: $vlessURL)
                        .textInputAutocapitalization(.never)
                    if !urlError.isEmpty {
                        Text(urlError).foregroundColor(.red).font(.caption)
                    }
                }

                Section {
                    Button("Добавить") { parseAndSave() }
                        .disabled(vlessURL.isEmpty)
                }
            }

            // ── Подписка ───────────────────────────────────
            if mode == 1 {
                Section("URL подписки") {
                    TextField("https://...", text: $subURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    if !urlError.isEmpty {
                        Text(urlError).foregroundColor(.red).font(.caption)
                    }
                }
                Section {
                    Button {
                        fetchSubscription()
                    } label: {
                        HStack {
                            Text("Загрузить подписку")
                            Spacer()
                            if isLoading { ProgressView() }
                        }
                    }
                    .disabled(subURL.isEmpty || isLoading)
                }
                if !subConfigs.isEmpty {
                    Section {
                        Button {
                            store.addSubscription(subConfigs, url: subURL)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Добавить все (\(subConfigs.count))")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    Section("Найдено: \(subConfigs.count)") {
                        ForEach(subConfigs.indices, id: \.self) { i in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(subConfigs[i].name).font(.headline)
                                    Text("\(subConfigs[i].address):\(subConfigs[i].port)")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Добавить") {
                                    store.addSubscription([subConfigs[i]], url: subURL)
                                    dismiss()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                            }
                        }
                    }
                }
            }

            // ── Вручную ────────────────────────────────────
            if false, mode == 2 {
                Section("Сервер") {
                    TextField("UUID", text: $uuid).textInputAutocapitalization(.never)
                    TextField("Адрес", text: $address).textInputAutocapitalization(.never)
                    TextField("Порт", text: $port).keyboardType(.numberPad)
                }
                Section("Соединение") {
                    Picker("Network", selection: $network) {
                        ForEach(networks, id: \.self) { Text($0) }
                    }
                    Picker("Security", selection: $security) {
                        ForEach(securities, id: \.self) { Text($0) }
                    }
                    TextField("SNI", text: $sni).textInputAutocapitalization(.never)
                    TextField("Path", text: $path).textInputAutocapitalization(.never)
                }

                if !urlError.isEmpty {
                    Section { Text(urlError).foregroundColor(.red).font(.caption) }
                }
                Section {
                    Button("Сохранить") { saveManual() }
                        .disabled(uuid.isEmpty || address.isEmpty)
                }
            }
        }
        .navigationTitle("VLESS")
        .onAppear {
            if let sub = store.pendingSubscriptionURL {
                mode   = 1
                subURL = sub
                store.pendingSubscriptionURL = nil
            }
            if let vless = store.pendingVlessURL {
                mode     = 0
                vlessURL = vless
                store.pendingVlessURL = nil
            }
        }
    }

    // ── Fetch subscription ────────────────────────────────

    func fetchSubscription() {
        guard let url = URL(string: subURL.trimmingCharacters(in: .whitespaces)) else {
            urlError = "Неверный URL подписки"; return
        }
        isLoading  = true
        urlError   = ""
        subConfigs = []

        var req = URLRequest(url: url)
        req.timeoutInterval = 15

        let device     = UIDevice.current
        let hwid       = device.identifierForVendor?.uuidString.lowercased() ?? "unknown"
        let osVersion  = device.systemVersion
        let model      = device.model
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let locale     = Locale.current.language.languageCode?.identifier ?? "en"
        // User-Agent в стиле Happ — Remnawave проверяет первое слово
        let userAgent  = "TochkaG/\(appVersion) (iOS \(osVersion); \(model))"

        req.setValue(hwid,       forHTTPHeaderField: "x-hwid")
        req.setValue("iOS",      forHTTPHeaderField: "x-device-os")
        req.setValue(osVersion,  forHTTPHeaderField: "x-ver-os")
        req.setValue(model,      forHTTPHeaderField: "x-device-model")
        req.setValue(locale,     forHTTPHeaderField: "x-device-locale")
        req.setValue(userAgent,  forHTTPHeaderField: "User-Agent")

        #if DEBUG
        print("[SUB] x-hwid=\(hwid)")
        #endif
        print("[SUB] user-agent=\(userAgent)")

        URLSession.shared.dataTask(with: req) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error = error {
                    urlError = "Ошибка: \(error.localizedDescription)"; return
                }

                if let http = response as? HTTPURLResponse {
                    print("[SUB] HTTP \(http.statusCode)")
                    // Стандартные Remnawave-заголовки (с v2.7.5)
                    let maxReached = http.value(forHTTPHeaderField: "x-hwid-max-devices-reached") == "true"
                                   || http.value(forHTTPHeaderField: "x-hwid-limit") == "true"
                    let notSupported = http.value(forHTTPHeaderField: "x-hwid-not-supported") == "true"

                    if maxReached {
                        urlError = "Превышен лимит устройств на этой подписке. Обратитесь к администратору.\n\nВаш HWID: \(hwid)"
                        return
                    }
                    if notSupported {
                        urlError = "Сервер требует HWID, но не распознаёт наше приложение. HWID: \(hwid)"
                        return
                    }
                    if http.statusCode == 404 {
                        urlError = "Подписка не найдена или превышен лимит. HWID: \(hwid)"
                        return
                    }
                    // announce — информационная плашка панели (Remnawave шлёт её всегда),
                    // не признак ошибки. Логируем и продолжаем парсинг конфигов.
                    if let announce = http.value(forHTTPHeaderField: "x-hwid-announce")
                        ?? http.value(forHTTPHeaderField: "announce") {
                        print("[SUB] announce: \(self.decodePanelMessage(announce))")
                    }
                }

                guard let data = data,
                      let raw  = String(data: data, encoding: .utf8) else {
                    urlError = "Не удалось прочитать ответ"; return
                }

                print("[SUB] raw first 200: \(String(raw.prefix(200)))")
                let decoded = decodeBase64IfNeeded(raw)
                print("[SUB] decoded first 200: \(String(decoded.prefix(200)))")

                // Делим ТОЛЬКО по переводам строк: в #fragment бывают пробелы
                // (например "#\u{1F1F3}\u{1F1F1} Netherlands").
                let tokens = decoded
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                var vlessLines = tokens.filter { $0.hasPrefix("vless://") }

            // Fallback: если базовая стратегия ничего не нашла, пробуем парсить JSON Xray-config
            if vlessLines.isEmpty {
                if let extracted = extractVlessFromXrayJSON(raw) {
                    print("[SUB] JSON parsed, extracted \(extracted.count) vless lines")
                    vlessLines = extracted
                }
            }

                let real = vlessLines.filter { line in
                    !line.contains("0.0.0.0:1") &&
                    !line.contains("0.0.0.0:0") &&
                    !line.contains("127.0.0.1:") &&
                    !line.contains("@localhost") &&
                    !line.contains("example.com") &&
                    !line.contains("00000000-0000-0000-0000-000000000000")
                }

                if real.isEmpty {
                    if !vlessLines.isEmpty {
                        // Извлекаем сообщение сервера из #fragment заглушки
                        var serverMsg = ""
                        if let stub = vlessLines.first,
                           let fragRange = stub.range(of: "#"),
                           let decoded = String(stub[fragRange.upperBound...])
                                            .removingPercentEncoding {
                            serverMsg = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        let lower = serverMsg.lowercased()

                        if lower.contains("limit") && lower.contains("device") {
                            urlError = "Превышен лимит устройств на этой подписке. Обратитесь к администратору.\n\nВаш HWID: \(hwid)"
                        } else if lower.contains("no hosts") || lower.contains("no servers") {
                            urlError = "На этой подписке нет активных серверов. Обратитесь к администратору."
                        } else if lower.contains("expired") || lower.contains("expire") {
                            urlError = "Срок действия подписки истёк."
                        } else if lower.contains("disabled") || lower.contains("inactive") {
                            urlError = "Подписка отключена."
                        } else if lower.contains("not supported") || lower.contains("not_supported") {
                            urlError = "Этот VPN-сервис пока не поддерживает наше приложение. Попробуйте другую подписку или добавьте конфиг вручную."
                        } else if lower.contains("remnawave") || lower.contains("→") || lower.contains("->") {
                            urlError = "Подписка не активна или у неё нет привязанных серверов."
                        } else if !serverMsg.isEmpty {
                            urlError = "Ответ сервера: \(serverMsg)\n\nHWID: \(hwid)"
                        } else {
                            urlError = "Не удалось загрузить конфиги. HWID: \(hwid)"
                        }
                    } else {
                        urlError = "В подписке не найдено VLESS-конфигов. Проверьте ссылку или обратитесь в поддержку."
                    }
                    return
                }

                subConfigs = real.compactMap { line -> VlessConfig? in
                    guard let p = parseVlessURL(line) else { return nil }
                    return VlessConfig(
                        name:     p["name"] ?? p["sni"] ?? p["address"] ?? "VLESS",
                        uuid:     p["uuid"] ?? "",
                        address:  p["address"] ?? "",
                        port:     p["port"] ?? "443",
                        path:     p["path"] ?? "/",
                        network:  p["network"] ?? "ws",
                        security: p["security"] ?? "tls",
                        sni:      p["sni"] ?? p["address"] ?? "",
                        publicKey:   p["pbk"] ?? "",
                        shortId:     p["sid"] ?? "",
                        flow:        p["flow"] ?? "",
                        fingerprint: p["fp"] ?? "chrome"
                    )
                }
                if subConfigs.isEmpty {
                    urlError = "Не удалось распарсить ни один VLESS конфиг"
                } else {
                    // Сохраняем URL подписки для авто-обновления при следующем запуске
                    store.saveSubscriptionURL(subURL)
                }
            }
        }.resume()
    }


    /// Извлекает vless:// URI из JSON Xray/sing-box конфига.
    /// Поддерживает оба формата: массив конфигов и одиночный outbounds.
    func extractVlessFromXrayJSON(_ raw: String) -> [String]? {
        guard let data = raw.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        // Собираем массив outbounds из любого из форматов
        var outbounds: [[String: Any]] = []

        if let arr = parsed as? [[String: Any]] {
            // [{ outbounds: [...] }, { outbounds: [...] }]
            for cfg in arr {
                if let obs = cfg["outbounds"] as? [[String: Any]] {
                    outbounds.append(contentsOf: obs)
                }
            }
        } else if let obj = parsed as? [String: Any],
                  let obs = obj["outbounds"] as? [[String: Any]] {
            outbounds.append(contentsOf: obs)
        }

        if outbounds.isEmpty { return nil }

        var result: [String] = []
        for out in outbounds {
            // Xray: {"protocol":"vless","settings":{"vnext":[{"address":...,"port":...,"users":[{"id":...,"flow":...}]}]}, "streamSettings":{...}}
            guard let proto = out["protocol"] as? String, proto == "vless",
                  let settings = out["settings"] as? [String: Any],
                  let vnext = settings["vnext"] as? [[String: Any]],
                  let first = vnext.first,
                  let address = first["address"] as? String,
                  let port = first["port"] as? Int,
                  let users = first["users"] as? [[String: Any]],
                  let user = users.first,
                  let uuid = user["id"] as? String else { continue }

            let flow = user["flow"] as? String ?? ""
            let encryption = user["encryption"] as? String ?? "none"

            // streamSettings → type, security, sni, pbk, sid, fp, path
            let stream = out["streamSettings"] as? [String: Any] ?? [:]
            let network = stream["network"] as? String ?? "tcp"
            let security = stream["security"] as? String ?? "none"

            var params: [String: String] = [
                "encryption": encryption,
                "type": network,
                "security": security
            ]
            if !flow.isEmpty { params["flow"] = flow }

            // Reality settings
            if let reality = stream["realitySettings"] as? [String: Any] {
                if let sni = reality["serverName"] as? String { params["sni"] = sni }
                if let pbk = reality["publicKey"] as? String { params["pbk"] = pbk }
                if let sid = reality["shortId"] as? String { params["sid"] = sid }
                if let fp = reality["fingerprint"] as? String { params["fp"] = fp }
            }
            // TLS settings
            if let tls = stream["tlsSettings"] as? [String: Any] {
                if let sni = tls["serverName"] as? String { params["sni"] = sni }
                if let fp = tls["fingerprint"] as? String { params["fp"] = fp }
            }
            // WS settings
            if let ws = stream["wsSettings"] as? [String: Any] {
                if let path = ws["path"] as? String { params["path"] = path }
                if let headers = ws["headers"] as? [String: String], let host = headers["Host"] {
                    params["host"] = host
                }
            }

            let query = params.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $1)" }
                              .joined(separator: "&")
            let tag = (out["tag"] as? String) ?? "VLESS"
            let fragment = tag.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? tag

            let url = "vless://\(uuid)@\(address):\(port)?\(query)#\(fragment)"
            result.append(url)
        }
        return result.isEmpty ? nil : result
    }

    /// Панель отдаёт часть заголовков как "base64:...." — раскрываем в читаемый текст.
    func decodePanelMessage(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("base64:") else { return t }
        let body = String(t.dropFirst("base64:".count))
        let padded = body + String(repeating: "=", count: (4 - body.count % 4) % 4)
        if let d = Data(base64Encoded: padded),
           let s = String(data: d, encoding: .utf8) {
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return t
    }

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

    func parseVlessURL(_ raw: String) -> [String: String]? {
        guard let u = URL(string: raw), u.scheme == "vless" else { return nil }
        var r: [String: String] = [:]
        r["uuid"]    = u.user ?? ""
        r["address"] = u.host ?? ""
        r["port"]    = String(u.port ?? 443)
        URLComponents(url: u, resolvingAgainstBaseURL: false)?
            .queryItems?.forEach { if let v = $0.value { r[$0.name] = v } }
        r["network"]  = r["type"] ?? "ws"
        r["security"] = r["security"] ?? "tls"
        r["sni"]      = r["sni"] ?? u.host ?? ""
        r["path"]     = r["path"] ?? "/"
        if let frag = u.fragment, !frag.isEmpty {
            r["name"] = frag.removingPercentEncoding ?? frag
        }
        return r
    }

    func parseAndSave() {
        urlError = ""
        guard let p = parseVlessURL(vlessURL.trimmingCharacters(in: .whitespaces)) else {
            urlError = "Неверный формат VLESS URL"; return
        }
        store.add(.vless(VlessConfig(
            name:     p["name"] ?? p["sni"] ?? p["address"] ?? "VLESS",
            uuid:     p["uuid"] ?? "",
            address:  p["address"] ?? "",
            port:     p["port"] ?? "443",
            path:     p["path"] ?? "/",
            network:  p["network"] ?? "ws",
            security: p["security"] ?? "tls",
            sni:      p["sni"] ?? p["address"] ?? "",
            publicKey:   p["pbk"] ?? "",
            shortId:     p["sid"] ?? "",
            flow:        p["flow"] ?? "",
            fingerprint: p["fp"] ?? "chrome",
            routing: routing
        )))
        dismiss()
    }

    func saveManual() {
        urlError = ""
        if uuid.isEmpty || address.isEmpty { urlError = "UUID и адрес обязательны"; return }
        store.add(.vless(VlessConfig(
            name: sni.isEmpty ? address : sni,
            uuid: uuid, address: address, port: port,
            path: path, network: network, security: security, sni: sni,
            routing: routing
        )))
        dismiss()
    }
}

// ── Paste .conf ───────────────────────────────────────────

struct PasteConfView: View {
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    let onParse: (WireGuardConfig) -> Void

    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: $text)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                Button("Применить") {
                    onParse(PasteConfView.parse(text))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .navigationTitle("Вставьте .conf")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    static func parse(_ t: String) -> WireGuardConfig {
        var cfg = parseBase(t)
        var extra = cfg.awgParams ?? [:]
        for line in t.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[1].isEmpty else { continue }
            switch parts[0].lowercased() {
            case "mtu":                 extra["MTU"] = parts[1]
            case "persistentkeepalive": extra["PersistentKeepalive"] = parts[1]
            default: break
            }
        }
        if !extra.isEmpty { cfg.awgParams = extra }
        return cfg
    }

    static func parseBase(_ t: String) -> WireGuardConfig {
        func get(_ key: String) -> String {
            let pattern = "\(key)\\s*=\\s*(.+)"
            guard let r = t.range(of: pattern, options: .regularExpression) else { return "" }
            return String(t[r])
                .components(separatedBy: "=").dropFirst().joined(separator: "=")
                .trimmingCharacters(in: .whitespaces)
        }
        var c = WireGuardConfig(
            name: "WireGuard",
            privateKey: get("PrivateKey"), address: get("Address"), dns: get("DNS"),
            publicKey: get("PublicKey"), endpoint: get("Endpoint"), allowedIPs: get("AllowedIPs"),
            presharedKey: get("PresharedKey")
        )
        // AmneziaWG: читаем построчно и строго по имени ключа,
        // чтобы не зацепить совпадения внутри base64-ключей.
        let awgKeys: Set<String> = ["Jc","Jmin","Jmax","S1","S2","S3","S4",
                                    "H1","H2","H3","H4","I1","I2","I3","I4","I5",
                                    "J1","J2","J3","Itime"]
        var awg: [String: String] = [:]
        for line in t.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, awgKeys.contains(parts[0]), !parts[1].isEmpty else { continue }
            awg[parts[0]] = parts[1]
        }
        c.awgParams = awg.isEmpty ? nil : awg
        return c
    }
}

// ── URL helpers ───────────────────────────────────────────

extension URL {
    var queryParams: [String: String] {
        var result: [String: String] = [:]
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?.forEach { result[$0.name] = $0.value }
        return result
    }
}

