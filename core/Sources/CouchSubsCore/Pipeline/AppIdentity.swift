// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Uygulamanın adı ve kimlikleri tek yerde.
public enum AppIdentity {
    public static let name = "CouchSubs"
    public static let tvAppId = "com.couchsubs.tv"
    public static let samsungAppId = "CouchSubsT.CouchSubs"
    public static let tvGuideURL = URL(string: "https://github.com/yunusdemirbag/nino-game-translator/blob/main/docs/tv-kurulum.md")!
    public static let sourceURL = URL(string: "https://github.com/yunusdemirbag/nino-game-translator")!
    public static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    public static let serverPort: UInt16 = 8787
    /// Nino: herkesin gördüğü sürüm adı, bütün uygulamalarda (Mac, Windows, telefon, TV) aynı.
    public static let label = "V3.3"
    /// "V3.3 (0.2.4)"
    public static var displayVersion: String { "\(label) (\(version))" }
}
