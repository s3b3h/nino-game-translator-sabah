import CoreGraphics
import ImageIO
import XCTest
@testable import CouchSubsCore

final class MapCardTests: XCTestCase {
    private func line(_ text: String, _ left: Double, _ top: Double, _ right: Double, _ bottom: Double) -> TextLine {
        TextLine(text, box: TextBox(left: left, top: top, right: right, bottom: bottom))
    }

    /// Gerçek kareden (GTA 6 haritası, "Buy Flowers" seçili).
    private var map: Reading {
        Reading(lines: [
            line("STORY", 0.018, 0.04, 0.071, 0.075),
            line("Pick Up Lucia", 0.081, 0.12, 0.166, 0.145),
            line("OPTIONAL", 0.053, 0.18, 0.108, 0.205),
            line("Buy Flowers", 0.081, 0.238, 0.157, 0.263),
            line("Buy Lucia a Necklace", 0.081, 0.297, 0.214, 0.322),
            line("$1,200", 0.913, 0.12, 0.961, 0.147),
            line("0.63 mi", 0.484, 0.503, 0.517, 0.523),
            line("BUY FLOWERS", 0.577, 0.425, 0.662, 0.458),
            line("Lucia will appreciate this", 0.568, 0.478, 0.725, 0.506),
            line("Have some flowers delivered to the", 0.548, 0.521, 0.775, 0.549),
            line("house for Lucia.", 0.548, 0.556, 0.649, 0.584),
            line("RECENTER", 0.906, 0.757, 0.960, 0.777),
            line("2D VIEW", 0.918, 0.805, 0.960, 0.825),
            line("ADD MARKER", 0.893, 0.853, 0.960, 0.873),
            line("SET DESTINATION", 0.872, 0.901, 0.960, 0.921),
        ])
    }

    func testMapScreenIsRecognizedByItsButtonList() {
        XCTAssertTrue(MapCard.isMapScreen(map))
        XCTAssertFalse(MapCard.isMapScreen(Reading(lines: [line("You trying to kill me?", 0.4, 0.88, 0.6, 0.915)])))
    }

    func testCardTitleAndSentencesAreFound() throws {
        let card = try XCTUnwrap(MapCard.find(in: map))
        XCTAssertEqual(card.title, "BUY FLOWERS")
        XCTAssertEqual(card.sentences, ["Lucia will appreciate this", "Have some flowers delivered to the house for Lucia."])
        XCTAssertEqual(card.box.top, 0.425, accuracy: 0.001)
        XCTAssertEqual(card.box.bottom, 0.584, accuracy: 0.001)
    }

    /// Kart yokken (yalnız menü ve harita) bir şey bulunmaz.
    func testNoCardWithoutSentences() {
        let empty = Reading(lines: map.lines.filter { !["BUY FLOWERS", "Lucia will appreciate this",
                                                        "Have some flowers delivered to the", "house for Lucia."].contains($0.text) })
        XCTAssertNil(MapCard.find(in: empty))
    }

    /// Elle: NINO_FRAME klasöründeki gerçek karelerde haritayı ve kartı arar.
    func testProbeRealFrames() throws {
        guard let path = ProcessInfo.processInfo.environment["NINO_FRAME"] else { throw XCTSkip("NINO_FRAME yok") }
        let files = try FileManager.default.contentsOfDirectory(atPath: path).filter { $0.hasSuffix(".jpg") }.sorted()
        let region = CropRegion(top: 0.03, bottom: 0.95, left: 0, right: 1)
        for file in files {
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path + "/" + file) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            let place = TextBox(left: region.left, top: region.top, right: region.right, bottom: region.bottom)
            let reading = try VisionReader(language: "en").readLines(RegionCropper.crop(image, to: region), deep: false).placed(in: place)
            let isMap = MapCard.isMapScreen(reading)
            print("HARİTA", file, isMap ? "evet" : "hayır", "menü:", MenuBlock.isMenuScreen(reading))
            if ProcessInfo.processInfo.environment["NINO_READ"] == "2" {
                for line in reading.lines {
                    guard let b = line.box else { continue }
                    print("   SATIR", String(format: "%.3f %.3f %.3f %.3f", b.left, b.top, b.right, b.bottom), line.text)
                }
            }
            if isMap, let card = MapCard.find(in: reading) {
                print("   KART", card.title, "|", card.sentences.joined(separator: " | "),
                      String(format: "%.3f–%.3f", card.box.top, card.box.bottom))
            }
        }
    }
}
