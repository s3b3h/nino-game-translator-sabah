// SPDX-License-Identifier: AGPL-3.0-only

import XCTest
@testable import CouchSubsCore

/// Nino: Ayarlar'daki kolay kurulum (Ollama'nın kurulu modelleri ve indirme ilerlemesi).
final class OllamaAPITests: XCTestCase {
    func testRootDropsTheOpenAIPath() {
        XCTAssertEqual(OllamaAPI.root(of: URL(string: "http://localhost:11434/v1")!).absoluteString, "http://localhost:11434")
        XCTAssertEqual(OllamaAPI.root(of: URL(string: "http://192.168.1.20:11434/v1/")!).absoluteString, "http://192.168.1.20:11434")
    }

    func testInstalledModelsAreMatchedLoosely() throws {
        let tags = #"{"models":[{"name":"translategemma:4b","model":"translategemma:4b"},{"name":"hf.co/mradermacher/MiLMMT-46-4B-v1.0-GGUF:Q4_K_M"},{"name":"llama3:latest"}]}"#
        let names = try XCTUnwrap(OllamaAPI.parseTags(Data(tags.utf8)))
        XCTAssertTrue(OllamaAPI.contains(names, "translategemma:4b"))
        XCTAssertTrue(OllamaAPI.contains(names, "HF.CO/mradermacher/MiLMMT-46-4B-v1.0-GGUF:Q4_K_M"))
        XCTAssertTrue(OllamaAPI.contains(names, "llama3"))
        XCTAssertFalse(OllamaAPI.contains(names, "translategemma:12b"))
    }

    func testPullProgressSumsAllParts() {
        var tracker = PullProgress()
        XCTAssertNil(tracker.read(#"{"status":"pulling manifest"}"#))
        XCTAssertEqual(tracker.read(#"{"status":"pulling a","digest":"a","total":100,"completed":50}"#), .progress(0.5))
        XCTAssertEqual(tracker.read(#"{"status":"pulling b","digest":"b","total":100,"completed":0}"#), .progress(0.25))
        XCTAssertEqual(tracker.read(#"{"status":"success"}"#), .done)
        XCTAssertTrue(tracker.finished)
        var failing = PullProgress()
        XCTAssertEqual(failing.read(#"{"error":"pull model manifest: file does not exist"}"#),
                       .failed("pull model manifest: file does not exist"))
    }

    func testOldQwenDefaultMovesToTheRecommendedModel() throws {
        let saved = try JSONEncoder().encode(["localAIModel": "qwen2.5:7b"])
        XCTAssertEqual(try JSONDecoder().decode(UserSettings.self, from: saved).localAIModel, LocalAIServer.defaultModel)
        let chosen = try JSONEncoder().encode(["localAIModel": "qwen2.5:14b"])
        XCTAssertEqual(try JSONDecoder().decode(UserSettings.self, from: chosen).localAIModel, "qwen2.5:14b")
    }

    /// Bu bilgisayarda Ollama açıksa gerçek listeyi okur (açık değilse atlanır).
    func testLiveOllamaWhenRunning() async throws {
        guard let names = await OllamaAPI.installedModels(baseURL: URL(string: LocalAIServer.ollamaURL)!) else {
            throw XCTSkip("Ollama çalışmıyor")
        }
        print("Ollama modelleri: \(names)")
    }
}
