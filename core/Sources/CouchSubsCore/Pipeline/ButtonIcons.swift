// SPDX-License-Identifier: AGPL-3.0-only

import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Nino: yazı tanımanın atladığı ya da yanlış okuduğu kumanda simgesini görüntüden tanır. Oyunlar düğmeyi yazının içine
/// küçük bir resim olarak koyar ("Hold ⓧ to …"); Vision o resmi ya hiç okumaz ya da "•", "O", "X" sanır.
///
/// Sıra: simgenin kendisi bulunur (kesitteki en büyük, kareye yakın parlak leke). Renkliyse (sarı "B" gibi) harita
/// işaretidir. Artı biçimliyse yön tuşudur, enliyse dokunmatik yüzeydir. Değilse içindeki yazı ("L3", "R2") okunur;
/// yazı yoksa içindeki sembol (koyu ya da açık olabilir) ✕ ○ △ □ şablonlarıyla karşılaştırılır.
enum ButtonIcons {
    /// `box`: simgenin görüntüdeki kabaca yeri (0–1, üstten). Tanınamazsa nil.
    static func classify(_ image: CGImage, box: TextBox) -> String? {
        guard let crop = crop(image, box) else { return nil }
        let result = classify(crop)
        #if DEBUG
        dump(crop, result)
        #endif
        return result
    }

    static func classify(_ crop: CGImage) -> String? {
        guard let gray = Gray(crop, height: 48), let blob = gray.iconBlob() else { return nil }
        let w = blob.maxX - blob.minX + 1, h = blob.maxY - blob.minY + 1
        let aspect = Double(w) / Double(h)
        // Renkli (ör. sarı) daire: düğme değil, haritadaki görev işareti; içindeki harf daire içinde gösterilir.
        if blob.saturation > 0.28 {
            if let letter = readText(crop), letter.count == 1, let scalar = letter.unicodeScalars.first,
               scalar.value >= 65, scalar.value <= 90 {
                return String(UnicodeScalar(0x24B6 + scalar.value - 65)!)
            }
            return "◆"
        }
        if aspect < 0.62 { return nil }
        if let pad = gray.dpad(blob) { return pad }
        // Yazı simgenin kendisinden okunur (sıkı kesit; koyu yazı beyaz kutuda olabilir, ters renkle de denenir).
        let scale = Double(crop.height) / Double(gray.height)
        let padX = Double(w) * 0.15, padY = Double(h) * 0.15
        let tight = CGRect(x: (Double(blob.minX) - padX) * scale, y: (Double(blob.minY) - padY) * scale,
                           width: (Double(w) + 2 * padX) * scale, height: (Double(h) + 2 * padY) * scale)
            .intersection(CGRect(x: 0, y: 0, width: crop.width, height: crop.height)).integral
        let iconImage = crop.cropping(to: tight) ?? crop
        if let label = readLabel(iconImage) ?? inverted(iconImage).flatMap(readLabel) ?? readLabel(crop) { return label }
        // Dokunmatik yüzey: yazısız, en boyunun ~1,6 katı, içi dikey çizgili.
        if aspect > 1.45, gray.stripes(in: blob) >= 4 { return "▦" }
        // Yazılı kutu ama yazı okunamadı: daire/kare sembol sanılmasın.
        if aspect > 1.15 { return nil }
        return gray.symbol(in: blob)
    }

    /// Simgenin aranacağı kesit: boşluğun tamamı (dar ise satır yüksekliği kadar genişletilir), satırın ~1,6 katı yükseklik.
    private static func crop(_ image: CGImage, _ box: TextBox) -> CGImage? {
        let w = Double(image.width), h = Double(image.height)
        let lineHeight = (box.bottom - box.top) * h
        let cy = (box.top + box.bottom) / 2 * h
        var left = box.left * w, right = box.right * w
        let minWidth = lineHeight * 1.4
        if right - left < minWidth {
            let cx = (left + right) / 2
            left = cx - minWidth / 2
            right = cx + minWidth / 2
        }
        let rect = CGRect(x: left - 2, y: cy - lineHeight, width: right - left + 4, height: lineHeight * 2)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h)).integral
        guard rect.width >= 6, rect.height >= 6 else { return nil }
        return image.cropping(to: rect)
    }

    /// Simgenin içindeki "L2", "R1", "L3", "OPTIONS" gibi yazı.
    private static func readLabel(_ crop: CGImage) -> String? {
        guard var text = readText(crop)?.uppercased().filter({ $0.isLetter || $0.isNumber }) else { return nil }
        if text.hasPrefix("OPTION") { return "OPTIONS" }
        if text.count == 3, text.first == "C" || text.first == "I" { text.removeFirst() }
        // Kesite komşu harf karışabilir ("DL2T"): kısa yazının içinde L/R + rakam aranır.
        if text.count > 2, text.count <= 5,
           let r = text.range(of: #"[LR][123IZ7]"#, options: .regularExpression) { text = String(text[r]) }
        guard text.count == 2, let side = text.first, side == "L" || side == "R" else { return nil }
        text = String(side) + String(text.last!)
            .replacingOccurrences(of: "I", with: "1").replacingOccurrences(of: "Z", with: "2")
            .replacingOccurrences(of: "7", with: "1").replacingOccurrences(of: "B", with: "3")
        return ["L1", "L2", "L3", "R1", "R2", "R3"].contains(text) ? text : nil
    }

    private static func inverted(_ image: CGImage) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(rect)
        ctx.setBlendMode(.difference)
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }

    /// Vision çok kısa ve tek başına duran yazıyı ("L1") çoğu zaman okumaz: kesit, kenar rengiyle doldurulmuş geniş bir
    /// zeminin ortasına konur; önce doğru, olmazsa hızlı düzeyle okunur.
    private static func readText(_ crop: CGImage) -> String? {
        let images = [scaled(crop, to: 120), padded(crop).flatMap { scaled($0, to: 140) }].compactMap { $0 }
        for level in [VNRequestTextRecognitionLevel.accurate, .fast] { for big in images {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = level
            request.usesLanguageCorrection = false
            let text: String = autoreleasepool {
                try? VNImageRequestHandler(cgImage: big).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
            }
            if !text.isEmpty { return text }
        } }
        return nil
    }

    private static func padded(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let gray = Gray(image, height: max(8, h)) else { return nil }
        // Kenar pikselleri ortalaması zemin rengi olur.
        var sum = 0.0, n = 0
        for x in 0..<gray.width { sum += gray.luma[x] + gray.luma[(gray.height - 1) * gray.width + x]; n += 2 }
        let edge = sum / Double(max(n, 1))
        let cw = w * 4, ch = h * 2
        guard let ctx = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: edge, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: cw, height: ch))
        ctx.draw(image, in: CGRect(x: (cw - w) / 2, y: (ch - h) / 2, width: w, height: h))
        return ctx.makeImage()
    }

    private static func scaled(_ image: CGImage, to height: Int) -> CGImage? {
        let factor = max(1, Double(height) / Double(image.height))
        let width = Int(Double(image.width) * factor), height = Int(Double(image.height) * factor)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    #if DEBUG
    /// Geliştirme: NINO_ICON_DUMP klasörüne her simge kesiti ve sonucu yazılır.
    private static func dump(_ crop: CGImage, _ result: String?) {
        guard let dir = ProcessInfo.processInfo.environment["NINO_ICON_DUMP"] else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("icon-\(UUID().uuidString.prefix(6))-\(result ?? "nil").png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, crop, nil)
        CGImageDestinationFinalize(dest)
    }
    #endif
}

/// Kesitin gri tonlu ve renk doygunluğu tutan küçük kopyası (satırlar üstten).
private struct Gray {
    let width: Int, height: Int
    var luma: [Double] = []
    var sat: [Double] = []

    struct Blob {
        var minX: Int, minY: Int, maxX: Int, maxY: Int
        var pixels: Set<Int>
        var saturation: Double
    }

    init?(_ image: CGImage, height target: Int) {
        let scale = Double(target) / Double(image.height)
        width = max(4, Int(Double(image.width) * scale)); height = target
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let ok = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        // Bellekteki ilk satır görüntünün üst satırıdır.
        luma.reserveCapacity(width * height); sat.reserveCapacity(width * height)
        for i in 0..<(width * height) {
            let r = Double(rgba[i * 4]) / 255, g = Double(rgba[i * 4 + 1]) / 255, b = Double(rgba[i * 4 + 2]) / 255
            luma.append(0.299 * r + 0.587 * g + 0.114 * b)
            let mx = max(r, g, b), mn = min(r, g, b)
            sat.append(mx > 0.15 ? (mx - mn) / mx : 0)
        }
    }

    /// Otsu eşiği: parlak ile koyuyu en iyi ayıran değer.
    func otsu(_ values: [Double]) -> Double {
        var hist = [Double](repeating: 0, count: 64)
        for v in values { hist[min(63, max(0, Int(v * 63.999)))] += 1 }
        let total = Double(values.count)
        var sumAll = 0.0
        for i in 0..<64 { sumAll += Double(i) * hist[i] }
        var sumB = 0.0, wB = 0.0, best = 0.0, threshold = 32
        for i in 0..<64 {
            wB += hist[i]; if wB == 0 { continue }
            let wF = total - wB; if wF == 0 { break }
            sumB += Double(i) * hist[i]
            let mB = sumB / wB, mF = (sumAll - sumB) / wF
            let between = wB * wF * (mB - mF) * (mB - mF)
            if between > best { best = between; threshold = i }
        }
        return (Double(threshold) + 0.5) / 64
    }

    /// Kesitteki simge: yüksekliği kesitin üçte birinden büyük, kareye yakın, ortaya yakın en büyük parlak leke.
    func iconBlob() -> Blob? {
        let t = otsu(luma)
        var mask = luma.map { $0 > t }
        var best: Blob?
        var bestScore = 0.0
        for start in 0..<(width * height) where mask[start] {
            var stack = [start], pixels: [Int] = []
            mask[start] = false
            var minX = width, minY = height, maxX = 0, maxY = 0
            while let p = stack.popLast() {
                pixels.append(p)
                let x = p % width, y = p / width
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    let n = ny * width + nx
                    if mask[n] { mask[n] = false; stack.append(n) }
                }
            }
            let bw = maxX - minX + 1, bh = maxY - minY + 1
            guard bh >= height / 3, bh < height else { continue }
            let aspect = Double(bw) / Double(bh)
            guard aspect > 0.4, aspect < 2.2 else { continue }
            let cx = Double(minX + maxX) / 2 / Double(width)
            let squareness = 1 - min(1, abs(log(aspect)))
            let score = Double(bw * bh) * (0.5 + squareness) * (1.2 - abs(cx - 0.5))
            if score > bestScore {
                bestScore = score
                let s = pixels.reduce(0.0) { $0 + sat[$1] } / Double(max(pixels.count, 1))
                best = Blob(minX: minX, minY: minY, maxX: maxX, maxY: maxY, pixels: Set(pixels), saturation: s)
            }
        }
        return best
    }

    /// Lekenin orta satırında açık-koyu geçiş sayısının yarısı (dokunmatik yüzey ızgarası çok çizgilidir).
    func stripes(in b: Blob) -> Int {
        let y = (b.minY + b.maxY) / 2
        let row = (b.minX...b.maxX).map { luma[y * width + $0] }
        let t = otsu(row)
        var flips = 0
        for i in 1..<row.count where (row[i] > t) != (row[i - 1] > t) { flips += 1 }
        return flips / 2
    }

    /// Yön tuşu: artı biçimli leke; ötekilerden parlak kol yönü verir.
    func dpad(_ b: Blob) -> String? {
        let w = b.maxX - b.minX + 1, h = b.maxY - b.minY + 1
        guard w >= 6, h >= 6 else { return nil }
        func cell(_ cx: Int, _ cy: Int) -> (fill: Double, light: Double) {
            let x0 = b.minX + cx * w / 3, x1 = max(x0 + 1, b.minX + (cx + 1) * w / 3)
            let y0 = b.minY + cy * h / 3, y1 = max(y0 + 1, b.minY + (cy + 1) * h / 3)
            var on = 0, n = 0, light = 0.0
            for y in y0..<y1 { for x in x0..<x1 {
                n += 1
                let p = y * width + x
                if b.pixels.contains(p) { on += 1 }
                light += luma[p]
            } }
            return (Double(on) / Double(max(n, 1)), light / Double(max(n, 1)))
        }
        let corners = [cell(0, 0), cell(2, 0), cell(0, 2), cell(2, 2)].map(\.fill)
        let arms = [("↑", cell(1, 0)), ("←", cell(0, 1)), ("→", cell(2, 1)), ("↓", cell(1, 2))]
        guard corners.max()! < 0.2, arms.allSatisfy({ $0.1.fill > 0.35 }) else { return nil }
        let sorted = arms.sorted { $0.1.light > $1.1.light }
        return sorted[0].1.light > sorted[1].1.light * 1.12 ? sorted[0].0 : "✜"
    }

    /// Simgenin içindeki sembol: iç dairede azınlıkta kalan renk (beyaz daire üstünde koyu çarpı ya da koyu zeminde
    /// beyaz çarpı) ✕ ○ △ □ şablonlarıyla karşılaştırılır.
    func symbol(in b: Blob) -> String? {
        // Simgeler iç içe halkalı olabilir (halka, gri disk, içinde kare): sembol birkaç iç yarıçapta aranır, en iyi
        // eşleşme seçilir.
        var best: (name: String, score: Double)?
        for factor in [0.74, 0.6, 0.48] {
            if let found = symbol(in: b, radius: factor), best == nil || found.score > best!.score { best = found }
        }
        guard let best, best.score > 0.3 else { return nil }
        return best.name
    }

    private func symbol(in b: Blob, radius factor: Double) -> (name: String, score: Double)? {
        let w = b.maxX - b.minX + 1, h = b.maxY - b.minY + 1
        let cx = Double(b.minX + b.maxX) / 2, cy = Double(b.minY + b.maxY) / 2
        let r = Double(min(w, h)) / 2 * factor
        guard r >= 4 else { return nil }
        var inner: [(x: Double, y: Double, v: Double)] = []
        for y in Int(cy - r)...Int(cy + r) { for x in Int(cx - r)...Int(cx + r) {
            guard x >= 0, y >= 0, x < width, y < height else { continue }
            let dx = Double(x) - cx, dy = Double(y) - cy
            guard dx * dx + dy * dy <= r * r else { continue }
            inner.append((dx / r, dy / r, luma[y * width + x]))
        } }
        guard inner.count > 30 else { return nil }
        let values = inner.map(\.v)
        guard (values.max() ?? 0) - (values.min() ?? 0) > 0.15 else { return nil }
        let t = otsu(values)
        let bright = inner.filter { $0.v > t }.count
        let minorityIsBright = bright * 2 < inner.count
        let marks = inner.filter { minorityIsBright ? $0.v > t : $0.v <= t }
        guard marks.count >= 6 else { return nil }
        // İşaretli noktalar sembolün kendi kutusuna oranlanır, 16x16 ızgarada şablonlarla karşılaştırılır.
        let mx0 = marks.map(\.x).min()!, mx1 = marks.map(\.x).max()!, my0 = marks.map(\.y).min()!, my1 = marks.map(\.y).max()!
        let n = Templates.n
        var grid = [Bool](repeating: false, count: n * n)
        for m in marks {
            let gx = min(n - 1, Int((m.x - mx0) / max(mx1 - mx0, 0.01) * Double(n)))
            let gy = min(n - 1, Int((m.y - my0) / max(my1 - my0, 0.01) * Double(n)))
            grid[gy * n + gx] = true
        }
        // Karenin köşeleri doludur; daire ve çarpıda köşe hücreleri boş kalır.
        var cornerMarks = 0
        for y in 0..<n { for x in 0..<n where grid[y * n + x] && (x < 2 || x > n - 3) && (y < 2 || y > n - 3) { cornerMarks += 1 } }
        var best: (name: String, score: Double)?
        for (name, template) in Templates.all {
            if name == "□" && cornerMarks < 3 { continue }
            let score = Templates.similarity(grid, template)
            if ProcessInfo.processInfo.environment["NINO_ICON_DEBUG"] != nil { print("SYMBOL", factor, name, score) }
            if best == nil || score > best!.score { best = (name, score) }
        }
        return best
    }
}

/// ✕ ○ △ □ şablonları (16x16, sembolün kendi kutusuna oranlı çizgi).
private enum Templates {
    static let n = 16
    static let all: [(String, [Bool])] = [
        ("✕", draw { x, y in abs(x - y) < 0.17 || abs(x + y - 1) < 0.17 }),
        ("○", draw { x, y in let d = hypot(x - 0.5, y - 0.5); return d > 0.34 && d < 0.52 }),
        ("□", draw { x, y in x < 0.18 || x > 0.82 || y < 0.18 || y > 0.82 }),
        ("△", draw { x, y in
            // Tepe üstte; iki yan kenar ve taban.
            let half = y / 2
            return y > 0.82 || abs(x - (0.5 - half)) < 0.12 || abs(x - (0.5 + half)) < 0.12
        }),
    ]

    static func draw(_ f: (Double, Double) -> Bool) -> [Bool] {
        var g = [Bool](repeating: false, count: n * n)
        for y in 0..<n { for x in 0..<n { g[y * n + x] = f((Double(x) + 0.5) / Double(n), (Double(y) + 0.5) / Double(n)) } }
        return g
    }

    private static func grown(_ g: [Bool]) -> [Bool] {
        var out = g
        for y in 0..<n { for x in 0..<n where g[y * n + x] {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                if nx >= 0, ny >= 0, nx < n, ny < n { out[ny * n + nx] = true }
            }
        } }
        return out
    }

    /// İşaretlerin ne kadarı şablonda (bir hücre payla) × şablonun ne kadarı işaretlenmiş (bir hücre payla).
    static func similarity(_ a: [Bool], _ t: [Bool]) -> Double {
        let gt = grown(t), ga = grown(a)
        var inA = 0, aCount = 0, inT = 0, tCount = 0
        for i in 0..<(n * n) {
            if a[i] { aCount += 1; if gt[i] { inA += 1 } }
            if t[i] { tCount += 1; if ga[i] { inT += 1 } }
        }
        return Double(inA) / Double(max(aCount, 1)) * Double(inT) / Double(max(tCount, 1))
    }
}
