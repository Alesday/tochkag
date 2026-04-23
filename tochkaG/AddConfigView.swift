// AddConfigView.swift
// TochkaG

import SwiftUI
import UniformTypeIdentifiers

// ── Выбор протокола ───────────────────────────────────────

struct AddConfigView: View {
    @EnvironmentObject var store: ConfigStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                if !store.hasConfig(ofType: .wireguard) {
                    NavigationLink(destination: AddWireGuardView().environmentObject(store)) {
                        Label("WireGuard", systemImage: "network")
                    }
                } else {
                    HStack {
                        Label("WireGuard", systemImage: "network")
                        Spacer()
                        Text("Уже добавлен").foregroundColor(.secondary).font(.caption)
                    }
                }

                if !store.hasConfig(ofType: .vless) {
                    NavigationLink(destination: AddVlessView().environmentObject(store)) {
                        Label("VLESS", systemImage: "bolt.shield")
                    }
                } else {
                    HStack {
                        Label("VLESS", systemImage: "bolt.shield")
                        Spacer()
                        Text("Уже добавлен").foregroundColor(.secondary).font(.caption)
                    }
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
            .navigationTitle("Добавить конфиг")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
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
                Button("Вставить из буфера обмена") {
                    if let text = UIPasteboard.general.string, !text.isEmpty {
                        applyParsed(PasteConfView.parse(text))
                        if name.isEmpty { name = "WireGuard" }
                    }
                }
                Button("Вставить текст вручную") { showPaste = true }
            }

            if fileLoaded {
                Section("Данные конфига") {
                    row("Endpoint", endpoint)
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
        store.add(.wireguard(cfg))
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
    @State private var mode       = 0   // 0=URL, 1=Subscription, 2=Manual
    @State private var urlError   = ""
    @State private var isLoading  = false
    @State private var subConfigs: [VlessConfig] = []

    let networks   = ["ws", "tcp", "grpc", "httpupgrade"]
    let securities = ["tls", "none", "reality"]

    var body: some View {
        Form {
            Picker("Способ", selection: $mode) {
                Text("VLESS URL").tag(0)
                Text("Подписка").tag(1)
                Text("Вручную").tag(2)
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            // ── VLESS URL ──────────────────────────────────
            if mode == 0 {
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
                    TextField("https://sub.tochkag.online/...", text: $subURL)
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
                            Text("Загрузить конфиги")
                            Spacer()
                            if isLoading { ProgressView() }
                        }
                    }
                    .disabled(subURL.isEmpty || isLoading)
                }
                if !subConfigs.isEmpty {
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
                                    store.add(.vless(subConfigs[i]))
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
            if mode == 2 {
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

        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                isLoading = false
                if let error = error { urlError = "Ошибка: \(error.localizedDescription)"; return }
                guard let data = data,
                      let raw  = String(data: data, encoding: .utf8) else {
                    urlError = "Не удалось прочитать ответ"; return
                }
                let decoded = decodeBase64IfNeeded(raw)
                let lines   = decoded
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("vless://") }

                if lines.isEmpty { urlError = "Конфиги не найдены"; return }

                subConfigs = lines.compactMap { line -> VlessConfig? in
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
                if subConfigs.isEmpty { urlError = "Конфиги не найдены в ответе сервера" }
            }
        }.resume()
    }

    func decodeBase64IfNeeded(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("vless://") { return t }
        let padded = t + String(repeating: "=", count: (4 - t.count % 4) % 4)
        if let data = Data(base64Encoded: padded),
           let decoded = String(data: data, encoding: .utf8) { return decoded }
        return t
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
            fingerprint: p["fp"] ?? "chrome"
        )))
        dismiss()
    }

    func saveManual() {
        urlError = ""
        if uuid.isEmpty || address.isEmpty { urlError = "UUID и адрес обязательны"; return }
        store.add(.vless(VlessConfig(
            name: sni.isEmpty ? address : sni,
            uuid: uuid, address: address, port: port,
            path: path, network: network, security: security, sni: sni
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
        func get(_ key: String) -> String {
            let pattern = "\(key)\\s*=\\s*(.+)"
            guard let r = t.range(of: pattern, options: .regularExpression) else { return "" }
            return String(t[r])
                .components(separatedBy: "=").dropFirst().joined(separator: "=")
                .trimmingCharacters(in: .whitespaces)
        }
        return WireGuardConfig(
            name: "WireGuard",
            privateKey: get("PrivateKey"), address: get("Address"), dns: get("DNS"),
            publicKey: get("PublicKey"), endpoint: get("Endpoint"), allowedIPs: get("AllowedIPs"),
            presharedKey: get("PresharedKey")
        )
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

