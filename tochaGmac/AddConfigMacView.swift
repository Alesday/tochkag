import UniformTypeIdentifiers
import SwiftUI

struct AddConfigMacView: View {
    @ObservedObject var store: MacConfigStore
    let mode: AddMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        switch mode {
        case .url:          AddByURLView(store: store, dismiss: dismiss)
        case .subscription: AddSubscriptionView(store: store, dismiss: dismiss)
        case .manualVless:  AddVlessManualView(store: store, dismiss: dismiss)
        case .manualWG:     AddWireGuardManualView(store: store, dismiss: dismiss)
        case .importFile:   ImportFileView(store: store, dismiss: dismiss)
        }
    }
}

// ── Добавить по URL ────────────────────────────────────────────────────────
struct AddByURLView: View {
    @ObservedObject var store: MacConfigStore
    let dismiss: DismissAction
    @State private var urlText = ""
    @State private var error = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Добавить по URL").font(.headline)
            Text("Вставьте vless:// ссылку").foregroundStyle(.secondary).font(.callout)
            TextEditor(text: $urlText)
                .font(.system(.body, design: .monospaced))
                .frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            if !error.isEmpty {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Отмена", role: .cancel) { dismiss() }
                Spacer()
                Button("Добавить") {
                    let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let config = parseVlessURL(trimmed) {
                        store.add(config); dismiss()
                    } else {
                        error = "Неверный формат URL"
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

// ── Добавить подписку ──────────────────────────────────────────────────────
struct AddSubscriptionView: View {
    @ObservedObject var store: MacConfigStore
    let dismiss: DismissAction
    @State private var urlText = ""
    @State private var isLoading = false
    @State private var error = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Добавить подписку").font(.headline)
            Text("Вставьте URL подписки").foregroundStyle(.secondary).font(.callout)
            TextField("https://...", text: $urlText)
                .textFieldStyle(.roundedBorder)
            if !error.isEmpty {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack {
                Button("Отмена", role: .cancel) { dismiss() }
                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button("Загрузить") { loadSubscription() }
                    .buttonStyle(.borderedProminent)
                    .disabled(urlText.isEmpty || isLoading)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    func loadSubscription() {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            error = "Неверный URL"; return
        }
        isLoading = true; error = ""
        URLSession.shared.dataTask(with: url) { data, _, err in
            DispatchQueue.main.async {
                isLoading = false
                guard let data = data, err == nil else {
                    error = err?.localizedDescription ?? "Ошибка загрузки"; return
                }
                let text = String(data: data, encoding: .utf8) ?? ""
                let decoded = (Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .flatMap { String(data: $0, encoding: .utf8) }) ?? text
                var added = 0
                for line in decoded.components(separatedBy: .newlines) {
                    let l = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if l.hasPrefix("vless://"), let cfg = parseVlessURL(l) {
                        store.add(cfg); added += 1
                    }
                }
                if added > 0 { dismiss() }
                else { error = "Не найдено конфигураций в подписке" }
            }
        }.resume()
    }
}

// ── Добавить VLESS вручную ─────────────────────────────────────────────────
struct AddVlessManualView: View {
    @ObservedObject var store: MacConfigStore
    let dismiss: DismissAction

    @State private var name = ""
    @State private var uuid = ""
    @State private var address = ""
    @State private var port = "443"
    @State private var network = "tcp"
    @State private var security = "reality"
    @State private var sni = ""
    @State private var pbk = ""
    @State private var sid = ""
    @State private var flow = "xtls-rprx-vision"
    @State private var fp = "chrome"
    @State private var path = ""

    let networks = ["tcp", "ws", "grpc", "httpupgrade"]
    let securities = ["reality", "tls", "none"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Добавить VLESS вручную").font(.headline)
                Group {
                    field("Название", text: $name, placeholder: "Мой сервер")
                    field("UUID", text: $uuid, placeholder: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")
                    field("Адрес", text: $address, placeholder: "example.com")
                    field("Порт", text: $port, placeholder: "443")
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Сеть").font(.callout).foregroundStyle(.secondary)
                        Picker("", selection: $network) {
                            ForEach(networks, id: \.self) { Text($0) }
                        }.labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Безопасность").font(.callout).foregroundStyle(.secondary)
                        Picker("", selection: $security) {
                            ForEach(securities, id: \.self) { Text($0) }
                        }.labelsHidden()
                    }
                }
                field("SNI", text: $sni, placeholder: "example.com")
                if security == "reality" {
                    field("Public Key (pbk)", text: $pbk, placeholder: "")
                    field("Short ID (sid)", text: $sid, placeholder: "")
                }
                field("Flow", text: $flow, placeholder: "xtls-rprx-vision")
                field("Fingerprint", text: $fp, placeholder: "chrome")
                if network == "ws" || network == "grpc" || network == "httpupgrade" {
                    field("Path", text: $path, placeholder: "/")
                }
                HStack {
                    Button("Отмена", role: .cancel) { dismiss() }
                    Spacer()
                    Button("Добавить") {
                        let cfg = VlessConfig(
                            name: name.isEmpty ? address : name,
                            uuid: uuid, address: address, port: port,
                            path: path, network: network, security: security,
                            sni: sni, publicKey: pbk, shortId: sid,
                            flow: flow, fingerprint: fp
                        )
                        store.add(.vless(cfg)); dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(uuid.isEmpty || address.isEmpty)
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
        .frame(width: 480, height: 520)
    }

    func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// ── Добавить WireGuard вручную ─────────────────────────────────────────────
struct AddWireGuardManualView: View {
    @ObservedObject var store: MacConfigStore
    let dismiss: DismissAction

    @State private var name = ""
    @State private var privateKey = ""
    @State private var address = ""
    @State private var dns = "1.1.1.1"
    @State private var publicKey = ""
    @State private var endpoint = ""
    @State private var allowedIPs = "0.0.0.0/0"
    @State private var presharedKey = ""
    @State private var wgText = ""
    @State private var showPaste = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Добавить WireGuard").font(.headline)

                // Вставить .conf
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Вставить .conf файл").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button(showPaste ? "Скрыть" : "Показать") { showPaste.toggle() }
                            .font(.callout)
                    }
                    if showPaste {
                        TextEditor(text: $wgText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 120)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        Button("Разобрать") { parseConf() }
                            .disabled(wgText.isEmpty)
                    }
                }

                Divider()

                Group {
                    field("Название", text: $name, placeholder: "Мой WG сервер")
                    field("Private Key", text: $privateKey, placeholder: "")
                    field("Адрес интерфейса", text: $address, placeholder: "10.0.0.2/32")
                    field("DNS", text: $dns, placeholder: "1.1.1.1")
                    field("Public Key (Peer)", text: $publicKey, placeholder: "")
                    field("Endpoint", text: $endpoint, placeholder: "server.com:51820")
                    field("Allowed IPs", text: $allowedIPs, placeholder: "0.0.0.0/0")
                    field("Preshared Key (опционально)", text: $presharedKey, placeholder: "")
                }

                HStack {
                    Button("Отмена", role: .cancel) { dismiss() }
                    Spacer()
                    Button("Добавить") {
                        let cfg = WireGuardConfig(
                            name: name.isEmpty ? endpoint : name,
                            privateKey: privateKey, address: address,
                            dns: dns, publicKey: publicKey,
                            endpoint: endpoint, allowedIPs: allowedIPs,
                            presharedKey: presharedKey
                        )
                        store.add(.wireguard(cfg)); dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(privateKey.isEmpty || publicKey.isEmpty || endpoint.isEmpty)
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
        .frame(width: 480, height: 560)
    }

    func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    func parseConf() {
        var inInterface = false
        var inPeer = false
        for rawLine in wgText.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "[Interface]" { inInterface = true; inPeer = false; continue }
            if line == "[Peer]"      { inPeer = true; inInterface = false; continue }
            let parts = line.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }
            let key = parts[0]
            let val = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
            if inInterface {
                if key == "PrivateKey" { privateKey = val }
                if key == "Address"    { address = val }
                if key == "DNS"        { dns = val }
            }
            if inPeer {
                if key == "PublicKey"     { publicKey = val }
                if key == "Endpoint"      { endpoint = val }
                if key == "AllowedIPs"    { allowedIPs = val }
                if key == "PresharedKey"  { presharedKey = val }
            }
        }
    }
}

// ── VLESS URL parser ───────────────────────────────────────────────────────
func parseVlessURL(_ urlStr: String) -> VPNConfig? {
    guard urlStr.hasPrefix("vless://"),
          let url = URL(string: urlStr),
          let host = url.host,
          let port = url.port else { return nil }
    let uuid = url.user ?? ""
    let name = url.fragment ?? host
    var params: [String: String] = [:]
    if let query = url.query {
        for item in query.components(separatedBy: "&") {
            let kv = item.components(separatedBy: "=")
            if kv.count == 2,
               let k = kv[0].removingPercentEncoding,
               let v = kv[1].removingPercentEncoding {
                params[k] = v
            }
        }
    }
    let cfg = VlessConfig(
        name: name.removingPercentEncoding ?? name,
        uuid: uuid, address: host, port: String(port),
        path: params["path"] ?? "/",
        network: params["type"] ?? "tcp",
        security: params["security"] ?? "none",
        sni: params["sni"] ?? "",
        publicKey: params["pbk"] ?? "",
        shortId: params["sid"] ?? "",
        flow: params["flow"] ?? "",
        fingerprint: params["fp"] ?? "chrome"
    )
    return .vless(cfg)
}

// ── Импорт .conf файла ─────────────────────────────────────────────────────
struct ImportFileView: View {
    @ObservedObject var store: MacConfigStore
    let dismiss: DismissAction
    @State private var isImporting = false
    @State private var error = ""

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Импорт файла").font(.headline)
            Text("Выберите .conf (WireGuard) или вставьте содержимое")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if !error.isEmpty {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack(spacing: 12) {
                Button("Отмена", role: .cancel) { dismiss() }
                Button("Выбрать файл...") { isImporting = true }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 360)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.text, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                    error = "Не удалось прочитать файл"; return
                }
                parseAndAdd(content: content, name: url.deletingPathExtension().lastPathComponent)
            case .failure(let err):
                error = err.localizedDescription
            }
        }
    }

    func parseAndAdd(content: String, name: String) {
        var privateKey = "", address = "", dns = "1.1.1.1"
        var publicKey = "", endpoint = "", allowedIPs = "0.0.0.0/0", presharedKey = ""
        var inInterface = false, inPeer = false
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "[Interface]" { inInterface = true; inPeer = false; continue }
            if line == "[Peer]"      { inPeer = true; inInterface = false; continue }
            let parts = line.components(separatedBy: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }
            let key = parts[0]
            let val = parts[1...].joined(separator: "=").trimmingCharacters(in: .whitespaces)
            if inInterface {
                if key == "PrivateKey" { privateKey = val }
                if key == "Address"    { address = val }
                if key == "DNS"        { dns = val }
            }
            if inPeer {
                if key == "PublicKey"    { publicKey = val }
                if key == "Endpoint"     { endpoint = val }
                if key == "AllowedIPs"   { allowedIPs = val }
                if key == "PresharedKey" { presharedKey = val }
            }
        }
        if !privateKey.isEmpty && !publicKey.isEmpty {
            let cfg = WireGuardConfig(
                name: name, privateKey: privateKey, address: address,
                dns: dns, publicKey: publicKey, endpoint: endpoint,
                allowedIPs: allowedIPs, presharedKey: presharedKey
            )
            store.add(.wireguard(cfg))
            dismiss()
        } else {
            error = "Файл не содержит WireGuard конфигурацию"
        }
    }
}
