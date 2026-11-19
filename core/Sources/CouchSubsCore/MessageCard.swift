// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Nino: oyunda telefona gelen mesaj kartı (GTA 6: üstte gönderenin adı "Donnie", altında mesaj). Altyazı değildir:
/// Türkçesi siyah altyazı kutusunda değil, kartın üstünde yarı saydam yazıyla gösterilir.
public enum MessageCard {
    /// Okumanın ilk satırı kısa bir ad (kişi ya da dükkân), altında en az üç sözcüklük küçük harfli mesaj satırı varsa kart sayılır.
    /// Konuşan adı iki noktalıysa ("ENZO: ...") altyazıdır, kart değildir.
    public static func isCard(_ reading: Reading) -> Bool {
        let lines = reading.lines
        if isList(reading) { return false }
        guard lines.count >= 2, let name = lines.first, let nameBox = name.box, let firstBody = lines[1].box else { return false }
        let text = name.text.trimmingCharacters(in: .whitespaces)
        // Gönderen: kişi ya da yer adı ("Donnie", "Chuck's Gun Shop"): 1-4 sözcük, her biri büyük harfle başlar, cümle
        // noktalaması yok. Konuşan adı iki noktalıdır ("ENZO: ..."), o altyazıdır.
        let words = text.split(separator: " ")
        guard (2...30).contains(text.count), (1...4).contains(words.count),
              words.allSatisfy({ $0.first?.isUppercase == true || $0.first == "&" }),
              // Tabela/reklam yazısı ("TREADBounD") ad değildir: sözcüğün içinde birden çok büyük harf olmaz.
              words.allSatisfy({ $0.dropFirst().filter(\.isUppercase).count <= 1 }),
              text.contains(where: \.isLowercase),
              !text.contains(where: { ".,!?:;…\"".contains($0) }) else { return false }
        guard nameBox.bottom <= firstBody.top + 0.01 else { return false }
        let body = lines.dropFirst().map(\.text).joined(separator: " ")
        let bodyWords = body.split(separator: " ").count
        if bodyWords >= 3 { return body.contains(where: \.isLowercase) }
        // Kısa mesaj ("On my way", "Ok"): eskiden kart sayılmıyor, altyazı sanılıp siyah kutuyla kartın üstüne basılıyordu.
        // Altyazı ekranın ortasındadır; ad + 1-2 sözcük yalnız okunan alanın sağ yarısında duruyorsa karttır.
        return bodyWords >= 1 && body.contains(where: \.isLetter) && min(nameBox.left, firstBody.left) >= shortCardLeft
    }

    /// Kısa mesajlı kartın sol kenarı en az burada olmalı (okunan alana oranla; GTA 6'da kart sağ alttadır).
    static let shortCardLeft = 0.55

    /// Telefon araması kartı (üstte arananın adı "Paradise Taxi", altında "Calling...", "Incoming call" ya da süre "00:05").
    /// Altyazı değildir. Durumun Türkçesi hazırdır (çeviriye gitmez); süre gösterilirken (konuşma sürüyor) durum boştur.
    public static func call(_ reading: Reading) -> (name: String, status: String)? {
        let lines = reading.lines.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count == 2, isName(lines[0]) else { return nil }
        let state = lines[1].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".… "))
        switch state {
        case "calling", "dialing", "dialling", "connecting", "ringing": return (lines[0], "aranıyor…")
        case "incoming call", "incoming": return (lines[0], "seni arıyor…")
        case "call ended", "ended", "call failed", "busy", "no answer", "unavailable": return (lines[0], "arama bitti")
        default: break
        }
        if lines[1].range(of: #"^\d{1,2}:\d{2}(:\d{2})?$"#, options: .regularExpression) != nil { return (lines[0], "") }
        return nil
    }

    /// Telefonun mesaj listesi (gönderen adları ve "…" ile kesilmiş önizlemeler alt alta): altyazı da mesaj da değildir.
    public static func isList(_ reading: Reading) -> Bool {
        let lines = reading.lines.map { $0.text.trimmingCharacters(in: .whitespaces) }
        let names = lines.filter(isName).count
        let truncated = lines.filter { $0.hasSuffix("...") || $0.hasSuffix("…") }.count
        return lines.count >= 3 && (names >= 2 || truncated >= 2)
    }

    static func isName(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        return (2...30).contains(text.count) && (1...4).contains(words.count)
            && words.allSatisfy({ $0.first?.isUppercase == true || $0.first == "&" })
            && words.allSatisfy({ $0.dropFirst().filter(\.isUppercase).count <= 1 })
            && text.contains(where: \.isLowercase) && !text.contains(where: { ".,!?:;…\"".contains($0) })
    }

    /// Gönderenin adı ve mesaj metni.
    public static func parts(_ reading: Reading) -> (name: String, body: String) {
        (reading.lines.first?.text.trimmingCharacters(in: .whitespaces) ?? "",
         reading.lines.dropFirst().map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: " "))
    }

    /// Okuma, kartın metninin bir parçası mı (adı okunamayan kart): sözcüklerinin en az yarısı kartta geçiyorsa.
    public static func repeats(_ text: String, of body: String) -> Bool {
        let read = Set(TextMatch.normalize(text).split(separator: " ").filter { $0.count > 1 }.map(String.init))
        let card = Set(TextMatch.normalize(body).split(separator: " ").map(String.init))
        // Kısa mesajın ("On my way") adı okunmayan karesi: okunan sözcüklerin hepsi kartta geçiyorsa o da kartın parçasıdır.
        if card.count <= 2 { return !read.isEmpty && read.isSubset(of: card) }
        guard read.count >= 2 else { return false }
        return Double(read.intersection(card).count) / Double(read.count) >= 0.5
    }
}
