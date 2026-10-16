// ConfigDetailView.swift
// TochkaG — перекрашен под BrandKit (liquid glass / aurora).

import SwiftUI

struct ConfigDetailView: View {
    @EnvironmentObject var store: ConfigStore
    @Environment(\.presentationMode) var presentationMode
    let config: VPNConfig

    var body: some View {
        ZStack {
            AuroraBackground(animated: false)

            List {
                // Статус
                Section {
                    HStack {
                        Image(systemName: config.isActive ? "shield.fill" : "shield")
                            .font(.system(size: 16))
                            .foregroundStyle(config.isActive ? Brand.cyan : Brand.faint)
                        Text("Статус")
                            .font(.system(size: 15))
                            .foregroundStyle(Brand.text)
                        Spacer()
                        Text(config.isActive ? "Активен" : "Неактивен")
                            .font(.system(size: 13))
                            .foregroundStyle(config.isActive ? Brand.cyan : Brand.muted)
                        Toggle("", isOn: Binding(
                            get: { config.isActive },
                            set: { _ in store.toggle(config) }
                        ))
                        .labelsHidden()
                        .tint(Brand.cyan)
                    }
                    .padding(.vertical, 11)
                    .padding(.horizontal, 13)
                    .brandGlass(
                        cornerRadius: 16,
                        tint: config.isActive ? Brand.cyan.opacity(0.14) : Brand.glassFill,
                        stroke: config.isActive ? Brand.cyan.opacity(0.5) : Color.white.opacity(0.08)
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }

                // Параметры — только безопасное, без ключей и UUID
                switch config {
                case .wireguard(let wg):
                    section("Подключение") {
                        row("Сервер",   wg.endpoint)
                        row("Протокол", wg.awgParams?["Jc"] != nil ? "AmneziaWG" : "WireGuard")
                    }
                case .vless(let vl):
                    section("Подключение") {
                        row("Сервер",   "\(vl.address):\(vl.port)")
                        row("Протокол", "VLESS")
                    }
                }

                // Удаление
                Section {
                    Button(role: .destructive) {
                        store.delete(config)
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        HStack(spacing: 9) {
                            Spacer()
                            Image(systemName: "trash")
                            Text("Удалить конфиг")
                            Spacer()
                        }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Brand.disconnect)
                        .padding(.vertical, 12)
                        .brandGlass(cornerRadius: 14, tint: Color.white.opacity(0.05))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .preferredColorScheme(.dark)
        .navigationTitle(config.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
    }

    // MARK: - Секция в стекле

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        Section {
            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 13)
            .brandGlass(cornerRadius: 16)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        } header: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.muted)
                .textCase(nil)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Brand.muted)
            Spacer(minLength: 8)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 12, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Brand.text)
        }
        .padding(.vertical, 9)
    }
}
