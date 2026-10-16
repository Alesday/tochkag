//
//  BrandKit.swift
//  Tochka G — дизайн-система «liquid glass / aurora»
//
//  Перенос токенов из tochka_g_brand.html в SwiftUI.
//  iOS 16+.
//

import SwiftUI

// MARK: - Hex helper

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 8:
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8)  & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        case 6:
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8)  & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        default:
            r = 1; g = 1; b = 1; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Brand tokens

enum Brand {
    static let blue   = Color(hex: "2E74C8")
    static let cyan   = Color(hex: "43AEDD")
    static let indigo = Color(hex: "4B43A0")
    static let violet = Color(hex: "7A53B0")
    static let coral  = Color(hex: "E85C72")
    static let amber  = Color(hex: "F2A85E")

    static let text   = Color(hex: "EEF2FB")
    static let muted  = Color(hex: "A6B0CC")
    static let faint  = Color(hex: "74809E")

    static let glassFill = Color.white.opacity(0.065)
    static let edge      = Color.white.opacity(0.14)
    static let highlight = Color.white.opacity(0.28)

    static let pingGood = cyan
    static let pingMid  = Color(hex: "F0C07A")
    static let pingHigh = Color(hex: "EF8E96")

    static let disconnect = Color(hex: "FF8B80")

    static let grad = LinearGradient(
        stops: [
            .init(color: Color(hex: "3B7FD0"), location: 0.0),
            .init(color: Color(hex: "7A53B0"), location: 0.52),
            .init(color: Color(hex: "E85C72"), location: 1.0)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let gradWarm = LinearGradient(
        colors: [coral, amber],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let orbSpectrum = AngularGradient(
        gradient: Gradient(colors: [blue, cyan, amber, coral, violet, blue]),
        center: .center, angle: .degrees(200)
    )
}

// MARK: - Стекло

private struct BrandGlass: ViewModifier {
    var cornerRadius: CGFloat = 18
    var tint: Color = Brand.glassFill
    var strokeColor: Color = Brand.edge

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Brand.highlight, .clear],
                            startPoint: .top, endPoint: .center
                        ),
                        lineWidth: 1
                    )
                    .blendMode(.overlay)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func brandGlass(cornerRadius: CGFloat = 18,
                    tint: Color = Brand.glassFill,
                    stroke: Color = Brand.edge) -> some View {
        modifier(BrandGlass(cornerRadius: cornerRadius, tint: tint, strokeColor: stroke))
    }
}

// MARK: - Аврора-фон

struct AuroraBackground: View {
    var animated: Bool = true
    @State private var drift = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0C1230"), Color(hex: "121634"), Color(hex: "0E1230")],
                startPoint: .top, endPoint: .bottom
            )
            radial(Brand.blue.opacity(0.32), x: 0.18, y: -0.08, scale: 1.15)
            radial(Brand.cyan.opacity(0.22), x: 0.90, y: 0.06, scale: 0.95)
            radial(Brand.amber.opacity(0.22), x: 0.88, y: 1.12, scale: 1.10)
            radial(Brand.coral.opacity(0.24), x: 0.08, y: 1.06, scale: 1.00)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "786ED2").opacity(0.20), .clear],
                        center: .center, startRadius: 0, endRadius: 220
                    )
                )
                .frame(width: 440, height: 440)
                .offset(x: drift ? 30 : -20, y: drift ? 40 : -10)
                .scaleEffect(drift ? 1.14 : 1.0)
                .blur(radius: 30)
        }
        .ignoresSafeArea()
        .onAppear {
            guard animated else { return }
            withAnimation(.easeInOut(duration: 15).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func radial(_ color: Color, x: Double, y: Double, scale: Double) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            RadialGradient(
                colors: [color, .clear],
                center: UnitPoint(x: x, y: y),
                startRadius: 0,
                endRadius: max(w, h) * 0.7 * scale
            )
        }
    }
}

// MARK: - Орб подключения

struct ConnectionOrb: View {
    var diameter: CGFloat = 150
    var ringDiameter: CGFloat = 208
    var animated: Bool = true

    @State private var spin = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: Color(hex: "7896E6").opacity(0.0), location: 0.55),
                            .init(color: Color(hex: "7896E6").opacity(0.5), location: 0.88),
                            .init(color: Color(hex: "DCEBFF").opacity(0.9), location: 0.97),
                            .init(color: .clear, location: 1.0)
                        ]),
                        center: .center
                    ),
                    lineWidth: 3
                )
                .frame(width: ringDiameter, height: ringDiameter)
                .rotationEffect(.degrees(spin ? 360 : 0))

            Circle()
                .fill(Brand.orbSpectrum)
                .overlay(
                    RadialGradient(
                        colors: [Color.white.opacity(0.92), .clear],
                        center: UnitPoint(x: 0.36, y: 0.30),
                        startRadius: 0, endRadius: diameter * 0.30
                    )
                    .clipShape(Circle())
                )
                .frame(width: diameter, height: diameter)
                .shadow(color: Color(hex: "7878DC").opacity(0.40), radius: 30)
                .shadow(color: Color(hex: "E8786E").opacity(0.35), radius: 14)
                .scaleEffect(breathe ? 1.035 : 1.0)
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) {
                spin = true
            }
            withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

// MARK: - Кнопки

struct BrandPrimaryButton: View {
    var title: String
    var systemIcon: String? = nil
    var gradient: LinearGradient = Brand.grad
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemIcon { Image(systemName: systemIcon) }
                Text(title)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(gradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
                    .blendMode(.overlay)
            )
            .shadow(color: Color(hex: "7850AA").opacity(0.36), radius: 18, y: 8)
        }
        .buttonStyle(.plain)
    }
}

struct BrandDisconnectButton: View {
    var title: String = "Отключиться"
    var systemIcon: String? = "power"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let systemIcon { Image(systemName: systemIcon) }
                Text(title)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Brand.disconnect)
            .frame(maxWidth: .infinity)
            .padding(14)
            .brandGlass(cornerRadius: 12, tint: Color.white.opacity(0.06))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Сегмент-контрол

struct BrandSegmentedControl: View {
    var titles: [String]
    @Binding var selection: Int
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { i in
                let active = selection == i
                Text(titles[i])
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(active ? .white : Brand.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        ZStack {
                            if active {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Brand.grad)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                            .blendMode(.overlay)
                                    )
                                    .shadow(color: Color(hex: "7850AA").opacity(0.34), radius: 8, y: 4)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            selection = i
                        }
                    }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.24))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Чип

struct BrandChip: View {
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? .white : Brand.muted)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Brand.grad)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                    .blendMode(.overlay)
                            )
                            .shadow(color: Color(hex: "7850AA").opacity(0.30), radius: 6, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Brand.glassFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                            )
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Пинг-пилюля

struct PingPill: View {
    var ms: Int

    private var color: Color {
        switch ms {
        case ..<90:   return Brand.pingGood
        case ..<130:  return Brand.pingMid
        default:      return Brand.pingHigh
        }
    }

    var body: some View {
        Text("\(ms) мс")
            .font(.system(size: 12.5, weight: .regular).monospacedDigit())
            .foregroundStyle(color)
    }
}

// MARK: - Карточка сервера (универсальная)

struct ServerRow: View {
    var flag: String
    var name: String
    var subtitle: String
    var ms: Int?
    var selected: Bool
    var trailingSystemIcon: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            FlagBadge(flag: flag)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .medium)).foregroundStyle(Brand.text)
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Brand.muted)
            }
            Spacer(minLength: 8)
            HStack(spacing: 9) {
                if let ms { PingPill(ms: ms) }
                if let trailingSystemIcon {
                    Image(systemName: trailingSystemIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? Brand.cyan : Brand.faint)
                }
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 13)
        .brandGlass(
            cornerRadius: 18,
            tint: selected ? Brand.cyan.opacity(0.14) : Brand.glassFill,
            stroke: selected ? Brand.cyan.opacity(0.5) : Color.white.opacity(0.08)
        )
        .shadow(color: selected ? Brand.blue.opacity(0.20) : .clear, radius: 22, y: 8)
    }
}

// MARK: - Бейдж флага

struct FlagBadge: View {
    var flag: String
    var size: CGFloat = 36

    var body: some View {
        Text(flag)
            .font(.system(size: size * 0.56))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                            .strokeBorder(Brand.edge, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Чип локации

struct LocationChip: View {
    var flag: String
    var name: String
    var subtitle: String
    var ms: Int

    var body: some View {
        HStack(spacing: 12) {
            FlagBadge(flag: flag)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 14, weight: .medium)).foregroundStyle(Brand.text)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(Brand.muted)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(ms) мс")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Brand.cyan)
                Text("пинг").font(.system(size: 11)).foregroundStyle(Brand.faint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .brandGlass(cornerRadius: 20)
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
    }
}

// MARK: - Поле конфигурации

struct ConfigCodeField: View {
    var placeholder: String = "vless://"
    var code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(placeholder)
                .font(.system(size: 12))
                .foregroundStyle(Brand.faint)
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(hex: "8FC6F0"))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(minHeight: 96, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Примечание с замком

struct LockNote: View {
    var text: String = "Ключи хранятся только на этом устройстве"
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").font(.system(size: 12))
            Text(text).font(.system(size: 12))
        }
        .foregroundStyle(Brand.muted)
    }
}
