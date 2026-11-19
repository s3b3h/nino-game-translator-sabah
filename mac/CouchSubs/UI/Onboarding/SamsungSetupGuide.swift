// SPDX-License-Identifier: AGPL-3.0-only

import CouchSubsCore
import SwiftUI

/// Samsung TV'ye kurulumdan önceki denetim kartı: üç satırda neyin tamam, neyin eksik olduğunu gösterir ve yalnız
/// eksik adımı anlatır. TV'ye üç saniyede bir yeniden sorulur; adım tamamlanınca kart kendiliğinden ilerler.
/// Eskiden her durumda aynı dört adım ve "TV bu bilgisayarı kabul etmedi" gösteriliyordu; kullanıcı geliştirici modu
/// zaten açıkken pencereyi yeniden açmaya uğraşıyordu (QE55Q70C, 2026-11-19).
struct SamsungSetupGuide: View {
    @EnvironmentObject private var model: AppModel
    /// Kurulum denendi ve TV bağlantıyı kesti.
    var dropped = false
    /// Yardımcının verdiği ayrıntı (sdb hatası).
    var reason: String?
    @State private var showHelp = false

    private var check: SamsungSetupCheck? { model.samsungSetup }
    private var computer: String { check?.computer ?? model.computerAddress ?? "?" }

    var body: some View {
        Card(title: "Nino TV app") {
            if let check, check.problem != .tvNotResponding {
                VStack(alignment: .leading, spacing: Theme.space("s")) {
                    SetupCheckRow(tone: modeTone(check), text: modeText(check))
                    SetupCheckRow(tone: addressTone(check), text: addressText(check))
                    SetupCheckRow(tone: restartTone(check), text: restartText(check))
                }
            }
            guidance
        }
    }

    // MARK: Denetim satırları

    private func modeTone(_ check: SamsungSetupCheck) -> StatusTone { check.developerModeOn ? .good : .warning }

    private func modeText(_ check: SamsungSetupCheck) -> String {
        check.developerModeOn ? String(localized: "Developer mode is on") : String(localized: "Developer mode is off")
    }

    private func addressTone(_ check: SamsungSetupCheck) -> StatusTone {
        guard check.developerModeOn else { return .idle }
        switch check.problem {
        case .hostPcIpLoopback, .hostPcIpPadded, .hostPcIpReversed, .hostPcIpWrong: return .warning
        default: return check.hostPcIpMatches == true ? .good : .idle
        }
    }

    private func addressText(_ check: SamsungSetupCheck) -> String {
        if check.developerModeOn, let tvIp = check.info?.developerIp, check.hostPcIpMatches == false {
            return String(format: String(localized: "Host PC IP on the TV is %1$@, it must be %2$@"), tvIp, computer)
        }
        return String(format: String(localized: "Host PC IP is this computer's address (%@)"), computer)
    }

    private func restartTone(_ check: SamsungSetupCheck) -> StatusTone {
        guard check.developerModeOn else { return .idle }
        if check.portOpen { return .good }
        return check.problem == .needsRestart ? .warning : .idle
    }

    private func restartText(_ check: SamsungSetupCheck) -> String {
        check.developerModeOn && check.portOpen
            ? String(localized: "The TV has restarted and accepts installs")
            : String(localized: "The TV has fully restarted after the change")
    }

    // MARK: Eksik adım

    @ViewBuilder
    private var guidance: some View {
        switch check?.problem {
        case .tvNotResponding:
            waiting("Waiting for the TV to answer…")
            HintText(text: "Make sure the TV is on and on the same network as this computer. This screen continues by itself.")
        case .developerModeOff:
            Text("Nino installs the TV app once Developer Mode is on.")
            windowSteps
            HintText(text: "Later you sign in once with a free Samsung account; Samsung needs it to sign the app for your TV.")
        case .hostPcIpWrong(let tvIp):
            ErrorText(error: String(format: String(localized: "The TV has another address as Host PC IP (%1$@), so it does not accept this computer. Change it to %2$@."), tvIp, computer))
            windowSteps
            tryAnyway
        case .hostPcIpPadded(let tvIp):
            ErrorText(error: String(format: String(localized: "The address on the TV is typed with zeros in front (%1$@), so the TV does not accept this computer. Type it again without them: %2$@."), tvIp, computer))
            windowSteps
            tryAnyway
        case .hostPcIpReversed(let tvIp):
            ErrorText(error: String(format: String(localized: "The TV saved the address backwards (%1$@). This happens when the TV's language is written from right to left. Turn Developer mode Off and On again, then type the address backwards so the TV saves it as %2$@."), tvIp, computer))
            windowSteps
            tryAnyway
        case .hostPcIpLoopback:
            ErrorText(error: String(format: String(localized: "Host PC IP on the TV is 127.0.0.1. That setting is for installers that run on the TV itself; Nino installs from this computer. Change it to %@."), computer))
            windowSteps
        case .needsRestart:
            ErrorText(error: String(localized: "Developer mode is on, but the TV has not fully restarted yet, so it does not accept installs."))
            HintText(text: "Hold the power button on the remote until the Samsung logo appears, or unplug the TV for a minute. A short press only puts the TV on standby. This screen continues by itself.")
        case nil where dropped:
            droppedGuidance
        case nil:
            waiting("Checking the TV…")
        }
    }

    /// 2022 ve sonrası modellerde kod yalnız Uygulamalar sayfasının en altındaki Uygulama Ayarları'nda sayılır
    /// (couch-tv #53, Samsung'un kendi belgesi); eski modellerde Uygulamalar ekranında.
    private var codeGoesInAppSettings: Bool { (model.samsungModelYear ?? 0) >= 2022 }

    /// Geliştirici modu penceresini açma adımları; pencere açılmayanlar için ek yollar.
    @ViewBuilder
    private var windowSteps: some View {
        if codeGoesInAppSettings {
            HintText(text: "1. On the TV, open Apps, go to the very bottom of the page and select App Settings.")
        } else {
            HintText(text: "1. On the TV, open Apps. If the page has App Settings at the very bottom, select it.")
        }
        HintText(text: "2. Type 1 2 3 4 5. If the remote has no number buttons, press its 123 button and choose the numbers on the screen. The Developer Mode window opens after the fifth number.")
        HintText(text: "3. Turn Developer mode On and type this computer's address as Host PC IP: \(computer). Type each part as it is, without zeros in front (1, not 001), then choose OK. If the address cannot be changed, press the 123 button first.")
        HintText(text: "4. Restart the TV: hold the power button on the remote until the Samsung logo appears, or unplug the TV for a minute. This screen continues by itself.")
        DisclosureGroup(isExpanded: $showHelp) {
            VStack(alignment: .leading, spacing: Theme.space("s")) {
                HintText(text: "• Type the numbers in App Settings at the very bottom of Apps. On 2022 and newer TVs they do nothing on the first page of Apps.")
                HintText(text: "• Restart the TV fully (hold the power button until the Samsung logo appears) and try again; on some TVs the window opens on the second or third try.")
                HintText(text: "• Plug a USB keyboard into the TV and type 12345 with it. The number buttons of the SmartThings app on your phone work on some TVs.")
                HintText(text: "• Or let Nino type it: open App Settings on the TV, then press the button below. The TV may first ask you to allow Nino. This works on some TVs only.")
                HStack(spacing: Theme.space("s")) {
                    Button("Type 1 2 3 4 5 on the TV") { Task { await model.typeSamsungDevCode() } }
                        .buttonStyle(.secondary)
                        .disabled(model.samsungCode == .sending)
                    switch model.samsungCode {
                    case .idle: EmptyView()
                    case .sending: ProgressView().controlSize(.small)
                    case .sent: HintText(text: "Sent. If the window did not open on the TV, try one of the other ways.")
                    case .failed: HintText(text: "Could not reach the TV. Make sure it is on and try again.")
                    }
                }
            }
            .padding(.top, Theme.space("s"))
        } label: {
            Text("The window does not open?").font(.csCallout)
        }
    }

    /// TV adresi yanlış bildirebilir (ya da bu Mac'in adresi yanlış seçilmiş olabilir): kullanıcı yine de deneyebilir.
    private var tryAnyway: some View {
        Button("Try anyway") { Task { await model.installSamsungAnyway() } }.buttonStyle(.secondary)
    }

    /// Ayarlar doğru görünürken TV bağlantıyı kesti: çoğu zaman TV ayardan sonra tam kapanıp açılmamıştır.
    @ViewBuilder
    private var droppedGuidance: some View {
        if check?.hostPcIpMatches == true {
            ErrorText(error: String(localized: "The TV dropped the connection although its settings look right. Unplug the TV from the wall for a minute, plug it back in and wait a minute after it turns on. Nino tries again by itself when the TV is back."))
        } else {
            ErrorText(error: TVAppCard.message(for: .unreachable, brand: .samsung))
            HintText(text: "This computer's address (Host PC IP): \(computer)")
            HintText(text: "To restart a Samsung TV fully, hold the power button on the remote for about 2 seconds until it turns off; a short press only puts it on standby.")
        }
        if let reason {
            HintText(text: LocalizedStringKey(String(localized: "Details:") + " " + reason))
        }
        HintText(text: "If this keeps happening, send us this file: \(TVInstallLog.displayPath)")
        Button("Try again") { Task { await model.refreshTVApp() } }.buttonStyle(.secondary)
    }

    private func waiting(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: Theme.space("s")) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(Color.csSecondary)
        }
    }
}

/// Denetim satırı: tamam (yeşil işaret), eksik (turuncu ünlem) ya da henüz sırası gelmedi (boş daire).
private struct SetupCheckRow: View {
    let tone: StatusTone
    let text: String

    private var symbol: String {
        switch tone {
        case .good: "checkmark.circle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .idle: "circle"
        }
    }

    var body: some View {
        Label {
            Text(text)
                .font(.csCallout)
                .foregroundStyle(tone == .idle ? Color.csSecondary : Color.csText)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tone.color)
        }
        .accessibilityElement(children: .combine)
    }
}
