// SPDX-License-Identifier: AGPL-3.0-only
// Nino görünümü: saydam cam yüzeyler, PlayStation mavisi ve lacivert zemin.
// Based on CouchSubs by Sinan Yorulmaz (https://github.com/yorulmazsinan/couchsubs), modified on 2026-11-14.

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    /// Cam yüzeylerin ince ışık kenarı.
    static let ninoGlassEdge = Color(nsColorName: "ninoGlassEdge", light: (1, 1, 1, 0.75), dark: (1, 1, 1, 0.12))
    /// Cam yüzeyin altına serilen hafif renk (açıkta beyaz, koyuda lacivert).
    static let ninoGlassFill = Color(nsColorName: "ninoGlassFill", light: (1, 1, 1, 0.55), dark: (0.06, 0.10, 0.22, 0.55))

    fileprivate init(nsColorName name: String, light: (Double, Double, Double, Double), dark: (Double, Double, Double, Double)) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: NSColor.Name(name)) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
        #else
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
        #endif
    }
}

extension View {
    /// Cam yüzey: macOS 26 ve sonrasında sistemin "Liquid Glass" efekti, öncesinde buzlu cam (material).
    @ViewBuilder func ninoGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26, iOS 26, *) {
            self
                .background(Color.ninoGlassFill, in: shape)
                .glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(Color.ninoGlassFill, in: shape)
        }
    }
}

/// Pencere zemini: açıkta beyazdan buz mavisine, koyuda laciverte giden degrade ve camın arkasında süzülen iki mavi ışık.
struct NinoBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(colors: dark
                           ? [Color(red: 0.02, green: 0.04, blue: 0.10), Color(red: 0.04, green: 0.09, blue: 0.22)]
                           : [Color(red: 0.97, green: 0.98, blue: 1.00), Color(red: 0.89, green: 0.93, blue: 0.99)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color(red: 0.00, green: 0.44, blue: 0.82).opacity(dark ? 0.35 : 0.22))
                .frame(width: 520, height: 520)
                .blur(radius: 120)
                .offset(x: drift ? -260 : -200, y: drift ? -220 : -170)
            Circle()
                .fill(Color(red: 0.00, green: 0.13, blue: 0.36).opacity(dark ? 0.55 : 0.16))
                .frame(width: 600, height: 600)
                .blur(radius: 140)
                .offset(x: drift ? 300 : 240, y: drift ? 260 : 210)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
        .accessibilityHidden(true)
    }
}

/// Açılış ekranı: logo bulanıklıktan netleşerek büyür, arkasında mavi bir halka döner, ardından yazı belirir.
struct SplashView: View {
    var onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoIn = false
    @State private var ringSpin = false
    @State private var textIn = false
    @State private var leaving = false
    @State private var flagGlow = false
    @State private var flagShine = false

    var body: some View {
        ZStack {
            NinoBackdrop()
            VStack(spacing: 28) {
                ZStack {
                    // Dönen ışık halkası
                    Circle()
                        .strokeBorder(AngularGradient(colors: [.clear, Color.csAccent, Color.csAccentHi, .clear, .clear],
                                                      center: .center), lineWidth: 3)
                        .frame(width: 290, height: 290)
                        .blur(radius: 1.5)
                        .rotationEffect(.degrees(ringSpin ? 360 : 0))
                        .opacity(logoIn ? 1 : 0)
                    Circle()
                        .fill(Color.csAccent.opacity(0.25))
                        .frame(width: 220, height: 220)
                        .blur(radius: 60)
                        .scaleEffect(logoIn ? 1 : 0.4)
                    LogoView(size: 200)
                        .overlay { FlagHighlight(glow: flagGlow, shine: flagShine) }
                        .scaleEffect(logoIn ? 1 : 0.72)
                        .blur(radius: logoIn ? 0 : 14)
                        .opacity(logoIn ? 1 : 0)
                }
                VStack(spacing: 6) {
                    Text(verbatim: "Nino")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("Your games, in Turkish.")
                        .font(.csBody)
                        .foregroundStyle(Color.csSecondary)
                }
                .opacity(textIn ? 1 : 0)
                .offset(y: textIn ? 0 : 12)
            }
            .scaleEffect(leaving ? 1.06 : 1)
            .opacity(leaving ? 0 : 1)
        }
        .task {
            if reduceMotion {
                logoIn = true; textIn = true
                try? await Task.sleep(for: .milliseconds(900))
                onFinish(); return
            }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.72)) { logoIn = true }
            withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { ringSpin = true }
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.6)) { textIn = true }
            // Bayrak: kırmızı ışık iki kez nabız gibi atar, üstünden beyaz bir parıltı geçer.
            withAnimation(.easeInOut(duration: 0.55).repeatCount(3, autoreverses: true)) { flagGlow = true }
            withAnimation(.easeInOut(duration: 0.9).delay(0.15)) { flagShine = true }
            try? await Task.sleep(for: .milliseconds(1700))
            withAnimation(.easeIn(duration: 0.45)) { leaving = true }
            try? await Task.sleep(for: .milliseconds(450))
            onFinish()
        }
    }
}

/// Logodaki Türk bayrağının üstünde kırmızı parıltı ve soldan sağa geçen ışık (LogoView(size:200) ölçüsüne göre).
private struct FlagHighlight: View {
    var glow: Bool
    var shine: Bool

    var body: some View {
        // Bayrak, 1254'lük görselde yaklaşık x 470–780, y 235–345; LogoView görseli 1.21 kat büyütür.
        let scale = 200 * 1.21 / 1254
        let w = 310 * scale, h = 110 * scale
        let y = (290 - 627) * scale
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.95, green: 0.12, blue: 0.16))
                .frame(width: w * 1.15, height: h * 1.3)
                .blur(radius: 18)
                .opacity(glow ? 0.85 : 0)
                .blendMode(.screen)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [.clear, .white.opacity(0.75), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: w * 0.35, height: h)
                .offset(x: shine ? w * 0.75 : -w * 0.75)
                .opacity(shine ? 0 : 1)
                .blendMode(.plusLighter)
                .frame(width: w, height: h)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .offset(y: y)
        .allowsHitTesting(false)
    }
}

/// Cam zeminli bölmeli seçici: seçili bölmenin altında mavi bir kapsül kayar (Apple'ın segment kontrolü gibi).
struct NinoSegmented<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String, String)]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let (value, title, symbol) = options[i]
                let selected = value == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selection = value }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                        Text(verbatim: title).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .font(.csCallout.weight(.semibold))
                    .foregroundStyle(selected ? Color.white : Color.csSecondary)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background {
                        if selected {
                            Capsule()
                                .fill(LinearGradient(colors: [Color.csAccent, Color(red: 0.0, green: 0.19, blue: 0.52)],
                                                     startPoint: .top, endPoint: .bottom))
                                .shadow(color: Color.csAccent.opacity(0.4), radius: 8, y: 3)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .ninoGlass(in: Capsule())
        .overlay(Capsule().strokeBorder(Color.ninoGlassEdge))
    }
}

/// Tıklanabilir seçenek kartı: solda degrade simge, başlık ve açıklama, sağda ok. Üzerine gelince hafifçe büyür.
struct OptionCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    var action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.space("l")) {
                GradientIcon(symbol: symbol, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.csHeadline).foregroundStyle(Color.csText)
                    Text(detail).font(.csCallout).foregroundStyle(Color.csSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(hovering ? Color.csAccentText : Color.csSecondary)
                    .offset(x: hovering ? 3 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tile(hovering ? .active : .plain, padding: Theme.space("l"))
            .scaleEffect(hovering ? 1.01 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius("card"), style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { h in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { hovering = h } }
    }
}
