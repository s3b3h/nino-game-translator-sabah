// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI

/// Kurulum (Nino): iPhone'un ilk açılışı gibi ortada tek bir cam kart, altta ilerleme noktaları ve tek büyük düğme.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.space("s")) {
                LogoView(size: 26)
                Text(verbatim: "Nino").font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, Theme.space("xl"))
            .padding(.top, Theme.space("m"))

            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        switch model.step {
                        case .welcome: WelcomeStep()
                        case .secondAccount: SecondAccountStep()
                        case .psnLogin: PSNLoginStep()
                        case .console: ConsoleStep()
                        case .tv: TVStep()
                        case .test: TestStep()
                        case .betterTranslation, .done: BetterTranslationStep()
                        }
                    }
                    .id(model.step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    .environment(\.onboardingSymbol, Self.symbol(model.step))
                    .padding(.horizontal, Theme.space("xxl"))
                    .padding(.vertical, Theme.space("xl"))
                }
                .scrollIndicators(.never)
                .environment(\.scrollOnboardingTo, { id in
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                })
            }
            .frame(maxWidth: 700, maxHeight: .infinity)
            .clipped()
            .tile(padding: 0)
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: model.step)
            .padding(.horizontal, Theme.space("xxl"))
            .padding(.top, Theme.space("m"))

            StepButtons()
                .frame(maxWidth: 700)
                .padding(.horizontal, Theme.space("xxl"))
                .padding(.vertical, Theme.space("xl"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension OnboardingView {
    static func symbol(_ step: AppModel.Step) -> String {
        switch step {
        case .welcome: "nino.logo"
        case .secondAccount: "person.crop.circle.badge.plus"
        case .psnLogin: "key.fill"
        case .console: "gamecontroller.fill"
        case .tv: "tv.fill"
        case .test: "captions.bubble.fill"
        case .betterTranslation, .done: "wand.and.stars"
        }
    }
}

extension EnvironmentValues {
    /// Sihirbazın kaydırma alanında verilen kimlikli görünüme kaydırır (adımın dışında hiçbir şey yapmaz).
    @Entry var scrollOnboardingTo: (String) -> Void = { _ in }
}

/// Geri (solda), ilerleme noktaları (ortada), Devam ya da "Şimdilik geç" (sağda).
private struct StepButtons: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            PageDots(count: AppModel.Step.allCases.count - 1, current: model.step.rawValue)
            HStack(spacing: Theme.space("m")) {
                if model.step != .welcome {
                    Button { withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { model.back() } } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(CSButtonStyle(kind: .ghost, height: "buttonLarge"))
                }
                Spacer()
                if model.step == .betterTranslation && !model.usesFreeGemini {
                    Button("Skip for now") { withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { model.advance() } }
                        .buttonStyle(CSButtonStyle(kind: .secondary, height: "buttonLarge"))
                } else if model.step != .test {
                    Button { withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { model.advance() } } label: {
                        Text("Continue").frame(minWidth: 120)
                    }
                    .buttonStyle(CSButtonStyle(kind: .primary, height: "buttonLarge"))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canAdvance)
                }
            }
        }
    }
}

/// iPhone'daki sayfa noktaları: geçerli adım uzun mavi kapsül, bitenler mavi, kalanlar soluk.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? Color.csAccent : Color.csSecondary.opacity(0.3))
                    .frame(width: i == current ? 24 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: current)
        .accessibilityElement()
        .accessibilityLabel(Text(String(format: String(localized: "Step %lld of %lld"), current + 1, count)))
    }
}

/// Adım listesi: biten adımlar onaylı, sıradaki adım vurgulu; altta "Adım n / toplam" ve ilerleme çubuğu.
private struct StepSidebar: View {
    @EnvironmentObject private var model: AppModel

    private var steps: [AppModel.Step] { AppModel.Step.allCases.filter { $0 != .done } }

    var body: some View {
        let total = steps.count
        VStack(alignment: .leading, spacing: Theme.space("xs")) {
            HStack(spacing: Theme.space("m")) {
                LogoView(size: 32)
                Text("Setup").font(.csTitle)
            }
            .padding(.horizontal, Theme.space("s"))
            .padding(.bottom, Theme.space("m"))
            ForEach(steps, id: \.self) { step in
                StepRow(step: step, current: model.step)
            }
            Spacer(minLength: Theme.space("l"))
            Text(String(format: String(localized: "Step %lld of %lld"), min(model.step.rawValue + 1, total), total))
                .font(.csCaption.monospacedDigit())
                .foregroundStyle(Color.csSecondary)
                .padding(.horizontal, Theme.space("s"))
            ProgressBar(value: Double(model.step.rawValue + 1) / Double(total))
                .padding(.horizontal, Theme.space("s"))
                .padding(.top, Theme.space("xs"))
        }
        .frame(width: Theme.size("sidebarWidth"), alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .tile(padding: Theme.space("m"))
    }
}

private struct StepRow: View {
    let step: AppModel.Step
    let current: AppModel.Step

    private var isDone: Bool { step.rawValue < current.rawValue }
    private var isCurrent: Bool { step == current }

    var body: some View {
        HStack(spacing: Theme.space("m")) {
            marker
            Text(Self.title(step))
                .font(isCurrent ? .csBody.weight(.semibold) : .csBody)
                .foregroundStyle(isCurrent || isDone ? Color.csText : Color.csSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.space("s"))
        .padding(.vertical, Theme.space("s"))
        .background(isCurrent ? Color.csAccentSoft : Color.clear, in: RoundedRectangle(cornerRadius: Theme.radius("control"), style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// Bitti: yeşil daire ve onay; şimdi: sarı daire; sonra: nötr daire. Parıltı yok.
    @ViewBuilder private var marker: some View {
        let size: CGFloat = 28
        if isDone {
            Image(systemName: "checkmark")
                .font(.csCaption.weight(.semibold))
                .foregroundStyle(Color.csSurface)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.csSuccess))
        } else {
            Text("\(step.rawValue + 1)")
                .font(.csCaption.monospacedDigit().weight(.semibold))
                .foregroundStyle(isCurrent ? Color.csOnAccent : Color.csSecondary)
                .frame(width: size, height: size)
                .background(Circle().fill(isCurrent ? AnyShapeStyle(LinearGradient(colors: [Color.csAccentHi, Color(red: 0.0, green: 0.19, blue: 0.52)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.csSurface2)))
                .shadow(color: isCurrent ? Color.csAccent.opacity(0.5) : .clear, radius: 6)
        }
    }

    /// Adımın kendi başlığı (adım ekranındaki StepLayout başlığıyla aynı).
    static func title(_ step: AppModel.Step) -> LocalizedStringKey {
        switch step {
        case .welcome: "Welcome to Nino"
        case .secondAccount: "A second PSN account"
        case .psnLogin: "Sign in with the second account"
        case .console: "Connect your PS5"
        case .tv: "Connect your TV"
        case .test: "Let's test it"
        case .betterTranslation, .done: "Better translation (free)"
        }
    }
}

/// İnce, yuvarlak uçlu ilerleme çubuğu.
struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.csBorder)
                Capsule().fill(Color.csAccent)
                    .frame(width: geometry.size.width * min(max(value, 0), 1))
                    .animation(.easeOut(duration: 0.25), value: value)
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int(value * 100))%"))
    }
}
