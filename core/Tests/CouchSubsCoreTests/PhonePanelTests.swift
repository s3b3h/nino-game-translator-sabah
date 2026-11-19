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
