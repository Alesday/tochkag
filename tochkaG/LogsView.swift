// LogsView.swift
// TochkaG — просмотр логов туннеля и Xray из App Group.

import SwiftUI
import UIKit

struct LogsView: View {
    @Environment(\.dismiss) var dismiss

    @State private var tunnelLog = ""
    @State private var xrayLog   = ""
    @State private var tab       = 0

    private let appGroup = "group.com.tochkag.vpn"

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Tunnel").tag(0)
                    Text("Xray").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView {
                    Text(tab == 0 ? tunnelLog : xrayLog)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
            .navigationTitle("Логи")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = tab == 0 ? tunnelLog : xrayLog
                    } label: { Image(systemName: "doc.on.doc") }
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            tunnelLog = "App Group недоступна"
            return
        }

        // tunnel.log — наши flog()
        let tunnelURL = dir.appendingPathComponent("tunnel.log")
        if let s = try? String(contentsOf: tunnelURL, encoding: .utf8), !s.isEmpty {
            tunnelLog = tail(s, lines: 300)
        } else if let ud = UserDefaults(suiteName: appGroup),
                  let arr = ud.stringArray(forKey: "tunnel_logs"), !arr.isEmpty {
            tunnelLog = arr.joined(separator: "\n")
        } else {
            tunnelLog = "tunnel.log пуст.\nПодключите VPN и обновите."
        }

        // xray.log — логи самого Xray (решения роутинга)
        let xrayURL = dir.appendingPathComponent("xray.log")
        if let s = try? String(contentsOf: xrayURL, encoding: .utf8), !s.isEmpty {
            xrayLog = tail(s, lines: 300)
        } else {
            xrayLog = "xray.log пуст.\nПоявится после подключения."
        }
    }

    private func tail(_ s: String, lines: Int) -> String {
        let all = s.components(separatedBy: .newlines)
        return all.count <= lines ? s : all.suffix(lines).joined(separator: "\n")
    }
}
