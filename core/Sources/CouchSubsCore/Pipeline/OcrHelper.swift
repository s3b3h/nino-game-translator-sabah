// SPDX-License-Identifier: AGPL-3.0-only

#if os(macOS)
import CoreGraphics
import Foundation

/// Nino 4.0.5: Ayrı süreçte yazı tanıma (yedek okuyucu). CouchSubs'ın #722 çözümünden (OcrHelper) uyarlandı.
///
/// Apple'ın yazı tanıması (Vision) uzun oyunda arada bir kilitleniyor ve kilit süreç genelinde: aynı süreçte yeni
/// istek, yeni okuyucu, işlemci yolu da bekliyor (21 Kasım 2026'da Nino'da denendi). Eskiden Nino kendini yeniden
/// açıyor, PS5 bağlantısı kopuyordu. Artık takılınca okumalar ayrı bir süreçteki yedek okuyucuya gider; PS5 akışı ve
/// TV bağlantısı ana süreçte sürer. Yardımcı, uygulamanın kendi çalıştırılabilir dosyasıdır (`--ocr-helper`, pencere
/// açmaz); kareyi stdin'den alır, satırları stdout'a yazar. Yardımcı da takılırsa öldürülür, yenisi açılır.
public enum OcrHelper {
    /// Uygulama bu argümanla açıldıysa pencere açmadan yardımcı olarak çalışır.
    public static let argument = "--ocr-helper"

    struct Header: Codable {
        var width: Int
        var height: Int
        var language: String
        var deep: Bool
        var edgeIcons: Bool
        var fast: Bool
    }

    struct Line: Codable {
        var t: String
        var c: Double?
        /// Kutu: sol, üst, sağ, alt.
        var b: [Double]?
    }

    struct Reply: Codable {
        var lines: [Line]?
        var error: String?
    }

    public enum Failure: Error, Equatable {
        /// Yardımcı açılamadı, okuma sürerken kapandı ya da süresinde dönmedi.
        case closed
        case failed(String)
    }

    static func encode(_ reading: Reading) -> [Line] {
        reading.lines.map { Line(t: $0.text, c: $0.confidence, b: $0.box.map { [$0.left, $0.top, $0.right, $0.bottom] }) }
    }

    static func decode(_ lines: [Line]) -> Reading {
        Reading(lines: lines.map { line in
            let box = line.b.flatMap { $0.count == 4 ? TextBox(left: $0[0], top: $0[1], right: $0[2], bottom: $0[3]) : nil }
            return TextLine(line.t, box: box, confidence: line.c)
        })
    }

    /// Karenin RGBA baytları (8 bit, satır başına `width * 4`).
    static func pixels(of image: CGImage) -> Data? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var data = Data(count: width * height * 4)
        let drawn: Bool = data.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? data : nil
    }

    static func image(from data: Data, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, data.count == width * height * 4, let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: - Çerçeveleme: [uzunluk: UInt32 BE][bayt]

    static func write(_ data: Data, to fd: Int32) -> Bool {
        var length = UInt32(data.count).bigEndian
        return writeAll(Data(bytes: &length, count: 4), to: fd) && writeAll(data, to: fd)
    }

    static func read(from fd: Int32, limit: Int = 256 * 1024 * 1024) -> Data? {
        guard let head = readExactly(4, from: fd) else { return nil }
        let length = Int(head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
        guard length <= limit else { return nil }
        return readExactly(length, from: fd)
    }

    private static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += written
            }
            return true
        }
    }

    private static func readExactly(_ count: Int, from fd: Int32) -> Data? {
        var data = Data(count: count)
        let complete: Bool = data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < count {
                let got = Darwin.read(fd, buffer.baseAddress! + offset, count - offset)
                if got < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                if got == 0 { return false }
                offset += got
            }
            return true
        }
        return complete ? data : nil
    }

    // MARK: - Yardımcı süreç tarafı

    /// Yardımcının ana döngüsü: stdin kapanınca (uygulama kapandı) çıkar.
    static func serve(input: Int32 = STDIN_FILENO, output: Int32 = STDOUT_FILENO,
                      recognize: (CGImage, Header) throws -> Reading = OcrHelper.recognize) {
        while let head = read(from: input, limit: 64 * 1024) {
            guard let header = try? JSONDecoder().decode(Header.self, from: head), let body = read(from: input) else { return }
            var reply = Reply()
            if let image = image(from: body, width: header.width, height: header.height) {
                do { reply.lines = encode(try recognize(image, header)) } catch { reply.error = "\(error)" }
            } else {
                reply.error = "kare çözülemedi"
            }
            guard let data = try? JSONEncoder().encode(reply), write(data, to: output) else { return }
        }
    }

    /// Yardımcıdaki okuma: Nino'nun kendi okuyucusu (simgeler, satır birleştirme aynı), istenirse hızlı düzeyde.
    static func recognize(_ image: CGImage, _ header: Header) throws -> Reading {
        var reader = VisionReader(language: header.language, edgeIcons: header.edgeIcons)
        reader.fastLevel = header.fast
        return try reader.readLines(image, deep: header.deep)
    }

    /// Uygulamanın `main`'inden çağrılır; dönmez.
    public static func runAsHelper() -> Never {
        let parent = getppid()
        Thread.detachNewThread {
            // Üst süreç kapandıysa (launchd'ye devredildiyse) yardımcı da kapanır.
            while getppid() == parent { Thread.sleep(forTimeInterval: 2) }
            exit(0)
        }
        serve()
        exit(0)
    }
}

/// Çalışan bir yardımcı süreç; istekler sırayla, senkron.
final class OcrHelperProcess: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()

    init(executable: URL) throws {
        process.executableURL = executable
        process.arguments = [OcrHelper.argument]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .userInitiated
        // Yardımcı kapanmışken yazmak süreci SIGPIPE ile öldürmesin; yazma hata döner.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try process.run()
    }

    var isRunning: Bool { process.isRunning }

    func recognize(_ image: CGImage, header: OcrHelper.Header) throws -> Reading {
        guard let pixels = OcrHelper.pixels(of: image), let head = try? JSONEncoder().encode(header)
        else { throw OcrHelper.Failure.failed("kare hazırlanamadı") }
        let fd = input.fileHandleForWriting.fileDescriptor
        guard OcrHelper.write(head, to: fd), OcrHelper.write(pixels, to: fd),
              let data = OcrHelper.read(from: output.fileHandleForReading.fileDescriptor),
              let reply = try? JSONDecoder().decode(OcrHelper.Reply.self, from: data) else { throw OcrHelper.Failure.closed }
        if let error = reply.error { throw OcrHelper.Failure.failed(error) }
        return OcrHelper.decode(reply.lines ?? [])
    }

    /// Süreci öldürür; süren `recognize` `closed` ile döner.
    func kill() {
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        try? input.fileHandleForWriting.close()
    }

    deinit { kill() }
}

/// Nino'nun yedek okuyucusu: asıl süreçteki Vision takılıyken okumaları yardımcı süreçte yapar.
///
/// Yeni açılan bir süreçte ilk Vision okuması (model yüklenirken) 45 sn'yi bulabiliyor; sonrakiler 0,1-0,2 sn
/// (21 Kasım 2026, testte ölçüldü). Bu yüzden yardımcı takılma anında değil, oturumun ilk okumasında açılır ve o kareyle
/// ısıtılır (`prepare`); oturum boyunca hazır bekler. Takılmada hemen devralır. Hazır değilken gelen okuma
/// `notReady` ile atlanır. Her okuma en çok `readLimit` beklenir; dönmezse yardımcı öldürülür ve yenisi ısıtılır.
/// Art arda `maxFailures` kez düşerse yedek bırakılır (`isExhausted`; Mac son çare olarak Nino'yu yeniden açar).
public final class OcrHelperReader: @unchecked Sendable {
    static let readLimit: TimeInterval = 12
    /// Isıtma okuması (model yüklemesi dahil) en çok bu kadar beklenir.
    static let warmLimit: TimeInterval = 240
    public static let maxFailures = 3

    public enum NotReady: Error { case warming }

    private let executable: URL
    private let lock = NSLock()
    private var helper: OcrHelperProcess?
    private var ready = false
    private var failures = 0
    private var serial = 0
    /// Günlük için.
    public var onLog: (@Sendable (String) -> Void)?

    public init(executable: URL) {
        self.executable = executable
    }

    /// Yardımcı art arda düştü; yedek artık işe yaramıyor.
    public var isExhausted: Bool { lock.withLock { failures >= Self.maxFailures } }
    /// Yardımcı ısındı, okumayı hemen devralabilir.
    public var isReady: Bool { lock.withLock { ready } }

    /// Yardımcı yoksa açar ve bu kareyle (arka planda) ısıtır. Sık çağrılabilir; açıksa hiçbir şey yapmaz.
    public func prepare(_ image: CGImage, language: String) {
        let helper: OcrHelperProcess? = lock.withLock {
            guard self.helper == nil, failures < Self.maxFailures else { return nil }
            do {
                let started = try OcrHelperProcess(executable: executable)
                self.helper = started
                ready = false
                return started
            } catch {
                failures += 1
                onLog?("yedek okuyucu açılamadı: \(error.localizedDescription)")
                return nil
            }
        }
        guard let helper else { return }
        let header = OcrHelper.Header(width: image.width, height: image.height, language: language, deep: false, edgeIcons: false, fast: false)
        let begun = Date()
        Thread.detachNewThread { [weak self] in
            let ok = (try? helper.recognize(image, header: header)) != nil
            guard let self else { return helper.kill() }
            self.lock.withLock {
                guard self.helper === helper else { return }
                if ok {
                    self.ready = true
                    self.onLog?(String(format: "yedek okuyucu hazır (ayrı süreç, %.0f sn'de ısındı)", Date().timeIntervalSince(begun)))
                } else {
                    self.helper = nil
                    self.failures += 1
                    self.onLog?("yedek okuyucu ısınamadı (\(self.failures)/\(Self.maxFailures))")
                }
            }
            if !ok { helper.kill() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.warmLimit) { [weak self] in
            if let self, self.lock.withLock({ self.helper === helper && !self.ready }) { helper.kill() }
        }
    }

    public func read(_ image: CGImage, language: String, deep: Bool, edgeIcons: Bool) throws -> Reading {
        let (helper, token) = try lock.withLock { () throws -> (OcrHelperProcess?, Int) in
            guard failures < Self.maxFailures else { throw OcrHelper.Failure.closed }
            guard let helper, ready else { return (nil, 0) }
            serial += 1
            return (helper, serial)
        }
        guard let helper else {
            // Isınmamış: bu kare atlanır, yardımcı (yoksa) bu kareyle açılıp ısıtılır.
            prepare(image, language: language)
            throw NotReady.warming
        }
        // Süresinde dönmeyen okuma: yardımcı öldürülür, bekleyen okuma `closed` ile döner.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.readLimit) { [weak self] in
            guard let self, self.lock.withLock({ self.serial == token }) else { return }
            helper.kill()
        }
        let header = OcrHelper.Header(width: image.width, height: image.height, language: language, deep: deep,
                                      edgeIcons: edgeIcons, fast: false)
        do {
            let reading = try helper.recognize(image, header: header)
            lock.withLock { failures = 0; serial += 1 }
            return reading
        } catch OcrHelper.Failure.closed {
            let count: Int = lock.withLock {
                failures += 1
                serial += 1
                if self.helper === helper { self.helper = nil; ready = false }
                return failures
            }
            helper.kill()
            onLog?("yedek okuyucu yanıt vermedi, yenisi ısıtılıyor (\(count)/\(Self.maxFailures))")
            prepare(image, language: language)
            throw OcrHelper.Failure.closed
        }
    }

    /// Asıl okuyucu düzeldi: yardımcı ısınmış hâlde bekler; düşme sayacı sıfırlanır.
    public func standDown() {
        lock.withLock { failures = 0; serial += 1 }
    }

    /// Oturum bitti: yardımcı kapatılır.
    public func shutdown() {
        let had: Bool = lock.withLock {
            let had = helper != nil
            helper?.kill()
            helper = nil
            ready = false
            failures = 0
            serial += 1
            return had
        }
        if had { onLog?("yedek okuyucu kapatıldı") }
    }

    deinit { helper?.kill() }
}
#endif
