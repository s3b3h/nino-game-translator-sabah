import CoreGraphics
import ImageIO
import XCTest
@testable import CouchSubsCore

final class PhonePanelTests: XCTestCase {
    /// 240×135 haritada telefonun ekranı: x 139–190, y 27–115 (gerçek karelerdeki yer).
    private func phone(_ x: Int, _ y: Int) -> Bool { (139...190).contains(x) && (27...115).contains(y) }

    /// Beyaz olmayan her nokta koyu (karanlık sahne).
    private func find(_ isWhite: @escaping (Int, Int) -> Bool) -> TextBox? {
        PhonePanel.find(width: 240, height: 135, isWhite: isWhite, isDark: { !isWhite($0, $1) })?.box
    }

    private func panel(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> PhonePanel.Panel {
        PhonePanel.Panel(box: TextBox(left: left, top: top, right: right, bottom: bottom), topLeft: left, lean: 0, width: right - left)
    }

    /// Yaya hâlde telefon eğik tutulur (gerçek karede: sol kenar 81 satırda 13 nokta sola kayar); yine bulunur.
    func testLeaningPanelIsFound() throws {
        let found = try XCTUnwrap(PhonePanel.find(width: 240, height: 135, isWhite: { x, y in
            guard (24...105).contains(y) else { return false }
            let left = 99 - Int((Double(y - 24) * 0.16).rounded())
            return x >= left && x <= left + 45
        }, isDark: { _, _ in true }))
        XCTAssertEqual(found.lean * 240 / 135, -0.16, accuracy: 0.03)
        XCTAssertEqual(found.box.top, 24.0 / 135, accuracy: 0.01)
        XCTAssertEqual(found.box.bottom, 106.0 / 135, accuracy: 0.01)
        XCTAssertEqual(found.center(at: found.box.top), (99 + 23) / 240.0, accuracy: 0.012)
        XCTAssertEqual(found.center(at: found.box.bottom), (86 + 23) / 240.0, accuracy: 0.012)
    }

    func testFindsWhitePortraitPanel() throws {
        let box = try XCTUnwrap(find { self.phone($0, $1) })
        XCTAssertEqual(box.left, 139.0 / 240, accuracy: 0.01)
        XCTAssertEqual(box.right, 191.0 / 240, accuracy: 0.01)
        XCTAssertEqual(box.top, 27.0 / 135, accuracy: 0.01)
        XCTAssertEqual(box.bottom, 116.0 / 135, accuracy: 0.01)
    }

    /// Sohbetteki fotoğraf ve mavi balonlar bazı satırları böler; ekran yine bulunur.
    func testPanelWithPhotoAndBubblesIsStillFound() {
        let found = find { x, y in
            guard self.phone(x, y) else { return false }
            if (40...75).contains(y), (144...185).contains(x) { return false }
            if (95...108).contains(y), (160...186).contains(x) { return false }
            return true
        }
        XCTAssertNotNil(found)
    }

    /// Çerçevesi koyu olmayan beyaz dikdörtgen (açık renk duvardaki kapı, pano) telefon değildir.
    func testPanelWithoutDarkBezelIsNotAPhone() {
        XCTAssertNil(PhonePanel.find(width: 240, height: 135, isWhite: { self.phone($0, $1) }, isDark: { _, _ in false }))
    }

    /// Gerçek karelerden: karenin solundaki aydınlık duvar (x 12–65, y 7–88) ve üst kenara dayanan kapı telefon değildir.
    func testLitWallAtTheEdgeIsNotAPhone() {
        XCTAssertNil(find { x, y in (12...65).contains(x) && (7...88).contains(y) })
        XCTAssertNil(find { x, y in (100...150).contains(x) && (0...68).contains(y) })
    }

    func testDarkSceneHasNoPanel() {
        XCTAssertNil(find { _, _ in false })
    }

    /// Parlak gökyüzü (karenin üst yarısı baştan sona beyaz) telefon değildir.
    func testSkyIsNotAPanel() {
        XCTAssertNil(find { _, y in y < 70 })
    }

    /// Yatay beyaz kutu (SMS kartı, tabela) telefon değildir.
    func testWideBoxIsNotAPanel() {
        XCTAssertNil(find { x, y in (150...220).contains(x) && (110...134).contains(y) })
    }

    /// Kenarları satırdan satıra oynayan beyaz leke (bulut, duvar) telefon değildir.
    func testRaggedBlobIsNotAPanel() {
        XCTAssertNil(find { x, y in
            (20...120).contains(y) && x >= 100 + (y * 7) % 23 && x <= 150 + (y * 11) % 29
        })
    }

    private func line(_ text: String, _ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> TextLine {
        TextLine(text, box: TextBox(left: left, top: top, right: right, bottom: bottom))
    }

    private var panel: PhonePanel.Panel { panel(0.58, 0.197, 0.793, 0.854) }

    func testThreadMessagesAreGroupedAndLabelsSkipped() {
        let reading = Reading(lines: [
            line("Kenton", 0.66, 0.22, 0.70, 0.24),
            line("Nuestra Señora del Ocio", 0.63, 0.295, 0.755, 0.315),
            line("Dropped off scuba to yuh boat", 0.60, 0.372, 0.752, 0.394),
            line("man. Happy hunting!", 0.60, 0.398, 0.70, 0.42),
            line("New message", 0.648, 0.503, 0.718, 0.522),
            line("Still can't believe u found them", 0.60, 0.558, 0.753, 0.58),
            line("doubloons. U got that luck boy.", 0.60, 0.582, 0.754, 0.604),
            line("Need u out there on these", 0.60, 0.607, 0.731, 0.629),
            line("wrecks man.", 0.60, 0.632, 0.662, 0.652),
            line("Yeah, I'm on it man.", 0.667, 0.689, 0.766, 0.712),
        ])
        let messages = PhoneThread.messages(in: reading, panel: panel)
        XCTAssertEqual(messages.map(\.text), [
            "Dropped off scuba to yuh boat man. Happy hunting!",
            "Still can't believe u found them doubloons. U got that luck boy. Need u out there on these wrecks man.",
            "Yeah, I'm on it man.",
        ])
    }

    func testThreadHasCenteredNameOnTop() {
        let thread = Reading(lines: [line("Kenton", 0.653, 0.233, 0.690, 0.248),
                                     line("Hey Jason! Was good meeting u", 0.595, 0.351, 0.750, 0.377)])
        XCTAssertTrue(PhoneThread.isThread(thread, panel: panel(0.575, 0.215, 0.783, 0.859)))
    }

    /// Mesaj listesi (en üstte sola yaslı "Suggested" ya da kişi adı) sohbet değildir; çevrilmez.
    func testListIsNotAThread() {
        let list = Reading(lines: [
            line("Suggested", 0.608, 0.230, 0.661, 0.249),
            line("Donnie", 0.635, 0.272, 0.669, 0.285), line("Go get em", 0.635, 0.297, 0.685, 0.313),
            line("Chuck's Gun Shop", 0.634, 0.347, 0.725, 0.367), line("Hey Jason. You good? I saw", 0.634, 0.371, 0.772, 0.391),
        ])
        XCTAssertFalse(PhoneThread.isThread(list, panel: panel(0.583, 0.207, 0.792, 0.852)))
    }

    func testAttachmentLabelsAreNotMessages() {
        let reading = Reading(lines: [
            line("Kenton", 0.653, 0.233, 0.690, 0.248),
            line("Messages encrypted", 0.620, 0.296, 0.734, 0.322),
            line("Map Pin Expired", 0.624, 0.478, 0.707, 0.496),
            line("Here r the spots man. These", 0.595, 0.557, 0.736, 0.576),
            line("wrecks should be a good place", 0.595, 0.581, 0.747, 0.602),
            line("Nuestra Señora de la", 0.626, 0.646, 0.734, 0.665),
            line("Ética Laxa", 0.625, 0.668, 0.681, 0.694),
        ])
        let messages = PhoneThread.messages(in: reading, panel: panel(0.575, 0.215, 0.783, 0.859))
        XCTAssertEqual(messages.map(\.text), ["Here r the spots man. These wrecks should be a good place"])
    }

    /// Telefon sağdaysa (araçta) Türkçeler soluna, ortada ya da soldaysa sağına konur.
    func testColumnGoesToTheRoomierSide() {
        let left = PhoneThread.column(beside: panel)
        XCTAssertLessThan(left.right, panel.box.left)
        let right = PhoneThread.column(beside: panel(0.39, 0.2, 0.61, 0.85))
        XCTAssertGreaterThan(right.left, 0.61)
        XCTAssertLessThanOrEqual(right.right, 0.98)
    }

    func testBoxesDoNotOverlap() {
        let messages = [PhoneThread.Message(text: "a", box: TextBox(left: 0.6, top: 0.40, right: 0.7, bottom: 0.42), lineHeight: 0.022),
                        PhoneThread.Message(text: "b", box: TextBox(left: 0.6, top: 0.43, right: 0.7, bottom: 0.45), lineHeight: 0.022)]
        let boxes = PhoneThread.boxes(for: messages, lineCounts: [3, 1], lineHeights: [0.02, 0.02], column: (0.2, 0.5))
        XCTAssertGreaterThanOrEqual(boxes[1].top, boxes[0].bottom)
    }

    /// Elle: NINO_FRAME klasöründeki gerçek karelerde telefonu arar ve okunan mesajları yazdırır.
    func testProbeRealFrames() throws {
        guard let path = ProcessInfo.processInfo.environment["NINO_FRAME"] else { throw XCTSkip("NINO_FRAME yok") }
        let files = try FileManager.default.contentsOfDirectory(atPath: path).filter { $0.hasSuffix(".jpg") }.sorted()
        for file in files {
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path + "/" + file) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            guard let found = PhonePanel.find(in: image) else { print("TELEFON", file, "yok"); continue }
            let box = found.box
            print("TELEFON", file, String(format: "%.3f %.3f %.3f %.3f eğim %.3f", box.left, box.top, box.right, box.bottom, found.lean))
            guard ProcessInfo.processInfo.environment["NINO_READ"] != nil else { continue }
            let region = CropRegion(top: box.top, bottom: box.bottom, left: box.left, right: box.right)
            let reading = try VisionReader(language: "en").readLines(RegionCropper.crop(image, to: region), deep: false)
                .placed(in: box)
            if ProcessInfo.processInfo.environment["NINO_READ"] == "2" {
                for line in reading.lines {
                    guard let b = line.box else { continue }
                    print("   SATIR", String(format: "%.3f %.3f %.3f %.3f", b.left, b.top, b.right, b.bottom), line.text)
                }
            }
            if !PhoneThread.isThread(reading, panel: found) { print("   SOHBET DEĞİL"); continue }
            for message in PhoneThread.messages(in: reading, panel: found) {
                print("   MESAJ", String(format: "%.3f–%.3f", message.box.top, message.box.bottom), message.text)
            }
        }
    }
}

/// Nino (GTA 6, 20 Kasım 2026): gerçek karelerden küçültülmüş örnekler. Gümüş çerçeveli telefon hiç bulunamıyordu:
/// sohbet mesajları altyazı sanılıp siyah kutuda çıkıyor, son balon "yeni mesaj" bildirimi sanılıp telefonun üstüne
/// yazılıyordu. Kenton'da telefonun üstündeki pencere, listede de resimler algılamayı bozuyordu.
final class RealPhoneFrameTests: XCTestCase {
    private func frame(_ name: String) throws -> CGImage {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil)?.appendingPathComponent(name))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    func testSilverPhoneIsFoundInEveryFrame() throws {
        for name in ["gta6-telefon-donnie.jpg", "gta6-telefon-kenton.jpg", "gta6-telefon-shirley.jpg", "gta6-telefon-liste.jpg"] {
            let panel = try XCTUnwrap(PhonePanel.find(in: try frame(name)), name)
            // Telefonun ekranı karede x ≈ 0.59–0.79, y ≈ 0.20–0.82.
            XCTAssertEqual(panel.box.left, 0.59, accuracy: 0.02, name)
            XCTAssertEqual(panel.box.right, 0.79, accuracy: 0.02, name)
            XCTAssertEqual(panel.box.top, 0.20, accuracy: 0.03, name)
            XCTAssertEqual(panel.box.bottom, 0.82, accuracy: 0.03, name)
        }
    }

    /// Telefon eğilip aşağı indirilince ekranın alt kenarından taşar; yine telefondur (bulunmayınca içindeki yazı
    /// altyazı ve mesaj kartı sanılıyordu).
    func testTiltedPhoneCutByTheBottomEdgeIsFound() throws {
        let panel = try XCTUnwrap(PhonePanel.find(in: try frame("gta6-telefon-egik-alt.jpg")))
        XCTAssertEqual(panel.box.top, 0.58, accuracy: 0.03)
        XCTAssertGreaterThan(panel.box.bottom, 0.96)
        XCTAssertEqual((panel.box.left + panel.box.right) / 2, 0.52, accuracy: 0.03)
    }
}

/// Nino (kullanıcı isteği, 20 Kasım 2026): mesajların Türkçesi balonun tam üstünde, balonun rengiyle; telefon
/// sallanınca örtüler onunla kayar.
final class PhoneCoverTests: XCTestCase {
    private let panel = PhonePanel.Panel(box: TextBox(left: 0.59, top: 0.2, right: 0.79, bottom: 0.81), topLeft: 0.59, lean: 0, width: 0.2)

    func testTranslationCoversTheBubbleInItsColour() {
        let messages = [PhoneThread.Message(text: "On my way", box: TextBox(left: 0.61, top: 0.5, right: 0.7, bottom: 0.53), lineHeight: 0.02),
                        PhoneThread.Message(text: "Casa De Donnie", box: TextBox(left: 0.61, top: 0.6, right: 0.7, bottom: 0.63), lineHeight: 0.02)]
        // Balonun içi açık gri; yazının üstü koyu (en aydınlık nokta alınır).
        let items = PhoneThread.covers(for: messages, translations: ["Geliyorum", "Casa De Donnie"]) { x, _ in
            x < 0.6075 ? (233, 233, 236) : (40, 40, 40)
        }
        XCTAssertEqual(items.count, 1, "çevirisi aslıyla aynı olan (ad) örtülmez")
        XCTAssertEqual(items[0].fill, "#e9e9ec")
        XCTAssertEqual(items[0].ink, "#2c2c2e")
        XCTAssertLessThan(items[0].box.left, 0.61)
        XCTAssertGreaterThan(items[0].box.right, 0.7)
        XCTAssertLessThan(items[0].box.top, 0.5)
        XCTAssertGreaterThan(items[0].box.bottom, 0.53)
    }

    /// Eğik telefon: aşağı indikçe sol kenar sola kayıyorsa telefon saat yönünde dönmüştür; örtüler de aynı açıyla.
    func testTiltedPhoneTiltsTheCovers() {
        let tilted = PhonePanel.Panel(box: panel.box, topLeft: 0.6, lean: -0.1, width: 0.2)
        XCTAssertEqual(tilted.angle, atan(0.1 * 16 / 9) * 180 / .pi, accuracy: 1e-9)
        XCTAssertGreaterThan(tilted.angle, 9)
        let message = PhoneThread.Message(text: "On my way", box: TextBox(left: 0.61, top: 0.5, right: 0.7, bottom: 0.53), lineHeight: 0.02)
        let items = PhoneThread.covers(for: [message], translations: ["Geliyorum"], angle: tilted.angle) { _, _ in (233, 233, 236) }
        XCTAssertEqual(items[0].angle ?? 0, tilted.angle, accuracy: 1e-9)
        XCTAssertEqual(panel.angle, 0, accuracy: 1e-9)
    }

    /// Kullanıcı isteği: Türkçe telefonun yanında, telefon boyunda dikey bir mesajlaşma panelinde; gelen solda, giden sağda.
    func testSideBubblesFormAChatPanelBesideThePhone() {
        let messages = [PhoneThread.Message(text: "On my way", box: TextBox(left: 0.61, top: 0.5, right: 0.7, bottom: 0.53), lineHeight: 0.02),
                        PhoneThread.Message(text: "Where at?", box: TextBox(left: 0.72, top: 0.6, right: 0.77, bottom: 0.62), lineHeight: 0.02)]
        let items = PhoneThread.sideBubbles(for: messages, translations: ["Geliyorum", "Nerede?"], panel: panel,
                                            color: { x, _ in x < 0.7 ? (233, 233, 236) : (200, 220, 245) },
                                            lines: { text, _, _ in (1, text.count) })
        XCTAssertEqual(items.count, 3)
        let backdrop = items[0]
        XCTAssertTrue(backdrop.backdrop)
        XCTAssertEqual(backdrop.box.top, panel.box.top, accuracy: 1e-9, "telefon boyunda")
        XCTAssertEqual(backdrop.box.bottom, panel.box.bottom, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(backdrop.box.right, panel.box.left, "telefonun solundaki boşlukta")
        let incoming = items[1], outgoing = items[2]
        for item in [incoming, outgoing] {
            XCTAssertTrue(item.side)
            XCTAssertGreaterThanOrEqual(item.box.left, backdrop.box.left)
            XCTAssertLessThanOrEqual(item.box.right, backdrop.box.right)
            XCTAssertNil(item.angle)
        }
        XCTAssertEqual(incoming.box.top, 0.5, accuracy: 0.001, "mesajın hizasında")
        XCTAssertLessThan(incoming.box.left, outgoing.box.left, "gelen solda, giden sağda")
        XCTAssertEqual(incoming.fill, "#f8f8f9")
        XCTAssertEqual(outgoing.fill, "#acccfe", "giden mesajın mavi balonu")
        // Uzun giden mesaj telefonun genişliğini kaplar; yerinden değil, sohbetin gri balonundan daha mavi olmasından anlaşılır.
        // Işık bütün balonları mavimsi gösterse de (gelen "#899ab7") en gri balon gelen sayılır.
        let gray = PhoneThread.Message(text: "Honestly if they didn't let us", box: TextBox(left: 0.61, top: 0.4, right: 0.77, bottom: 0.43), lineHeight: 0.02)
        let long = PhoneThread.Message(text: "No go. Cal's tryin to avoid that chick", box: TextBox(left: 0.61, top: 0.5, right: 0.77, bottom: 0.53), lineHeight: 0.02)
        let tinted = PhoneThread.sideBubbles(for: [gray, long], translations: ["Dürüst olmak gerekirse", "Yok, olmaz."], panel: panel,
                                             color: { _, y in y < 0.45 ? (137, 154, 183) : (120, 150, 215) }, lines: { text, _, _ in (1, text.count) })
        XCTAssertEqual(tinted[1].box.left, tinted[0].box.left + 0.012, accuracy: 1e-9, "mavimsi ışıktaki gelen balon solda")
        XCTAssertEqual(tinted[2].box.right, tinted[0].box.right - 0.012, accuracy: 1e-9, "belirgin mavi balon sağa yaslı")
    }

    func testCoversFollowThePhone() {
        var item = ScreenTranslation.Item(source: "a", translation: "b", box: TextBox(left: 0.6, top: 0.5, right: 0.7, bottom: 0.52), lineHeight: 0.02)
        item.fill = "#ffffff"
        let moved = PhoneThread.shifted([item], dx: 0.01, dy: -0.02)[0]
        XCTAssertEqual(moved.box.left, 0.61, accuracy: 1e-9)
        XCTAssertEqual(moved.box.top, 0.48, accuracy: 1e-9)
        XCTAssertEqual(moved.fill, "#ffffff")
    }
}

/// Nino: telefon açıkken altyazı bölgesindeki telefon kısmı okunmadan siyaha boyanır.
final class PhoneMaskTests: XCTestCase {
    func testPhoneAreaIsBlackenedInsideTheRegion() throws {
        let w = 200, h = 100
        let context = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let area = try XCTUnwrap(context.makeImage())
        let region = CropRegion(top: 0.5, bottom: 1, left: 0, right: 1)
        // Telefon karenin sağ yarısında, bölgenin üst yarısına giriyor.
        let masked = RegionCropper.masking(area, box: TextBox(left: 0.5, top: 0.2, right: 0.8, bottom: 0.75), in: region, margin: 0)
        func pixel(_ x: Int, _ y: Int) -> UInt8 {
            var p = [UInt8](repeating: 0, count: 4)
            let c = CGContext(data: &p, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            c.draw(masked.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return p[0]
        }
        XCTAssertEqual(pixel(130, 10), 0, "telefonun bölgedeki kısmı siyah")
        XCTAssertEqual(pixel(130, 80), 255, "telefonun altı (bölgenin alt yarısı) beyaz kalır")
        XCTAssertEqual(pixel(20, 10), 255, "telefonun solu beyaz kalır")
    }
}

/// Nino: başlığı virgüllü yer adı olan sohbet ("Fleeca, Laguna Lane") de sohbettir.
final class PhoneThreadTitleTests: XCTestCase {
    func testPlaceNameWithCommaIsAThreadTitle() {
        let panel = PhonePanel.Panel(box: TextBox(left: 0.59, top: 0.2, right: 0.79, bottom: 0.81), topLeft: 0.59, lean: 0, width: 0.2)
        let reading = Reading(lines: [
            TextLine("Fleeca, Laguna Lane", box: TextBox(left: 0.64, top: 0.21, right: 0.74, bottom: 0.23)),
            TextLine("Hello Mr. Duval. Please see the", box: TextBox(left: 0.61, top: 0.55, right: 0.76, bottom: 0.57)),
        ])
        XCTAssertTrue(PhoneThread.isThread(reading, panel: panel))
    }
}

/// Nino: sohbet olmayan telefon uygulamasında (BuckMe) her satır ayrı çevrilir; harfsiz satır ve satır başı simgesi alınmaz;
/// panel uygulamanın Türkçe kopyası gibi, satırlar telefondaki yatay yerlerinde.
final class PhoneAppScreenTests: XCTestCase {
    func testAppLinesSkipNumbersAndIcons() {
        let panel = PhonePanel.Panel(box: TextBox(left: 0.59, top: 0.2, right: 0.79, bottom: 0.81), topLeft: 0.59, lean: 0, width: 0.2)
        let reading = Reading(lines: [
            TextLine("$500", box: TextBox(left: 0.70, top: 0.33, right: 0.77, bottom: 0.36)),
            TextLine("◆ Checking Account", box: TextBox(left: 0.61, top: 0.38, right: 0.72, bottom: 0.40)),
            TextLine("$4,900 to next goal", box: TextBox(left: 0.64, top: 0.65, right: 0.74, bottom: 0.67)),
        ])
        let lines = PhoneThread.appLines(in: reading, panel: panel)
        XCTAssertEqual(lines.map(\.text), ["Checking Account", "$4,900 to next goal"])
        let items = PhoneThread.sideBubbles(for: lines, translations: ["Vadesiz Hesap", "Sonraki hedefe $4.900"], panel: panel, chat: false,
                                            color: { _, y in y < 0.5 ? (155, 80, 187) : (233, 233, 236) }, lines: { t, _, _ in (1, t.count) })
        XCTAssertEqual(items.count, 3)
        XCTAssertLessThan(items[1].box.left, items[2].box.left, "telefondaki gibi: içeride başlayan satır panelde de içeride")
        XCTAssertEqual(items[1].ink, "#f5f5f7", "mor kartın üstünde beyaz yazı")
    }
}

final class PhoneWorthShowingTests: XCTestCase {
    func testBrandNamesAreNotShown() {
        XCTAssertFalse(PhoneThread.worthShowing(source: "buckme", translation: "BuckMe mi?"))
        XCTAssertTrue(PhoneThread.worthShowing(source: "Checking Account", translation: "Vadesiz Hesap"))
    }
}

final class PhoneGlossaryTests: XCTestCase {
    func testBankTermsHaveFixedTurkish() {
        XCTAssertEqual(PhoneThread.glossary("Checking Account"), "Vadesiz Hesap")
        XCTAssertEqual(PhoneThread.glossary("Family Savings"), "Aile Birikimi")
        XCTAssertEqual(PhoneThread.glossary("$4,900 to next goal"), "Sonraki hedefe $4.900")
        XCTAssertNil(PhoneThread.glossary("Are you high right now?"))
        XCTAssertEqual(PhoneThread.glossary("Book Ryde ($82)"), "Ryde Çağır ($82)")
        XCTAssertEqual(PhoneThread.glossary("Trip Details"), "Yolculuk Bilgileri")
        XCTAssertEqual(PhoneThread.glossary("Level 3/4"), "Seviye 3/4")
        XCTAssertEqual(PhoneThread.glossary("Cardio Workout"), "Kardiyo Antrenmanı")
        XCTAssertEqual(PhoneThread.glossary("Muscle - High"), "Kas - Yüksek")
        XCTAssertEqual(PhoneThread.glossary("Body Fat - Low"), "Vücut Yağı - Düşük")
        XCTAssertEqual(PhoneThread.glossary("Ripped"), "Kaslı")
        XCTAssertEqual(PhoneThread.glossary("Muscle High"), "Kas - Yüksek")
        XCTAssertTrue(PhoneThread.isPhoneUI("Body Fat Low"))
    }

    func testAppLabelsAreNotSentences() {
        XCTAssertFalse(PhoneThread.isSentence("Book Ryde ($82)"))
        XCTAssertFalse(PhoneThread.isSentence("Righto Cash & Carry"))
        XCTAssertFalse(PhoneThread.isSentence("1.74 mi"))
        XCTAssertTrue(PhoneThread.isSentence("Thx amigo! U find anything else"))
        XCTAssertTrue(PhoneThread.isSentence("Are you high right now?"))
        XCTAssertTrue(PhoneThread.isSentence("Dropped off scuba to yuh boat man"))
    }
}

final class PhoneAppBubbleTests: XCTestCase {
    func testAppBubblesUseTheAppColourBesideThePhone() {
        let panel = PhonePanel.Panel(box: TextBox(left: 0.59, top: 0.2, right: 0.79, bottom: 0.81), topLeft: 0.59, lean: 0, width: 0.2)
        let lines = [PhoneThread.Message(text: "Checking Account", box: TextBox(left: 0.61, top: 0.38, right: 0.72, bottom: 0.40), lineHeight: 0.02),
                     PhoneThread.Message(text: "buckme", box: TextBox(left: 0.61, top: 0.28, right: 0.66, bottom: 0.30), lineHeight: 0.02)]
        let items = PhoneThread.appBubbles(for: lines, translations: ["Vadesiz Hesap", "BuckMe mi?"], panel: panel) { _, y in
            y < 0.45 ? (155, 80, 187) : (233, 233, 236)
        }
        XCTAssertEqual(items.map(\.translation), ["Vadesiz Hesap"])
        XCTAssertEqual(items[0].fill, "#9b50bb", "uygulamanın moru")
        XCTAssertEqual(items[0].ink, "#ffffff")
        XCTAssertLessThan(items[0].box.right, panel.box.left, "telefonun solunda")
        XCTAssertEqual((items[0].box.top + items[0].box.bottom) / 2, 0.39, accuracy: 0.002, "satırın hizasında")
    }
}

/// Nino: koyu temalı telefon uygulaması (Rydeme) da telefondur; koyu kıyafet (yazısız koyu dikdörtgen) değildir.
final class DarkPhoneTests: XCTestCase {
    func testDarkThemedAppIsFoundButDarkClothesAreNot() throws {
        let dark = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-telefon-koyu-rydeme.jpg"))
        let panel = try XCTUnwrap(PhonePanel.find(in: dark))
        XCTAssertEqual((panel.box.left + panel.box.right) / 2, 0.69, accuracy: 0.03)
        let menu = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-menu-kapusonlu.jpg"))
        XCTAssertNil(PhonePanel.find(in: menu), "Lucia'nın kapüşonlusu telefon değil")
    }
}

enum RealPhoneFrameTestsHelper {
    static func frame(_ name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil)?.appendingPathComponent(name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

final class PhoneMessageListTests: XCTestCase {
    func testAppScreenWithTitleCaseRowsIsNotAMessageList() {
        let app = Reading(lines: ["Righto Cash & Carry", "Standard Ryde", "Choose Ryde", "Change Destination"].map { TextLine($0) })
        XCTAssertFalse(PhoneThread.isMessageList(app))
        let list = Reading(lines: ["Donnie", "You got my plane?! You be...", "Brian", "Remember, you get your h..."].map { TextLine($0) })
        XCTAssertTrue(PhoneThread.isMessageList(list))
    }
}

/// Nino: bir kez bulunan telefon, baştan bulunamayan karede (koyu uygulamanın alt penceresi açık) gövdesinden takip edilir;
/// telefon olmayan karede takip bırakılır.
final class PhoneTrackerTests: XCTestCase {
    func testTrackerKeepsThePhoneWhileItsBodyIsThere() throws {
        let first = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-telefon-koyu-rydeme.jpg"))
        let sheet = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-telefon-koyu-altpencere.jpg"))
        let menu = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-menu-kapusonlu.jpg"))
        XCTAssertNil(PhonePanel.find(in: sheet), "alt pencere açıkken baştan bulunamıyor")
        let tracker = PhonePanel.Tracker()
        let found = try XCTUnwrap(tracker.locate(in: first))
        XCTAssertEqual(tracker.locate(in: sheet)?.box, found.box, "gövdesinden takip edilir")
        XCTAssertNil(tracker.locate(in: menu), "telefon kalkınca takip biter")
        XCTAssertNil(tracker.locate(in: sheet), "takip bittikten sonra kendiliğinden geri gelmez")
    }
}

final class PhoneUIWordTests: XCTestCase {
    func testAppWordsAreRecognised() {
        for text in ["Cardio Workout", "Calorie Balance", "You will maintain weight", "I Change Destination", "I Change Destinatior", "Book Ryde ($82)", "Choose Ryde", "Trip Details", "buckme", "Checking Account"] {
            XCTAssertTrue(PhoneThread.isPhoneUI(text), text)
        }
        for text in ["You got this!", "Get to the car", "Change of plans, meet me downtown", "Rydell's house is over there",
                     "I skipped my workout today"] {
            XCTAssertFalse(PhoneThread.isPhoneUI(text), text)
        }
    }
}

/// Nino: parlamalı karede telefonun beyaz gövdesi ekrandan sayılıyor (ekran yukarıda ve dar bulunuyor); "Brian" başlığı
/// yine de sohbet başlığı sayılmalı, mesajlar uygulama satırı gibi gösterilmemeli.
final class PhoneThreadGlareTests: XCTestCase {
    func testChatWithGlareIsStillAThread() throws {
        let frame = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-telefon-brian-parlama.jpg"))
        let panel = try XCTUnwrap(PhonePanel.find(in: frame))
        let box = panel.box
        let region = CropRegion(top: box.top, bottom: box.bottom, left: box.left, right: box.right)
        let reading = try VisionReader(language: "en", cpuOnly: true).readLines(RegionCropper.crop(frame, to: region), deep: false).placed(in: box)
        XCTAssertTrue(PhoneThread.isThread(reading, panel: panel))
        let messages = PhoneThread.messages(in: reading, panel: panel)
        XCTAssertFalse(messages.contains { $0.text == "Brian" }, "başlık mesaj değil")
        XCTAssertTrue(messages.contains { $0.text.hasPrefix("Remember, you get your hands") })
    }
}

/// Nino: dokunulmadan duran telefonun ekranı kararıyor (gece sahnesinde beyaz ekran ≈70); yine bulunmalı.
final class DimPhoneTests: XCTestCase {
    func testDimmedPhoneIsFound() throws {
        let frame = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-telefon-karanlik.jpg"))
        let panel = try XCTUnwrap(PhonePanel.find(in: frame))
        XCTAssertEqual(panel.box.left, 0.36, accuracy: 0.03)
        XCTAssertEqual(panel.box.right, 0.60, accuracy: 0.03)
    }
}

/// Nino (kullanıcı): GTA'da altyazı koyu sahnede beyaz yazıdır; telefondaki mesaj açık zeminde koyu yazıdır ve altyazı
/// okumasına girse de altyazı sayılmaz.
final class DarkOnLightTests: XCTestCase {
    private func lines(_ name: String) throws -> (Reading, (Double, Double) -> (r: Int, g: Int, b: Int)?) {
        let frame = try XCTUnwrap(RealPhoneFrameTestsHelper.frame(name))
        let region = CropRegion(top: 0.66, bottom: 0.97, left: 0.14, right: 0.86)
        let area = RegionCropper.crop(frame, to: region)
        let reading = try VisionReader(language: "en", cpuOnly: true).readLines(area, deep: false)
        return (Reading(lines: reading.lines.filter { $0.text.filter(\.isLetter).count >= 4 }), PhonePanel.sampler(for: area))
    }

    func testWhiteSubtitleIsNotDarkOnLight() throws {
        // Aynı karede telefon da var: altyazı beyaz yazı, telefondaki mesaj koyu yazı.
        let (reading, color) = try lines("gta6-altyazi-beyaz.jpg")
        let subtitle = try XCTUnwrap(reading.lines.first { $0.text.contains("gonna love it") })
        XCTAssertFalse(PhoneThread.isDarkOnLight(try XCTUnwrap(subtitle.box), color: color), subtitle.text)
        let phone = reading.lines.filter { $0.text.contains("finder") || $0.text.contains("lockups") }
        XCTAssertFalse(phone.isEmpty)
        for line in phone { XCTAssertTrue(PhoneThread.isDarkOnLight(try XCTUnwrap(line.box), color: color), line.text) }
    }

    func testPhoneMessageIsDarkOnLight() throws {
        let (reading, color) = try lines("gta6-telefon-yakin-alt.jpg")
        let message = reading.lines.filter { $0.text.contains("plane") || $0.text.contains("good to her") }
        XCTAssertFalse(message.isEmpty)
        for line in message { XCTAssertTrue(PhoneThread.isDarkOnLight(try XCTUnwrap(line.box), color: color), line.text) }
    }
}

extension DimPhoneTests {
    /// Kararmış ekranın renkleri aydınlatılır: giden mesaj yine mavi, zemin açık.
    func testDimmedPhoneColorsAreLifted() throws {
        let frame = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-telefon-karanlik.jpg"))
        let panel = try XCTUnwrap(PhonePanel.find(in: frame))
        let color = PhonePanel.liftedSampler(for: frame, panel: panel)
        // "Dropped that stuff off for you" balonu (mavi) ve zemin.
        let blue = try XCTUnwrap(color(0.44, 0.46))
        XCTAssertGreaterThan(blue.b, blue.r + 15, "\(blue)")
        XCTAssertGreaterThan(blue.b, 150, "\(blue)")
    }

    func testRydemeDarkThemeIsNotLifted() throws {
        let frame = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-telefon-koyu-rydeme.jpg"))
        let panel = try XCTUnwrap(PhonePanel.find(in: frame))
        let lifted = PhonePanel.liftedSampler(for: frame, panel: panel), plain = PhonePanel.sampler(for: frame)
        let y = (panel.box.top + panel.box.bottom) / 2, x = panel.left(at: y) + panel.width * 0.5
        XCTAssertEqual(lifted(x, y)?.r, plain(x, y)?.r)
    }
}

/// Nino (kullanıcı): eğik telefonda mavi giden mesaj sağda, beyaz gelen mesaj solda olmalı. Balonun rengi yazının
/// solundan okununca duvar kağıdına düşüyor, hepsi solda çıkıyordu.
final class PhoneOutgoingTiltTests: XCTestCase {
    func testBlueMessagesGoRightOnTiltedPhone() throws {
        let frame = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-telefon-egik-mavi.jpg"))
        let panel = try XCTUnwrap(PhonePanel.find(in: frame))
        let box = panel.box
        let region = CropRegion(top: box.top, bottom: box.bottom, left: box.left, right: box.right)
        let reading = try VisionReader(language: "en", cpuOnly: true).readLines(RegionCropper.crop(frame, to: region), deep: false).placed(in: box)
        let messages = PhoneThread.messages(in: reading, panel: panel)
        let items = PhoneThread.sideBubbles(for: messages, translations: messages.map { "TR " + $0.text }, panel: panel, chat: true,
                                            color: PhonePanel.liftedSampler(for: frame, panel: panel)) { t, _, _ in (1, t.count) }
            .filter { !$0.backdrop }
        let left = items.map(\.box.left).min() ?? 0
        func side(_ start: String) throws -> Bool { try XCTUnwrap(items.first { $0.source.hasPrefix(start) }).box.left > left + 0.02 }
        XCTAssertTrue(try side("Shit went sideways"))
        XCTAssertTrue(try side("Will do"))
        XCTAssertFalse(try side("Ah crap"))
        XCTAssertFalse(try side("Remember"))
    }
}

/// Nino: gündüz telefonun bir yanı güneşli korkuluk (koyu çerçeve görünmüyor); telefon yine bulunmalı ve fotoğraflı
/// sohbet sohbet sayılmalı. Panelin başlığında gönderenin adı olur.
final class DaylightPhoneTests: XCTestCase {
    func testDaylightPhoneWithPhotoIsAThread() throws {
        let frame = try XCTUnwrap(RealPhoneFrameTestsHelper.frame("gta6-telefon-lucia-foto.jpg"))
        let panel = try XCTUnwrap(PhonePanel.find(in: frame))
        XCTAssertEqual((panel.box.left + panel.box.right) / 2, 0.47, accuracy: 0.04)
        let box = panel.box
        let region = CropRegion(top: box.top, bottom: box.bottom, left: box.left, right: box.right)
        let reading = try VisionReader(language: "en", cpuOnly: true).readLines(RegionCropper.crop(frame, to: region), deep: false).placed(in: box)
        XCTAssertTrue(PhoneThread.isThread(reading, panel: panel))
        XCTAssertEqual(PhoneThread.titleText(reading, panel: panel), "Lucia")
    }
}
