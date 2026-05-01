// ConfigDetailView.swift
// TochkaG

import SwiftUI

struct ConfigDetailView: View {
    @EnvironmentObject var store: ConfigStore
    @Environment(\.presentationMode) var presentationMode
    let config: VPNConfig

    var body: some View {
        List {
            // Status
            Section {
                HStack {
                    Text("Статус")
                    Spacer()
                    Text(config.isActive ? "Активен" : "Неактивен")
                        .foregroundColor(config.isActive ? .green : .secondary)
                    Toggle("", isOn: Binding(
                        get: { config.isActive },
                        set: { _ in store.toggle(config) }
                    ))
                    .labelsHidden()
                }
            }

            // Parameters
            switch config {
            case .wireguard(let wg):
                Section("Интерфейс") {
                    row("Адрес",       wg.address)
                    row("DNS",         wg.dns)
                    row("Private Key", wg.privateKey)
                }
                Section("Peer") {
                    row("Public Key",  wg.publicKey)
                    row("Endpoint",    wg.endpoint)
                    row("Allowed IPs", wg.allowedIPs)
                }

            case .vless(let vl):
                Section("Сервер") {
                    row("Адрес",    vl.address)
                    row("Порт",     vl.port)
                }
                Section("Соединение") {
                    row("UUID",     vl.uuid)
                    row("Network",  vl.network)
                    row("Security", vl.security)
                    row("SNI",      vl.sni)
                    row("Path",     vl.path)
                }
            }

            // Delete
            Section {
                Button(role: .destructive) {
                    store.delete(config)
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    HStack {
                        Spacer()
                        Text("Удалить конфиг")
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle(config.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
                .foregroundColor(.primary)
        }
    }
}
