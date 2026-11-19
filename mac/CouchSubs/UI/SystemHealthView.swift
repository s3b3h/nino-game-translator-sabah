// SPDX-License-Identifier: AGPL-3.0-only

import AppKit
import CouchSubsCore
import Network
import SwiftUI

/// Nino: Mac'in ağa kabloyla mı Wi-Fi'yle mi bağlı olduğu. İzin istemez (Wi-Fi adı ve sinyali için konum izni gerekir;
/// bilerek okunmaz).
final class NetworkWatcher: ObservableObject, @unchecked Sendable {
    static let shared = NetworkWatcher()

    @Published private(set) var kind: NetworkKind = .unknown
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let kind: NetworkKind
            if path.status != .satisfied { kind = .offline }
            else if path.usesInterfaceType(.wiredEthernet) { kind = .wired }
            else if path.usesInterfaceType(.wifi) { kind = .wifi }
            else { kind = .other }
            DispatchQueue.main.async { self?.kind = kind }
        }
        monitor.start(queue: DispatchQueue(label: "nino.network-watcher", qos: .utility))
    }
}

/// Ayarlar › Sistem sağlığı: her satır yeşil/sarı/kırmızı ve sorun varsa ne yapılacağı; altta bilen biri için ayrıntılar.
struct SystemHealthPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var network = NetworkWatcher.shared

    var body: some View {
        // Sayılar libchiaki'nin iş parçacığında birikir; ekran iki saniyede bir okur (AppModel'i her pakette yayınlamadan).
        TimelineView(.periodic(from: .now, by: 2)) { _ in
            let snapshot = HealthRecorder.shared.snapshot()
            VStack(alignment: .leading, spacing: Theme.space("gap")) {
                HealthChecksCard(snapshot: snapshot, network: network.kind)
                // TV uygulamasının kurulum adımları ve hatası ("Tekrar dene"); eskiden TV ve Ekran sayfasındaydı.
                TVAppCard()
                DeviceInfoCard()
                HealthDetailsCard(snapshot: snapshot, network: network.kind)
            }
        }
    }
}

private extension HealthLevel {
    var color: Color {
        switch self {
        case .unknown: .csSecondary
        case .good: .csSuccess
        case .warning: .csWarning
        case .problem: .csDanger
        }
    }

    var label: String {
        switch self {
        case .unknown: String(localized: "Not measured yet")
        case .good: String(localized: "Good")
        case .warning: String(localized: "Could be better")
        case .problem: String(localized: "Problem")
        }
    }
}

/// Bir sağlık satırı: nokta, ad, değer; sarı ya da kırmızıysa altında ne yapılacağı.
private struct HealthRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let level: HealthLevel
    let value: String
    var advice: String?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.space("m")) {
            TileIcon(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.space("s")) {
                    Text(title).font(.csBody.weight(.semibold))
                    Spacer(minLength: Theme.space("s"))
                    StatusDot(color: level.color)
                    Text(verbatim: level.label)
                        .font(.csCallout.weight(.semibold))
                        .foregroundStyle(level == .unknown ? Color.csSecondary : level.color)
                }
                Text(verbatim: value)
                    .font(.csCallout)
                    .foregroundStyle(Color.csSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let advice, level >= .warning {
                    Text(verbatim: advice)
                        .font(.csCallout)
                        .foregroundStyle(Color.csText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HealthChecksCard: View {
    @EnvironmentObject private var model: AppModel
    let snapshot: HealthSnapshot
    let network: NetworkKind

    var body: some View {
        let stream = HealthReport.stream(snapshot)
        Card {
            if snapshot.isEmpty {
                HintText(text: "Start translation and play for a few minutes; Nino measures the connection while you play.")
            } else if !snapshot.active {
                HintText(text: "Results of the last translation session. They are measured again when you start translation.")
            }
            HealthRow(symbol: network == .wired ? "cable.connector" : "wifi", title: "This Mac's network",
                      level: HealthReport.network(network, stream: stream), value: networkText,
                      advice: network == .offline
                        ? String(localized: "This Mac is not connected to a network. Connect it to the same modem as the PS5.")
                        : String(localized: "The PS5 picture is losing data. Connect this Mac to the modem with a cable (a USB-C Ethernet adapter works). If that is not possible, move closer to the modem and use 5 GHz Wi-Fi."))
            Divider()
            HealthRow(symbol: "gamecontroller", title: "PS5 connection", level: HealthReport.connection(snapshot),
                      value: connectionText, advice: connectionAdvice)
            Divider()
            HealthRow(symbol: "play.rectangle", title: "PS5 picture", level: stream, value: streamText,
                      advice: String(localized: "When the picture freezes, Nino cannot read the subtitles. Connect both the PS5 and this Mac to the modem with a cable."))
            Divider()
            HealthRow(symbol: "globe", title: "Translation speed", level: HealthReport.translation(snapshot),
                      value: translationText,
                      advice: model.onlineTranslationActive || model.settings.onlineEngine == .local
                        ? String(localized: "Translation is slow. Choose the Free engine in Settings › Translation and see whether it gets faster.")
                        : String(localized: "Translation is slow. Close other heavy apps on this Mac and try again."))
            Divider()
            HealthRow(symbol: "tv", title: "TV", level: tvLevel, value: tvText,
                      advice: String(localized: "The TV app is not connected. Open the Nino app on the TV and check that the TV is on the same network as this Mac."))
            if let app = tvAppRow {
                Divider()
                HealthRow(symbol: "square.and.arrow.down.on.square", title: "Nino TV app", level: app.level, value: app.value, advice: app.advice)
            }
        }
    }

    private var networkText: String {
        switch network {
        case .wired: String(localized: "Cable")
        case .wifi: String(localized: "Wi-Fi")
        case .other: String(localized: "Other connection")
        case .offline: String(localized: "No network")
        case .unknown: String(localized: "Checking…")
        }
    }

    private var connectionText: String {
        if snapshot.isEmpty { return String(localized: "Not started") }
        if snapshot.connects == 0 {
            return String(format: String(localized: "Could not connect (%d tries)"), snapshot.connectAttempts)
        }
        if snapshot.drops == 0 { return String(localized: "Connected, no drops") }
        return String(format: String(localized: "Dropped %d times while playing"), snapshot.drops)
    }

    private var connectionAdvice: String {
        switch snapshot.lastDisconnect {
        case "consoleAsleep": String(localized: "The PS5 is off or asleep. Turn it on, or turn on “Stay connected to the internet” in its rest mode settings.")
        case "inUse": String(localized: "Remote Play is being used on another device. Close it there.")
        case "loginPasscode": String(localized: "The second account has a PS5 login passcode. Remove it on the PS5.")
        case "remotePlayDisabled": String(localized: "Remote Play is turned off on the PS5. On the PS5, open Settings › System › Remote Play and turn on Enable Remote Play, then start again.")
        case "registrationInvalid", "refused": String(localized: "The PS5 did not accept this Mac. Pair the PS5 again from Settings › About Nino › Set up again.")
        case "notFound": String(localized: "The PS5 did not answer on the network. Check that it is on (or in rest mode) and on the same network as this Mac.")
        default: String(localized: "The connection to the PS5 keeps dropping. Connect both the PS5 and this Mac to the modem with a cable.")
        }
    }

    private var streamText: String {
        guard let loss = snapshot.lossPerMinute, let stalls = snapshot.stallsPerMinute else {
            return snapshot.isEmpty ? String(localized: "Not started") : String(localized: "Measuring…")
        }
        return String(format: String(localized: "%1$@ lost packets and %2$@ freezes per minute"),
                      loss.formatted(.number.precision(.fractionLength(0))),
                      stalls.formatted(.number.precision(.fractionLength(1))))
    }

    private var translationText: String {
        guard let median = snapshot.translationMedianMs else {
            return snapshot.isEmpty ? String(localized: "Not started") : String(localized: "No line translated yet")
        }
        let seconds = (Double(median) / 1000).formatted(.number.precision(.fractionLength(1)))
        return String(format: String(localized: "%1$@ s per line (%2$d lines)"), seconds, snapshot.translations)
    }

    private var tvLevel: HealthLevel {
        guard model.isRunning, model.showsOnTV else { return .unknown }
        return model.tvClients > 0 ? .good : .problem
    }

    private var tvText: String {
        if !model.showsOnTV { return String(localized: "Subtitles are not sent to a TV") }
        if !model.isRunning { return String(localized: "Not started") }
        return model.tvClients > 0 ? String(localized: "Connected") : String(localized: "Not connected")
    }

    /// TV uygulamasının kurulum durumu; yapılacak bir şey yoksa satır görünmez.
    private var tvAppRow: (level: HealthLevel, value: String, advice: String?)? {
        let brand = model.tv?.brand ?? .lg
        switch model.tvApp {
        case .unknown, .working, .signIn, .needsPassphrase: return nil
        case .upToDate(let version):
            return (.good, String(format: String(localized: "Installed (version %@)"), version), nil)
        case .approveOnTV:
            return (.warning, String(localized: "Waiting for approval on the TV"),
                    String(localized: "Look at the TV: tick “Always allow from this computer” and choose Allow."))
        case .devModeOff:
            return (.warning, String(localized: "Not installed"),
                    String(localized: "Turn on developer mode on the TV (Settings › TV and screen shows how)."))
        case .failed(let error, let reason):
            return (.problem, String(localized: "Could not be installed"), TVAppCard.message(for: error, brand: brand, reason: reason))
        case .hostPcMismatch(let tvIp, let computer):
            return (.warning, String(localized: "Not installed"),
                    String(format: String(localized: "The TV has another address as Host PC IP (%1$@), so it does not accept this computer. Change it to %2$@."), tvIp, computer))
        }
    }
}

/// Nino: "Cihaz bilgileri". Kullanıcının ne kullandığı (uygulama, Mac modeli, sistem, TV, konsol); aynı özet Sorun
/// Bildir ve Nino'ya Sor bildirimlerine eklenir.
private struct DeviceInfoCard: View {
    @EnvironmentObject private var model: AppModel
    @State private var copied = false

    var body: some View {
        Card(title: "Device info") {
            VStack(alignment: .leading, spacing: Theme.space("s")) {
                ForEach(model.deviceRows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.space("m")) {
                        Text(Self.label(row.id)).font(.csBody).foregroundStyle(Color.csSecondary)
                            .frame(width: 150, alignment: .leading)
                        Text(verbatim: row.value).font(.csBody).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                HStack(spacing: Theme.space("s")) {
                    Button(copied ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy device info")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.deviceSummary, forType: .string)
                        copied = true
                    }
                    .buttonStyle(.secondary)
                    Spacer()
                }
                .padding(.top, Theme.space("s"))
                HintText(text: "Added to your problem reports so we can see what you use without asking. It contains no names, serial numbers or addresses.")
            }
        }
    }

    static func label(_ id: String) -> LocalizedStringKey {
        switch id {
        case "app": "App version"
        case "device": "Device model"
        case "system": "Operating system"
        case "tv": "TV"
        case "console": "Console"
        default: "Current status"
        }
    }
}

/// Ayrıntılar: sorunu çözecek biri için ham sayılar ve son günlük satırları; kopyalanır ya da kayıtlar zip olarak kaydedilir.
private struct HealthDetailsCard: View {
    @EnvironmentObject private var model: AppModel
    let snapshot: HealthSnapshot
    let network: NetworkKind
    @State private var expanded = false
    @State private var copied = false
    @State private var exportError: String?

    var body: some View {
        Card {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: Theme.space("m")) {
                    ScrollView {
                        Text(verbatim: details)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Theme.space("m"))
                    }
                    .frame(height: 260)
                    .background(Color.csSurface2, in: RoundedRectangle(cornerRadius: Theme.radius("tag"), style: .continuous))
                    HStack(spacing: Theme.space("s")) {
                        Button(copied ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy details")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(details, forType: .string)
                            copied = true
                        }
                        .buttonStyle(.secondary)
                        Button("Save logs as zip") { saveLogs() }.buttonStyle(.secondary)
                        Spacer()
                    }
                    ErrorText(error: exportError)
                    HintText(text: "If something does not work, send the zip to whoever helps you. The logs contain the subtitles Nino read, the PS5's name and its address on your home network, but no password, key or account information.")
                }
                .padding(.top, Theme.space("m"))
            } label: {
                // Yalnız ok değil, başlığın tamamı açıp kapatır.
                Text("Details").font(.csHeadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation { expanded.toggle() } }
            }
        }
        .onChange(of: expanded) { _ in copied = false }
    }

    private var details: String {
        let tvApp: String
        switch model.tvApp {
        case .unknown: tvApp = "bilinmiyor"
        case .working: tvApp = "kuruluyor"
        case .upToDate(let version): tvApp = "kurulu \(version)"
        case .devModeOff: tvApp = "geliştirici modu kapalı"
        case .needsPassphrase: tvApp = "parola bekleniyor"
        case .failed(let error, let reason): tvApp = "hata \(error)" + (reason.map { " (\($0))" } ?? "")
        case .signIn: tvApp = "Samsung girişi bekleniyor"
        case .approveOnTV: tvApp = "TV'de onay bekleniyor"
        case .hostPcMismatch(let tvIp, let computer): tvApp = "Host PC IP uyuşmuyor (TV'de \(tvIp), bu Mac \(computer))"
        }
        // Ayrıntılar destek içindir, Türkçe ve sabit kalır (ekran dili değişse de).
        let running = model.isRunning ? Self.runningText : Self.stoppedText
        let lines: [String?] = [
            "Nino \(AppIdentity.version), macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(Self.chip), "
                + "\(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) GB",
            "motor: \(model.onlineTranslationActive ? model.settings.onlineEngine.rawValue : "ücretsiz"), "
                + "çeviri: \(running), PS5: \(model.sessionState)",
            "TV: \(model.tv.map { "\($0.brand)" } ?? "yok"), bağlı TV uygulaması \(model.tvClients), TV uygulaması: \(tvApp)",
            model.samsungSetup.map { "Samsung denetimi: geliştirici modu \($0.info?.developerMode.map { $0 ? "açık" : "kapalı" } ?? "?"), "
                + "TV'deki Host PC IP \($0.info?.developerIp ?? "?"), bu Mac \($0.computer ?? "?"), "
                + "kurulum kapısı \($0.portOpen ? "açık" : "kapalı"), eksik adım: \($0.problem.map { "\($0)" } ?? "yok")" },
            HealthReport.summary(snapshot, network: network),
            "",
            "— altyazi.log (son satırlar) —",
            Self.tail(of: SubtitleLog.defaultFile, lines: 40),
            "",
            "— tvinstall.log (son satırlar) —",
            Self.tail(of: TVInstallLog.file, lines: 8),
        ]
        return lines.compactMap { $0 }.joined(separator: "\n")
    }

    private static let runningText = "sürüyor"
    private static let stoppedText = "durdu"

    static var chip: String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else { return "?" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else { return "?" }
        return String(cString: buffer)
    }

    /// Dosyanın son satırları (dosya yoksa "-"); en çok son 64 KB okunur.
    static func tail(of file: URL, lines count: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return "-" }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: end > 65_536 ? end - 65_536 : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return "-" }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.suffix(count).joined(separator: "\n")
    }

    /// Yalnız günlük dosyalarını (altyazi.log, remoteplay.log, tvinstall.log ve .1 yedekleri) ve ayrıntıları zip'ler;
    /// aynı klasördeki ses kayıtları ve görüntü kareleri girmez (onlarla zip 70 MB'ı buluyordu). İndirilenler'e
    /// (yazılamıyorsa geçici klasöre) koyar ve Finder'da gösterir.
    private func saveLogs() {
        exportError = nil
        SubtitleLog.flush()
        let logs = SubtitleLog.defaultFile.deletingLastPathComponent()
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let name = "Nino-kayitlar-\(stamp).zip"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Nino-kayitlar-\(stamp)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent.contains(".log") {
                try FileManager.default.copyItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
            }
            try details.write(to: folder.appendingPathComponent("ayrintilar.txt"), atomically: true, encoding: .utf8)
        } catch {
            exportError = String(localized: "The logs could not be saved.") + " (\(error.localizedDescription))"
            return
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        var coordinatorError: NSError?
        var saved: URL?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { zip in
            for target in [downloads, FileManager.default.temporaryDirectory].compactMap({ $0?.appendingPathComponent(name) }) {
                do {
                    try? FileManager.default.removeItem(at: target)
                    try FileManager.default.copyItem(at: zip, to: target)
                    saved = target
                    return
                } catch {
                    copyError = error
                }
            }
        }
        if let saved {
            NSWorkspace.shared.activateFileViewerSelecting([saved])
        } else {
            exportError = String(localized: "The logs could not be saved.")
                + ((coordinatorError ?? copyError).map { " (\($0.localizedDescription))" } ?? "")
        }
    }
}
