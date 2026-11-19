// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

final class DeviceInfoTests: XCTestCase {
    func testRowsSkipUnknownValues() {
        let rows = DeviceInfo.rows(app: "3.4.0 (19)", tv: nil, console: "PS5 · Remote Play", status: "  ",
                                   model: "Mac16,1", system: "macOS 27.0")
        XCTAssertEqual(rows.map(\.id), ["app", "device", "system", "console"])
    }

    func testSummaryIsOneLine() {
        let rows = DeviceInfo.rows(app: "3.4.0 (19)", tv: "Samsung QE55Q70C\nTV uygulaması 3.4.0", console: "PS5 | Remote Play",
                                   model: "Mac16,1", system: "macOS 27.0")
        XCTAssertEqual(DeviceInfo.summary(rows),
                       "app: 3.4.0 (19) | device: Mac16,1 | system: macOS 27.0 | tv: Samsung QE55Q70C TV uygulaması 3.4.0 | console: PS5 / Remote Play")
    }

    func testSummaryIsClipped() {
        let rows = DeviceInfo.rows(app: String(repeating: "x", count: 2000), model: "Mac16,1", system: "macOS 27.0")
        XCTAssertEqual(DeviceInfo.summary(rows).count, DeviceInfo.maxLength)
    }

    func testThisMachineHasAModelAndSystem() {
        XCTAssertFalse(DeviceInfo.model.isEmpty)
        XCTAssertTrue(DeviceInfo.system.hasPrefix("macOS ") || DeviceInfo.system.hasPrefix("iOS "))
    }

    func testReportCarriesDeviceOnlyWhenKnown() throws {
        let with = ProblemReport.Payload(install: "12345678", app: "3.4.0", platform: "mac", language: "tr", text: "x",
                                         device: " app: 3.4.0 | device: Mac16,1 ")
        XCTAssertEqual(with.device, "app: 3.4.0 | device: Mac16,1")
        let without = ProblemReport.Payload(install: "12345678", app: "3.4.0", platform: "mac", language: "tr", text: "x")
        XCTAssertNil(without.device)
        XCTAssertFalse(String(decoding: try ProblemReport.encode(without), as: UTF8.self).contains("device"))
    }
}
