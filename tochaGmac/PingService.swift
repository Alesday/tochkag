import Foundation
import Network
import Combine
import SwiftUI

@MainActor
final class PingService: ObservableObject {
    @Published var latencyMs: Int? = nil
    @Published var isMeasuring = false

    enum Proto { case tcp, udp }

    private var timer: Timer?
    private var host: String = ""
    private var port: UInt16 = 0
    private var proto: Proto = .tcp

    func start(host: String, port: UInt16, proto: Proto) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.timer?.invalidate()
            self.timer = nil
            self.host = host
            self.port = port
            self.proto = proto
            self.measure()
            self.timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                guard let s = self else { return }
                Task { @MainActor in s.measure() }
            }
        }
    }

    func stop() {
        Task { @MainActor [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
            self?.latencyMs = nil
            self?.isMeasuring = false
        }
    }

    private func measure() {
        guard !host.isEmpty, port > 0 else { return }
        Task { @MainActor [weak self] in self?.isMeasuring = true }
        switch proto {
        case .tcp: measureTCP()
        case .udp: measureUDP()
        }
    }

    private func measureTCP() {
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: NWEndpoint.Port(rawValue: port)!,
                                using: .tcp)
        let start = Date()
        var done = false
        let finish: (Int?) -> Void = { [weak self] ms in
            guard !done else { return }
            done = true
            conn.cancel()
            Task { @MainActor [weak self] in
                self?.latencyMs = ms
                self?.isMeasuring = false
            }
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(Int(Date().timeIntervalSince(start) * 1000))
            case .failed, .cancelled:
                finish(nil)
            default: break
            }
        }
        conn.start(queue: .global(qos: .utility))
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            finish(nil)
        }
    }

    private func measureUDP() {
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: NWEndpoint.Port(rawValue: port)!,
                                using: .udp)
        let start = Date()
        var done = false
        let finish: (Int?) -> Void = { [weak self] ms in
            guard !done else { return }
            done = true
            conn.cancel()
            Task { @MainActor [weak self] in
                self?.latencyMs = ms
                self?.isMeasuring = false
            }
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                var pkt = Data([0x01, 0x00, 0x00, 0x00])
                pkt.append(Data(repeating: 0, count: 144))
                conn.send(content: pkt, completion: .contentProcessed { _ in
                    finish(Int(Date().timeIntervalSince(start) * 1000))
                })
                conn.receiveMessage { data, _, _, _ in
                    if let data = data, !data.isEmpty {
                        finish(Int(Date().timeIntervalSince(start) * 1000))
                    }
                }
            case .failed, .cancelled:
                finish(nil)
            default: break
            }
        }
        conn.start(queue: .global(qos: .utility))
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
            finish(nil)
        }
    }
}
