// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Yazının yeri, içinde bulunduğu alanın kenarlarına oranla (0–1, üstten ve soldan).
public struct TextBox: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    public func union(_ other: TextBox) -> TextBox {
        TextBox(left: min(left, other.left), top: min(top, other.top), right: max(right, other.right), bottom: max(bottom, other.bottom))
    }

    /// Bu kutu `area` içindeki oranlarsa, aynı yerin `area`'yı içeren çerçevedeki oranları.
    public func placed(in area: TextBox) -> TextBox {
        let width = area.right - area.left, height = area.bottom - area.top
        return TextBox(left: area.left + left * width, top: area.top + top * height,
                       right: area.left + right * width, bottom: area.top + bottom * height)
    }

    /// Ekranın ortasındaki altyazının kutusu ortaya göre simetrik genişletilir. Açık zeminde ya da renkli yazıda
    /// yazı tanıma satırın bir ucunu okuyamayabilir; kutu yalnız okunan parçayı örterse İngilizcenin geri kalanı
    /// yanda görünür ve çeviri ortalanmamış durur. Ortadan uzak (köşedeki) yazıya dokunulmaz (Windows: TextBox.CenteredOnScreen).
    public func centeredOnScreen() -> TextBox {
        let middle = (left + right) / 2
        guard middle > 0.3, middle < 0.7 else { return self }
        return TextBox(left: max(0, min(left, 1 - right)), top: top, right: min(1, max(right, 1 - left)), bottom: bottom)
    }
}

/// Yazı tanımanın bulduğu bir satır.
public struct TextLine: Equatable, Sendable {
    public var text: String
    /// Okunan alana göre yeri; bilinmiyorsa nil.
    public var box: TextBox?
    /// Yazı tanımanın bu satırdan ne kadar emin olduğu (0–1); okuyucu vermiyorsa nil.
    public var confidence: Double?

    public init(_ text: String, box: TextBox? = nil, confidence: Double? = nil) {
        self.text = text
        self.box = box
        self.confidence = confidence
    }
}

/// Bir karenin okunan satırları, yukarıdan aşağı.
public struct Reading: Equatable, Sendable {
    public var lines: [TextLine]

    public init(lines: [TextLine]) {
        self.lines = lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public static let empty = Reading(lines: [])

    /// Satırları ayrı ayrı bilinmeyen eski okuyucular için: her satır sonu bir satırdır.
    public init(text: String) {
        self.init(lines: text.components(separatedBy: .newlines).map { TextLine($0.trimmingCharacters(in: .whitespaces)) })
    }

    public var text: String { lines.map(\.text).joined(separator: "\n") }

    /// Bütün satırları içine alan kutu; hiçbir satırın yeri bilinmiyorsa nil.
    public var box: TextBox? {
        lines.compactMap(\.box).reduce(nil) { total, box in total?.union(box) ?? box }
    }

    /// Satırların ortalama tanıma güveni (0–1); okuyucu güven vermiyorsa nil.
    public var confidence: Double? {
        let values = lines.compactMap(\.confidence)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Oyunun düğme ipuçları ("R2 Swing", "△ Pick up") çıkarılmış hali; bunlar altyazı değildir.
    public func withoutButtonPrompts() -> Reading {
        Reading(lines: lines.filter { !ButtonPrompts.isPrompt($0.text) })
    }

    /// Nino: oyunun eşya, kıyafet ve araç etiketleri altyazı değildir ("TRAP SANDALS", "WORTHAM / COMBAT RIFLE", "MILK"),
    /// tuş şeritleri de ("ADD TO TRUNK (1/5) □ WEAR ✕ EXIT ○"). Ayıklananlar: "(1/5)" gibi sayaç taşıyan satırlar, iki ya da
    /// daha çok tuş simgesi olan satırlar ve noktalama içermeyen, küçük harfi olmayan 1-4 sözcüklük kısa satırlar.
    /// Bağıran altyazı ("GET DOWN!") noktalamasıyla, konuşan adlı satır ("ENZO: ...") küçük harfleriyle kalır.
    public func withoutItemLabels() -> Reading {
        Reading(lines: lines.filter { !Self.isItemLabel($0.text) })
    }

    public static func isItemLabel(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.range(of: #"\(\d+\s*/\s*\d+\)"#, options: .regularExpression) != nil { return true }
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if tokens.filter(ButtonPrompts.isIcon).count >= 2 { return true }
        let words = tokens.filter { $0.contains(where: \.isLetter) }
        // Boya kutusu, ürün etiketi, reklam ("LOW ODOR, ZERO VOC", "MAKE IT A RIMM JOB!", "[POXY, ZINC, PHOSPHA?"): küçük
        // harfsiz, en çok 6 sözcük; noktalama olsa da etikettir. Yalnız 1-2 sözcüklük bağırış ("GET DOWN!", "WHAT?") kalır.
        if (1...6).contains(words.count), !text.contains(where: \.isLowercase), text.contains(where: \.isLetter),
           !(words.count <= 2 && (text.hasSuffix("!") || text.hasSuffix("?"))) { return true }
        guard (1...4).contains(words.count) else { return false }
        // Tek sözcüklük, noktalamasız yazı uygulama ya da ekran adıdır ("WhatUp", "Contacts"); tek sözcüklük altyazı
        // noktalamalıdır ("Okay.", "Lucia?").
        if words.count == 1, tokens.count == 1, text.allSatisfy({ $0.isLetter || $0 == "'" }) { return true }
        // Plaka, tabela, kısa okuma çöpü ("ASS MAN.", "\"ASS\" MAN", "NYWL, SSY."): küçük harfsiz, en çok 3 sözcük; noktalama
        // olsa da etikettir. Bağıran altyazı ("GET DOWN!", "WHAT?") ünlem ya da soruyla biter, kalır.
        if words.count <= 3, !text.contains(where: \.isLowercase), !text.hasSuffix("!"), !text.hasSuffix("?") { return true }
        // Kesme işareti ("GONE FISHIN'", "JASON'S") etikette de olur; cümle noktalaması değildir.
        if text.contains(where: { ".,!?:;…\"".contains($0) }) { return false }
        return !text.contains(where: \.isLowercase)
    }

    /// Yazı tanımanın uydurduğu sözcük çöpleri ("ou$3e", "waters2aljd") ayıklanmış hali; çevirmen bunları olduğu
    /// gibi taşıyıp TV'de anlamsız harfler gösteriyordu.
    /// Nino: okunan alanın hem sol hem sağ kenarına değen satır kesiktir, altyazı değildir: oyunların açılıştaki yasal uyarısı
    /// ("…rental, pay for play, or circumvention of copy protection…") ya da PS5 menüsündeki kayan yazı alanın iki yanından
    /// taşar, yarım okunur ve anlamsız çevrilirdi. Altyazılar ortalıdır, iki kenara birden değmez. (Yalnız bir kenara değen
    /// satır kalır: dar seçilmiş bir alanda gerçek altyazı da bir yandan taşabilir.) `margin`, alan genişliğine oranla.
    public func withoutClippedLines(margin: Double = 0.015) -> Reading {
        Reading(lines: lines.filter { line in
            guard let box = line.box else { return true }
            return !(box.left <= margin && box.right >= 1 - margin)
        })
    }

    /// Nino: dev yazı altyazı değildir. Oyunun içindeki tabela, reklam panosu, dükkân adı ya da ekranı kaplayan başlık
    /// altyazı sanılıp çevriliyor, TV'de de yazının kapladığı yer kadar kocaman siyah bir kutu çıkıyordu. Altyazı satırı
    /// ekran yüksekliğinin yaklaşık %2,5-5'i kadardır (en büyük erişilebilirlik ayarında %6); bundan belirgin biçimde
    /// büyük satır atılır. Ölçü karenin tamamına göredir (`area`: okunan alanın karedeki yeri), dar seçilmiş alanda
    /// normal satır büyük görünmesin. Yeri bilinmeyen satıra dokunulmaz (Windows: Reading.WithoutOversizedLines,
    /// Android: Reading.withoutOversizedLines).
    public static let maxSubtitleLineHeight = 0.075
    /// Altyazı bloğunun karede kaplayabileceği en çok yükseklik ve satır sayısı; aşan blok altyazı değildir (afiş,
    /// not, belge, üst üste tabelalar).
    public static let maxSubtitleBlockHeight = 0.26
    public static let maxSubtitleLines = 5

    /// Cümle gibi görünen satır bu kadar yüksekse de atılır (karenin %13'ü): altyazı hiçbir oyunda bu kadar büyük değildir.
    public static let maxSentenceLineHeight = 0.13

    /// Etiket gibi satır: en çok 4 sözcük ve cümle noktalaması yok ("OHM BOY", "Boat Charters", "YARD SALE").
    /// Altyazı satırı ya uzundur ya da noktalamalıdır ("What?", "We made it!").
    public static func isLabelLike(_ raw: String) -> Bool {
        let words = raw.split(whereSeparator: \.isWhitespace).filter { $0.contains(where: \.isLetter) }
        return words.count <= 4 && !raw.contains(where: { ".,!?…".contains($0) })
    }

    /// Dev satırlar atılır, ama temkinli: `limit`ten yüksek satır yalnız etiket gibiyse (tabela, pano) atılır. Cümle gibi
    /// satır, yanındaki gösterge ya da tabela harfiyle aynı sıraya düşüp yüksek ölçülmüş gerçek altyazı olabilir
    /// ("What happened? 0006", V3.4'te böyle satırlar atılıyordu); o ancak `maxSentenceLineHeight`i aşarsa atılır.
    public func withoutOversizedLines(in area: TextBox, limit: Double = Reading.maxSubtitleLineHeight) -> Reading {
        let scale = area.bottom - area.top
        return Reading(lines: lines.filter { line in
            guard let box = line.box else { return true }
            let height = (box.bottom - box.top) * scale
            if height > max(limit, Self.maxSentenceLineHeight) { return false }
            return !(height > limit && Self.isLabelLike(line.text))
        })
    }

    /// Blok bir altyazı için fazla mı yüksek ya da fazla mı satırlı (bkz. `maxSubtitleBlockHeight`).
    public func isOversizedBlock(in area: TextBox) -> Bool {
        if lines.count > Self.maxSubtitleLines { return true }
        guard let box else { return false }
        return (box.bottom - box.top) * (area.bottom - area.top) > Self.maxSubtitleBlockHeight
    }

    public func withoutOcrNoise() -> Reading {
        Reading(lines: lines.map { TextLine(OcrNoise.clean($0.text), box: $0.box, confidence: $0.confidence) })
    }

    /// Aynı satırda yan yana okunan parçalar soldan sağa tek satır olur. Renkli konuşan adını ("Arthur:", RDR2) yazı
    /// tanıma cümleden ayrı okuyor; parçalar yalnız üst kenarlarına göre dizilince ad cümlenin sonuna düşüyor ya da ayrı
    /// blok sayılıp atılıyordu. Yatayda aralarında en çok `rowGap` (alan genişliğine oranla) olan parçalar birleşir;
    /// uzaktaki köşe yazısı ayrı kalır (Android: Reading.joiningRows, Windows: Reading.JoiningRows).
    public func joiningRows() -> Reading {
        guard lines.count > 1, lines.allSatisfy({ $0.box != nil }) else { return self }
        var rows: [TextLine] = []
        for line in lines.sorted(by: { $0.box!.left < $1.box!.left }) {
            let box = line.box!
            if let index = rows.firstIndex(where: { Self.sameRow(box, $0.box!) }) {
                let row = rows[index]
                let confidence = [row.confidence, line.confidence].compactMap { $0 }.min()
                rows[index] = TextLine(row.text + " " + line.text, box: row.box!.union(box), confidence: confidence)
            } else {
                rows.append(line)
            }
        }
        return Reading(lines: rows.sorted { $0.box!.top < $1.box!.top })
    }

    static let rowGap = 0.05

    /// `next` (solda başlayan `row`'un sağında) aynı satırda mı: dikeyde küçük yüksekliğin en az %60'ı örtüşür.
    private static func sameRow(_ next: TextBox, _ row: TextBox) -> Bool {
        let overlap = min(next.bottom, row.bottom) - max(next.top, row.top)
        let smaller = min(next.bottom - next.top, row.bottom - row.top)
        guard smaller > 0, overlap >= smaller * 0.6 else { return false }
        return next.left - row.right <= rowGap
    }

    /// Alandaki altyazı bloğu. Seçilen alanda altyazının yanında menü ("MAP / HELP / SETTINGS" alt alta), köşedeki
    /// gösterge ("9", "PHOTO MODE") da okunuyordu; hepsi tek cümle gibi çevrilip TV'de bütün alanı kaplayan kutuyla
    /// gösteriliyordu. Satırlar yerlerine göre bloklara ayrılır; ortalanmış ve menü olmayan en alttaki blok altyazıdır.
    /// Ortalanmış blok yoksa en az üç sözcüklü, menü olmayan en alttaki blok alınır. Satırların yeri bilinmiyorsa
    /// okuma olduğu gibi kalır. `area`, okunan alanın karedeki yeridir (ortalanmışlık karenin ortasına göre ölçülür).
    public func subtitleBlock(in area: TextBox) -> Reading {
        guard !lines.isEmpty, lines.allSatisfy({ $0.box != nil }) else { return self }
        var blocks: [[TextLine]] = []
        for line in lines.sorted(by: { $0.box!.top < $1.box!.top }) {
            let box = line.box!.placed(in: area)
            if let index = blocks.lastIndex(where: { Self.belongs(box, to: $0, in: area) }) {
                blocks[index].append(line)
            } else {
                blocks.append([line])
            }
        }
        let candidates = blocks.map { Reading(lines: $0) }.filter { !$0.isMenu }
        let centered = candidates.filter { reading in
            guard let box = reading.box?.placed(in: area) else { return false }
            return abs((box.left + box.right) / 2 - 0.5) <= 0.12
        }
        if let block = centered.max(by: { $0.box!.bottom < $1.box!.bottom }) { return block }
        return candidates.filter { $0.text.split(whereSeparator: \.isWhitespace).count >= 3 }
            .max(by: { $0.box!.bottom < $1.box!.bottom }) ?? .empty
    }

    /// Bloğun son satırının hemen altında (arada bir satır yüksekliğinden az) ve yatayda onunla üst üste binen satır
    /// o bloğa aittir.
    private static func belongs(_ box: TextBox, to block: [TextLine], in area: TextBox) -> Bool {
        let last = block.last!.box!.placed(in: area)
        let height = max(box.bottom - box.top, last.bottom - last.top)
        guard box.top - last.bottom < height * 0.8, box.top >= last.top else { return false }
        let overlap = min(box.right, last.right) - max(box.left, last.left)
        let narrower = min(box.right - box.left, last.right - last.left)
        return overlap > 0 && overlap >= narrower * 0.5
    }

    /// Alt alta kısa ve noktalamasız satırlar ("MAP", "HELP", "SOCIAL CLUB") menüdür, konuşma değil.
    var isMenu: Bool {
        lines.count >= 3 && lines.allSatisfy { line in
            line.text.split(whereSeparator: \.isWhitespace).count <= 3 && !SubtitleStabilizer.endsSentence(line.text)
        }
    }

    /// Satır kutularını `area` içindeki oranlardan dış çerçevenin oranlarına taşır.
    public func placed(in area: TextBox) -> Reading {
        Reading(lines: lines.map { TextLine($0.text, box: $0.box?.placed(in: area), confidence: $0.confidence) })
    }
}

/// Oyunların ekranda gösterdiği kumanda ipuçlarını tanır: "R2 Swing", "L1 + R1 Spartan Rage",
/// "△ Pick up", "Press ✕ to jump". Konuşma satırları dokunulmadan kalır.
public enum ButtonPrompts {
    /// Her zaman kumanda düğmesi olan simgeler ve adlar (yazı tanıma bazen köşeli parantezle okur).
    private static let buttons: Set<String> = [
        "R1", "R2", "R3", "L1", "L2", "L3", "OPTIONS", "TOUCHPAD",
        "✕", "×", "⨯", "✖", "○", "◯", "●", "□", "▢", "◻", "■", "△", "▲", "⨂",
        // Nino: yazı tanıma PS simgelerini bu karakterlere çeviriyor ("Hold & to …", "hold ® to …").
        "&", "®", "©", "@", "⊗", "Ⓧ", "ⓧ",
        // L1/L2/R1/R2 simgeleri yazı tanımada böyle okunuyor ("Hold LZ to aim", "RZ Shoot").
        "L", "R", "LZ", "RZ", "LI", "RI", "L7", "R7",
        // Nino: RDR2'nin ✕ simgesi bazen "*" okunuyor ("SELECT * BACK O").
        "*",
        // Nino: görüntüden tanınan simgeler (ButtonIcons): yön tuşları, dokunmatik yüzey, harita işareti.
        "↑", "↓", "←", "→", "✜", "▦", "◆",
    ]
    /// Simge yazı tanımada harfe dönüşebilir; yalnız ipucu kalıbında düğme sayılır.
    private static let lookalikes: Set<String> = ["X", "O"]
    private static let verbs: Set<String> = ["press", "hold", "tap", "push", "use", "mash", "release", "double", "pull", "click"]
    private static let brackets = CharacterSet(charactersIn: "()[]{}<>「」")

    /// Nino: tek başına bir düğme simgesi mi ("✕", "R2", yazı tanımanın "&" ya da tek "O"/"X" okuduğu simge).
    public static func isIcon(_ token: String) -> Bool {
        let t = token.trimmingCharacters(in: brackets)
        if isCircledLetter(t) { return true }
        return buttons.contains(t.uppercased()) || t == "O" || t == "X"
    }

    /// Haritadaki görev işareti ("Ⓑ"): görüntüden tanınan renkli dairedeki harf.
    static func isCircledLetter(_ t: String) -> Bool {
        guard t.unicodeScalars.count == 1, let v = t.unicodeScalars.first?.value else { return false }
        return v >= 0x24B6 && v <= 0x24CF
    }

    /// Simgenin TV'de gösterilecek hali.
    public static func display(_ token: String) -> String {
        let t = token.trimmingCharacters(in: brackets)
        if isCircledLetter(t) || ["↑", "↓", "←", "→", "✜", "▦", "◆"].contains(t) { return t }
        switch t.uppercased() {
        case "O", "○", "◯": return "○"
        case "X", "✕", "×", "⨯", "✖", "⊗", "Ⓧ", "*": return "✕"
        case "□", "▢", "◻", "■": return "□"
        case "△", "▲": return "△"
        case "R1", "R2", "R3", "L1", "L2", "L3", "OPTIONS", "TOUCHPAD": return t.uppercased()
        case "LZ": return "L2"
        case "RZ": return "R2"
        case "LI", "L7", "L": return "L1"
        case "RI", "R7", "R": return "R1"
        default: return "●"
        }
    }

    /// Nino: yuvarlak L3/R3 simgesi yazı tanımada "13)", "(13", "L3]" gibi okunuyor; satır o zaman altyazı sanılıp
    /// çevrilmeye gidiyordu ("13) Stand up"). Bu biçimler düğme adına çevrilir. Yalnız parantezli ya da harfli
    /// biçimler sayılır, düz "13" (sayı) olduğu gibi kalır.
    public static func normalizedIcons(_ line: String) -> String {
        var s = line
        s = s.replacingOccurrences(of: #"(?<![\w])[\(\[]?[1lI|]([123])[\)\]](?=\s|$)"#, with: "L$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![\w])[\(\[][1lI|]([123])(?=\s|$)"#, with: "L$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![\w])[\(\[]?([LR])([123])[\)\]](?=\s|$)"#, with: "$1$2", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![\w])[\(\[]([LR])([123])(?=\s|$)"#, with: "$1$2", options: .regularExpression)
        // "(C1" = L1 simgesi.
        s = s.replacingOccurrences(of: #"(?<![\w])[\(\[]C([12])[\)\]]?(?=\s|$)"#, with: "L$1", options: .regularExpression)
        // Nino: tek düğme simgesi iki kez okunabiliyor ("Hold ✕ ✕ to …": simge hem yazı içinden hem kenardan bulunuyor).
        // Yan yana aynı simge tek simgedir.
        s = s.replacingOccurrences(of: #"([✕○△□↑↓←→✜▦◆●Ⓐ-Ⓩ])(?:\s+\1)+"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![\w])([LR][123]|OPTIONS|TOUCHPAD)(?:\s+\1)+(?![\w])"#, with: "$1", options: .regularExpression)
        return s
    }

    public static func isPrompt(_ line: String) -> Bool {
        let tokens = line
            .components(separatedBy: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "+/")))
            .map { $0.trimmingCharacters(in: brackets) }
            .filter { !$0.isEmpty }
        guard let first = tokens.first else { return false }
        // Nino: oyunun menü açıklaması ("PHOTO MODE  SELECT") altyazı değildir.
        if line == line.uppercased(), line.uppercased().contains("PHOTO MODE") { return true }

        let isButton = { (token: String) in buttons.contains(token.uppercased()) }
        let words = tokens.filter { !isButton($0) && $0.contains(where: \.isLetter) }

        // "R2 Swing", "△ Pick up", "L1 R1 Spartan Rage"
        if isButton(first) { return words.count <= 5 }
        // "PHOTO MODE L1 + R1": düğme sonda, önünde kısa ve noktalamasız bir eylem adı.
        if let last = tokens.last, isButton(last), words.count <= 4, !SubtitleStabilizer.endsSentence(line) { return true }
        // "X Interact", "O Back": ardından kısa, büyük harfle başlayan, noktalamasız bir eylem gelir.
        if lookalikes.contains(first), tokens.count >= 2, tokens.count <= 4,
           tokens[1].first?.isUppercase == true, !SubtitleStabilizer.endsSentence(line) {
            return true
        }
        // "Press ✕ to jump", "Hold R2 to aim"
        if verbs.contains(first.lowercased()), tokens.count >= 2, tokens.count <= 10 {
            let second = tokens[1]
            if isButton(second) || lookalikes.contains(second) { return true }
            // Nino: simge okunamayınca düşer ("Hold  to see nearby places"); "Hold to …" yine tuş ipucudur.
            if second.lowercased() == "to", tokens.count >= 4 { return true }
        }
        // Nino: "Double tap and hold ✕ to ride alongside Dutch": fiil ile başlayıp ortasında bir düğme simgesi olan,
        // cümle gibi bitmeyen kısa satır.
        if verbs.contains(first.lowercased()), tokens.count <= 14, tokens.contains(where: isButton),
           !SubtitleStabilizer.endsSentence(line) {
            return true
        }
        return false
    }
}
