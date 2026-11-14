// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Nino: önerilen yerel çeviri modelleri. Kullanıcı Terminal'de "ollama pull …" yazmasın; Ayarlar'da seçip İndir'e basar.
public struct LocalModelPreset: Identifiable, Equatable, Sendable {
    /// Ollama'daki tam adı (ayara bu yazılır).
    public let id: String
    public let title: String
    /// Kısa açıklama (İngilizce anahtar; arayüz yerelleştirir).
    public let detail: String
    /// İndirme boyu, gösterim için ("3,3 GB").
    public let gigabytes: Double
    public let recommended: Bool

    public static let all: [LocalModelPreset] = [
        LocalModelPreset(id: "translategemma:4b", title: "TranslateGemma 4B",
                         detail: "Google's translation model. Runs on most computers.", gigabytes: 3.3, recommended: true),
        LocalModelPreset(id: "translategemma:12b", title: "TranslateGemma 12B",
                         detail: "Translates better. Needs 16 GB of memory or more.", gigabytes: 8.1, recommended: false),
        LocalModelPreset(id: "hf.co/mradermacher/MiLMMT-46-4B-v1.0-GGUF:Q4_K_M", title: "MiLMMT 4B",
                         detail: "Xiaomi's translation model. Fast and natural.", gigabytes: 3.1, recommended: false),
    ]

    public static func preset(for model: String) -> LocalModelPreset? {
        all.first { $0.id.caseInsensitiveCompare(model.trimmingCharacters(in: .whitespaces)) == .orderedSame }
    }
}

/// Ollama'nın kendi API'si (docs.ollama.com/api): kurulu modeller (GET /api/tags) ve model indirme (POST /api/pull).
/// Çeviri isteği OpenAI uyumlu /v1 adresinden gider; bunlar yalnız Ayarlar'daki kolay kurulum için.
public enum OllamaAPI {
    /// "http://localhost:11434/v1" → "http://localhost:11434".
    public static func root(of baseURL: URL) -> URL {
        var text = baseURL.absoluteString
        while text.hasSuffix("/") { text.removeLast() }
        if text.lowercased().hasSuffix("/v1") { text.removeLast(3) }
        return URL(string: text) ?? baseURL
    }

    /// Kurulu modellerin adları; Ollama çalışmıyorsa nil.
    public static func installedModels(baseURL: URL, session: URLSession = .shared) async -> [String]? {
        var request = URLRequest(url: root(of: baseURL).appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parseTags(data)
    }

    static func parseTags(_ data: Data) -> [String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return nil }
        return models.compactMap { ($0["name"] as? String) ?? ($0["model"] as? String) }
    }

    /// Model kurulu mu (adlar büyük/küçük harf ayırmadan; "model" ile "model:latest" aynıdır).
    public static func contains(_ installed: [String], _ model: String) -> Bool {
        func key(_ name: String) -> String {
            let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
            return lower.hasSuffix(":latest") ? String(lower.dropLast(7)) : lower
        }
        return installed.contains { key($0) == key(model) }
    }

    public enum PullError: Error, Equatable {
        case unreachable
        case failed(String)
    }

    /// Modeli indirir; `progress` 0–1 arası çağrılır. Ollama ilerlemeyi satır satır JSON olarak yollar.
    public static func pull(_ model: String, baseURL: URL, session: URLSession = .shared,
                            progress: @escaping @Sendable (Double) -> Void) async throws {
        var request = URLRequest(url: root(of: baseURL).appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
        request.timeoutInterval = 60 * 60
        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PullError.unreachable
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PullError.failed("HTTP") }
        var tracker = PullProgress()
        for try await line in bytes.lines {
            switch tracker.read(line) {
            case .progress(let value): progress(value)
            case .failed(let message): throw PullError.failed(message)
            case .done: progress(1); return
            case .none: break
            }
        }
        if !tracker.finished { throw PullError.failed("incomplete") }
    }
}

/// Ollama'nın indirme satırlarını okur: {"status":"pulling …","digest":…,"total":…,"completed":…}, sonunda
/// {"status":"success"}, hata olursa {"error":"…"}. Model birkaç parçadan oluşur; ilerleme bütün parçaların toplamıdır.
struct PullProgress {
    enum Event: Equatable { case progress(Double), failed(String), done }
    private var parts: [String: (total: Double, completed: Double)] = [:]
    private(set) var finished = false

    mutating func read(_ line: String) -> Event? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object["error"] as? String { return .failed(error) }
        if (object["status"] as? String) == "success" {
            finished = true
            return .done
        }
        guard let digest = object["digest"] as? String, let total = (object["total"] as? NSNumber)?.doubleValue, total > 0
        else { return nil }
        parts[digest] = (total, (object["completed"] as? NSNumber)?.doubleValue ?? 0)
        let sum = parts.values.reduce(into: (0.0, 0.0)) { $0.0 += $1.total; $0.1 += $1.completed }
        return .progress(min(0.99, sum.1 / sum.0))
    }
}
