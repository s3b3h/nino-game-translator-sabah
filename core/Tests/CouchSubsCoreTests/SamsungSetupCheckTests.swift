// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

final class SamsungSetupCheckTests: XCTestCase {
    private func check(mode: Bool?, ip: String?, computer: String? = "192.168.1.50", port: Bool = true) -> SamsungSetupCheck {
        SamsungSetupCheck(info: SamsungDeveloperInfo(developerMode: mode, developerIp: ip), computer: computer, portOpen: port)
    }

    func testEverythingInPlaceHasNoProblem() {
        XCTAssertNil(check(mode: true, ip: "192.168.1.50").problem)
        XCTAssertEqual(check(mode: true, ip: "192.168.1.50").hostPcIpMatches, true)
    }

    func testDeveloperModeOffComesFirst() {
        XCTAssertEqual(check(mode: false, ip: nil, port: false).problem, .developerModeOff)
        // TV "kapalı" diyorsa kapı açık görünse de adımlar gösterilir.
        XCTAssertEqual(check(mode: false, ip: "192.168.1.50", port: true).problem, .developerModeOff)
    }

    func testOlderTVsThatDoNotReportTheModeUseThePort() {
        XCTAssertEqual(check(mode: nil, ip: nil, port: false).problem, .developerModeOff)
        XCTAssertNil(check(mode: nil, ip: nil, port: true).problem)
        XCTAssertNil(SamsungSetupCheck(info: nil, computer: "192.168.1.50", portOpen: true).problem)
    }

    func testTVThatAnswersNowhereIsNotResponding() {
        // Kapalı ya da yeniden başlayan TV'ye "geliştirici modunu açın" denmez.
        XCTAssertEqual(SamsungSetupCheck(info: nil, computer: "192.168.1.50", portOpen: false).problem, .tvNotResponding)
    }

    func testAnotherAddressIsWrong() {
        XCTAssertEqual(check(mode: true, ip: "192.168.1.20").problem, .hostPcIpWrong(tvIp: "192.168.1.20"))
        XCTAssertEqual(check(mode: true, ip: "192.168.1.20").hostPcIpMatches, false)
    }

    func testAddressTypedWithLeadingZerosIsPadded() {
        XCTAssertEqual(check(mode: true, ip: "192.168.001.050").problem, .hostPcIpPadded(tvIp: "192.168.001.050"))
    }

    func testAddressStoredBackwardsIsReversed() {
        XCTAssertEqual(check(mode: true, ip: "50.1.168.192").problem, .hostPcIpReversed(tvIp: "50.1.168.192"))
    }

    func testLoopbackAddressIsItsOwnProblem() {
        XCTAssertEqual(check(mode: true, ip: "127.0.0.1").problem, .hostPcIpLoopback)
        XCTAssertEqual(check(mode: true, ip: "127.0.0.1", computer: nil).problem, .hostPcIpLoopback)
    }

    func testModeOnWithTheRightAddressButClosedPortNeedsARestart() {
        XCTAssertEqual(check(mode: true, ip: "192.168.1.50", port: false).problem, .needsRestart)
        // Adres bilinmiyorsa da: mod açık ama kapı kapalı.
        XCTAssertEqual(check(mode: true, ip: nil, port: false).problem, .needsRestart)
    }

    func testUnknownAddressesAreNotAMismatch() {
        XCTAssertNil(check(mode: true, ip: nil).problem)
        XCTAssertNil(check(mode: true, ip: "192.168.1.20", computer: nil).problem)
        XCTAssertNil(check(mode: true, ip: nil).hostPcIpMatches)
    }

    func testOctets() {
        XCTAssertEqual(SamsungSetupCheck.octets("192.168.001.092"), [192, 168, 1, 92])
        XCTAssertNil(SamsungSetupCheck.octets("192.168.1"))
        XCTAssertNil(SamsungSetupCheck.octets("192.168.1.256"))
        XCTAssertNil(SamsungSetupCheck.octets("tv.local"))
        XCTAssertNil(SamsungSetupCheck.octets("192.168..1"))
    }

    func testModelYearComesFromTheModelCode() {
        XCTAssertEqual(SamsungMessages.modelYear(Data(#"{"device":{"model":"23_KANTSU2E_QLED","modelName":"QE55Q70CATXTK"}}"#.utf8)), 2023)
        XCTAssertEqual(SamsungMessages.modelYear(Data(#"{"device":{"model":"19_MUSEL_UHD"}}"#.utf8)), 2019)
        XCTAssertNil(SamsungMessages.modelYear(Data(#"{"device":{"model":"QLED"}}"#.utf8)))
        XCTAssertNil(SamsungMessages.modelYear(Data(#"{"device":{"model":"2023_X"}}"#.utf8)))
        XCTAssertNil(SamsungMessages.modelYear(Data(#"{"device":{"name":"TV"}}"#.utf8)))
        XCTAssertNil(SamsungMessages.modelYear(Data("not json".utf8)))
    }

    func testKeyMessageCarriesTheKeyAndTheCommand() throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: SamsungMessages.key("KEY_1", command: "Press")) as? [String: Any])
        XCTAssertEqual(object["method"] as? String, "ms.remote.control")
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        XCTAssertEqual(params["Cmd"] as? String, "Press")
        XCTAssertEqual(params["DataOfCmd"] as? String, "KEY_1")
        XCTAssertEqual(params["TypeOfRemote"] as? String, "SendRemoteKey")
        XCTAssertEqual(SamsungDeveloperCode.keys, ["KEY_1", "KEY_2", "KEY_3", "KEY_4", "KEY_5"])
    }
}
