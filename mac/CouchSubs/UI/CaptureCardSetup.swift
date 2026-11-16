// SPDX-License-Identifier: AGPL-3.0-only
// Nino: yakalama kartı kurulum rehberi ve canlı önizleme. Bu dosya Nino için sıfırdan yazıldı.

import AVFoundation
import AppKit
import CouchSubsCore
import SwiftUI

/// Kartın canlı önizlemesi için kartı kısa süre açan denetleyici (rehberde ve ayarlarda; çeviri sürerken açılmaz).
@MainActor
final class CaptureCardProbe: ObservableObject {
    @Published private(set) var status = CaptureCardCapture.Status.stopped
    @Published private(set) var devices: [CaptureCardInfo] = []
    let capture = CaptureCardCapture()
    private var observers: [NSObjectProtocol] = []

    func start(preferred: String?) {
        capture.preferredID = preferred
        capture.onStatus = { [weak self] status in self?.status = status }
        refreshDevices()
        let center = NotificationCenter.default
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDevices() }
            })
        }
        capture.start()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        capture.stop()
    }

    func choose(_ id: String?) {
        capture.preferredID = id
        capture.refresh()
    }

    private func refreshDevices() { devices = CaptureCardCapture.videoDevices() }
}

/// Kartın görüntüsünü gösteren küçük ekran (ekran kartıyla çizilir).
struct CaptureCardPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.backgroundColor = NSColor.black.cgColor
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspect
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(preview)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.layer?.sublayers?.forEach { $0.frame = view.bounds }
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        view.layer?.sublayers?.compactMap { $0 as? AVCaptureVideoPreviewLayer }.forEach { $0.session = nil }
    }
}

/// Önizleme, durum satırı ve (birden çok aygıt varsa) aygıt seçici. Rehberin son adımında ve ayarlarda kullanılır.
struct CaptureCardCheck: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var probe = CaptureCardProbe()
    var previewHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space("m")) {
            ZStack {
                CaptureCardPreview(session: probe.capture.session)
                if !hasPicture {
                    VStack(spacing: Theme.space("s")) {
                        Image(systemName: symbol).font(.system(size: 30, weight: .semibold))
                        Text(LocalizedStringKey(headline)).font(.csHeadline)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(height: previewHeight)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius("control"), style: .continuous))
            .overlay(alignment: .topLeading) { chip.padding(10) }

            if let detail {
                Label(LocalizedStringKey(detail), systemImage: tone == .good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.csCallout)
                    .foregroundStyle(tone == .good ? Color.csSuccess : Color.csWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if probe.status == .needsPermission {
                Button("Open Camera Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.secondary)
            }
            if probe.devices.count > 1 {
                Picker("Capture device", selection: Binding(get: { model.preferredCardID ?? "" }, set: { id in
                    model.preferredCardID = id.isEmpty ? nil : id
                    probe.choose(model.preferredCardID)
                })) {
                    Text("Automatic").tag("")
                    ForEach(probe.devices, id: \.id) { device in Text(verbatim: device.name).tag(device.id) }
                }
            }
        }
        .onAppear { probe.start(preferred: model.preferredCardID) }
        .onDisappear { probe.stop() }
    }

    private var tone: StatusTone {
        switch probe.status {
        case .capturing: .good
        case .stopped: .idle
        default: .warning
        }
    }

    /// Kart görüntü veriyor (siyah da olsa): önizlemenin üstüne yazı konmaz.
    private var hasPicture: Bool {
        switch probe.status {
        case .capturing, .blackPicture: true
        default: false
        }
    }

    private var symbol: String {
        probe.status == .needsPermission ? "lock.fill" : "cable.connector"
    }

    private var headline: String {
        switch probe.status {
        case .needsPermission: "Camera permission needed"
        case .noCard, .stopped: "Looking for your capture card…"
        default: ""
        }
    }

    private var detail: String? {
        switch probe.status {
        case .capturing: "The card is working. You can see the PS5 picture."
        case .blackPicture: "The card is connected but the picture is black. Turn the PS5 on and turn off HDCP (previous step)."
        case .needsPermission: "Capture cards appear as a camera on the Mac. Allow Nino in System Settings › Privacy & Security › Camera, then reopen Nino."
        case .noCard: "Plug the card into a USB 3 port on this Mac. If you use a hub, try a port on the Mac itself."
        case .stopped: nil
        }
    }

    @ViewBuilder private var chip: some View {
        HStack(spacing: 6) {
            Circle().fill(tone.color).frame(width: 7, height: 7)
            switch probe.status {
            case .capturing(let name), .blackPicture(let name): Text(verbatim: name)
            case .noCard: Text("No card found")
            case .stopped: Text("Searching…")
            case .needsPermission: Text("No permission")
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10).frame(height: 24)
        .background(Capsule().fill(Color.black.opacity(0.5)))
    }
}

/// Yakalama kartı kurulum rehberi: 1) nasıl bağlanacağı, 2) PS5'te HDCP, 3) kartı takıp görüntüyü görmek.
/// Kurulum sihirbazında (`inSheet` kapalı) ve ayarlarda ayrı bir pencerede açılır.
struct CaptureCardSetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var inSheet = false
    @State private var page = 0
    @State private var toTV = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch page {
                    case 0: layoutPage
                    case 1: hdcpPage
                    default: checkPage
                    }
                }
                .id(page)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .padding(.horizontal, Theme.space("xxl"))
                .padding(.vertical, Theme.space("xl"))
            }
            .scrollIndicators(.never)
            .frame(maxWidth: 700, maxHeight: .infinity)
            .clipped()
            .tile(padding: 0)
            .padding(.horizontal, inSheet ? Theme.space("xl") : Theme.space("xxl"))
            .padding(.top, Theme.space("m"))
            buttons
                .frame(maxWidth: 700)
                .padding(.horizontal, inSheet ? Theme.space("xl") : Theme.space("xxl"))
                .padding(.vertical, Theme.space("xl"))
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: page)
        .onAppear { toTV = model.usesCaptureCard && model.settings.output.showsOnTV }
    }

    // MARK: Sayfalar

    private var layoutPage: some View {
        StepLayout(title: "How is your PS5 connected?",
                   message: "A capture card takes the PS5 picture over HDMI and gives it to this Mac over USB. No second PSN account or Remote Play needed.") {
            VStack(spacing: Theme.space("m")) {
                LayoutChoice(selected: !toTV, symbol: "display",
                             title: "Monitor or a TV without apps",
                             detail: "Nino shows the game full screen on this Mac with its sound, and the translation on top. Connect the Mac to the screen with HDMI.",
                             chain: ["gamecontroller.fill", "cable.connector", "laptopcomputer", "display"]) { toTV = false }
                LayoutChoice(selected: toTV, symbol: "tv",
                             title: "Smart TV with the Nino app",
                             detail: "Needs a card with HDMI out (passthrough). The game goes straight to the TV with no extra delay; Nino reads the card and sends the translation to the TV app.",
                             chain: ["gamecontroller.fill", "cable.connector", "tv.fill"]) { toTV = true }
            }
        }
        .environment(\.onboardingSymbol, "cable.connector")
    }

    private var hdcpPage: some View {
        StepLayout(title: "Turn off HDCP on the PS5",
                   message: "The PS5 blocks capture cards with a copy protection called HDCP. Games are not affected; you only do this once.") {
            VStack(alignment: .leading, spacing: Theme.space("l")) {
                NumberedRow(number: 1, text: "Connect the PS5 directly to a TV or monitor for a moment (the setting can't be changed through the card).")
                NumberedRow(number: 2, text: "On the PS5, open Settings › System › HDMI.")
                NumberedRow(number: 3, text: "Turn off Enable HDCP. Then connect the PS5 to the card's HDMI in.")
                Label("While HDCP is off, video apps like Netflix don't play on the PS5. Turn it back on to watch them.",
                      systemImage: "info.circle")
                    .font(.csCallout).foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Label("If a headset is plugged into the controller, the PS5 sends the sound there and the card gets no sound.",
                      systemImage: "headphones")
                    .font(.csCallout).foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .environment(\.onboardingSymbol, "lock.open.fill")
    }

    private var checkPage: some View {
        StepLayout(title: "Plug in the card",
                   message: toTV ? "Connect PS5 → card HDMI in, card HDMI out → TV, and the card's USB → this Mac."
                       : "Connect PS5 → card HDMI in, and the card's USB → this Mac. Then connect this Mac to your screen.") {
            CaptureCardCheck()
        }
        .environment(\.onboardingSymbol, "checkmark.seal.fill")
    }

    // MARK: Düğmeler

    private var buttons: some View {
        ZStack {
            HStack(spacing: 7) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i <= page ? Color.csAccent : Color.csSecondary.opacity(0.3))
                        .frame(width: i == page ? 24 : 7, height: 7)
                }
            }
            HStack(spacing: Theme.space("m")) {
                Button {
                    if page > 0 { page -= 1 } else if inSheet { dismiss() } else { model.cancelCaptureCardSetup() }
                } label: {
                    Label(page == 0 && inSheet ? "Cancel" : "Back", systemImage: page == 0 && inSheet ? "xmark" : "chevron.left")
                }
                .buttonStyle(CSButtonStyle(kind: .ghost, height: "buttonLarge"))
                Spacer()
                Button {
                    if page < 2 {
                        page += 1
                    } else {
                        model.finishCaptureCardSetup(toTV: toTV)
                        if inSheet { dismiss() }
                    }
                } label: {
                    Text(page < 2 ? "Continue" : "Done").frame(minWidth: 120)
                }
                .buttonStyle(CSButtonStyle(kind: .primary, height: "buttonLarge"))
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Bağlantı seçeneği: başlık, açıklama ve kablo şeması (PS5 → kart → …).
private struct LayoutChoice: View {
    let selected: Bool
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let chain: [String]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Theme.space("l")) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Color.csAccent : Color.csSecondary)
                VStack(alignment: .leading, spacing: Theme.space("s")) {
                    Text(title).font(.csHeadline)
                    Text(detail).font(.csCallout).foregroundStyle(Color.csSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Theme.space("s")) {
                        ForEach(Array(chain.enumerated()), id: \.offset) { index, item in
                            if index > 0 { Image(systemName: "arrow.right").font(.caption).foregroundStyle(Color.csSecondary) }
                            Image(systemName: item)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.csAccentText)
                                .frame(width: 36, height: 30)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.csAccentSoft))
                        }
                    }
                    .padding(.top, Theme.space("xs"))
                    .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .tile(selected ? .active : .plain, padding: Theme.space("l"))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
