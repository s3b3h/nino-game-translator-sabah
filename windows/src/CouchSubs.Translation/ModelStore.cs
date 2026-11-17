// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;

namespace CouchSubs.Translation;

/// <summary>İndirilecek tek model dosyası: adı, kaynağı, beklenen boyutu ve SHA-256 özeti.</summary>
public sealed record ModelFile(string Name, Uri Url, long Size, string Sha256);

/// <summary>
/// Çeviri modelinin diskteki yeri ve indirilmesi. Dosyalar önce <c>.part</c> olarak iner, özet tutarsa
/// asıl adına taşınır; böylece asıl adla duran her dosya doğrulanmıştır ve yarım iniş kurulu sayılmaz.
/// Kesilen iniş, sunucu izin verirse kaldığı yerden sürer.
/// </summary>
public sealed class ModelStore
{
    public const string SourceSpmFile = "source.spm";
    public const string VocabFile = "vocab.json";
    // Nino: Türkçe dışındaki ücretsiz modeller (Xenova'nın int8 ONNX dönüşümleri) ONNX Runtime ile çalışır.
    public const string EncoderFile = "encoder_model_int8.onnx";
    public const string DecoderFile = "decoder_model_merged_int8.onnx";

    private const string PartSuffix = ".part";

    /// <summary>Uzun süre veri gelmezse bağlantı takılmış sayılır; iniş yeniden denenebilsin diye hata verir.</summary>
    private static readonly TimeSpan StallTimeout = TimeSpan.FromSeconds(60);

    // Depo belirli bir sürüme sabitlenir: dosyalar değişirse özetler de geçersiz kalırdı.
    private const string Revision = "ce128ea834a090aca240e4e113e7756e06cc78e0";
    private static readonly string BaseUrl = $"https://huggingface.co/onnx-community/opus-mt-tc-big-en-tr/resolve/{Revision}/";

    /// <summary>CTranslate2 modelinin belirteçleyicisi için özgün OPUS-MT sözlüğü.</summary>
    public static IReadOnlyList<ModelFile> EnglishTurkish { get; } =
    [
        new(SourceSpmFile, new Uri(BaseUrl + SourceSpmFile), 796_953,
            "180d3f94ddfee5585d78b702290ded0f4f9bd40f299349c8383b32a579fefad4"),
        new(VocabFile, new Uri(BaseUrl + VocabFile), 1_501_287,
            "01ef522455d2bf22b0716416ee34688cc2b3f5fa257f742665d21b6acc450ac1"),
    ];

    // Nino: İngilizce→Arapça. Helsinki-NLP opus-mt-en-ar (CC BY 4.0), Xenova'nın int8 ONNX dönüşümü (transformers.js);
    // dosya adları Türkçe modelinkiyle aynı. Özetler Hugging Face'in LFS kayıtlarından (onnx) ve dosyaların kendisinden
    // (source.spm, vocab.json) alındı; depo sürüme sabitlenir.
    private const string ArabicRevision = "034a684356c19021a187cda4d7f823298b913921";
    private static readonly string ArabicBaseUrl = $"https://huggingface.co/Xenova/opus-mt-en-ar/resolve/{ArabicRevision}/";

    /// <summary>opus-mt-en-ar çok hedeflidir: girdinin başına bu hedef dil belirteci konur.</summary>
    public const string ArabicTargetPrefix = ">>ara<<";

    public static IReadOnlyList<ModelFile> EnglishArabic { get; } =
    [
        new(EncoderFile, new Uri(ArabicBaseUrl + "onnx/" + EncoderFile), 51_600_664,
            "045dce89bd4b5bd5d8f546b9e3f9b506a9dbae70c551e8744eac67564050ddfd"),
        new(DecoderFile, new Uri(ArabicBaseUrl + "onnx/" + DecoderFile), 58_878_333,
            "f2cd3894f105e5859d60cd66ad5f83356a3343e68f60c1997627a6e2d156f549"),
        new(SourceSpmFile, new Uri(ArabicBaseUrl + SourceSpmFile), 801_074,
            "81ac8f4d4ee271f4109eac67560a31f9c2d555463ba5eb95c32c6deee8ae819d"),
        new(VocabFile, new Uri(ArabicBaseUrl + VocabFile), 2_243_581,
            "8b74af9e4c1ec122b8d06362db6c38795e10ca2b0156b2110cf08d4716744b76"),
    ];

    // Nino: Hintçe, Endonezce, Vietnamca ve Felemenkçe. Helsinki-NLP opus-mt-en-hi/id/vi/nl (Apache-2.0), Xenova'nın int8
    // ONNX dönüşümü; Arapça modelle aynı yapı (en-vi Arapça gibi hedef belirteci ister, ötekiler istemez). Özetler Hugging Face'in LFS kayıtlarından
    // (onnx) ve dosyaların kendisinden (source.spm, vocab.json) alındı; her depo sürüme sabitlenir. Tayca, Urduca, Bengalce,
    // Malayca ve Filipince için bu biçimde model yok: o diller yalnız yapay zekâ motoruyla çevrilir.
    private static IReadOnlyList<ModelFile> Xenova(string pair, string revision, long encoder, string encoderSha,
        long decoder, string decoderSha, long spm, string spmSha, long vocab, string vocabSha)
    {
        var baseUrl = $"https://huggingface.co/Xenova/opus-mt-{pair}/resolve/{revision}/";
        return
        [
            new(EncoderFile, new Uri(baseUrl + "onnx/" + EncoderFile), encoder, encoderSha),
            new(DecoderFile, new Uri(baseUrl + "onnx/" + DecoderFile), decoder, decoderSha),
            new(SourceSpmFile, new Uri(baseUrl + SourceSpmFile), spm, spmSha),
            new(VocabFile, new Uri(baseUrl + VocabFile), vocab, vocabSha),
        ];
    }

    public static IReadOnlyList<ModelFile> EnglishHindi { get; } = Xenova("en-hi", "7aad72006a1588a9c3485ed6203aed99eebbc872",
        51_164_441, "8b53ce50ba917cf4b77d6713a01cb767d16a6a92fe4a56bec4d3576fb9d1e4e2",
        58_438_702, "7c21712321e7a02aa1f0f676b4beeef8cdccd0c295cdc642eea97991ce59b180",
        812_240, "fd4e951487aed00bae6a6c2ee4ef5d8d1db05fd098b19b608046c9334b58d24d",
        2_221_738, "be02f5dfb85054d4f25089f6b347b69d32e98ed4c3d181ed0c789904eb1e3d3b");

    public static IReadOnlyList<ModelFile> EnglishIndonesian { get; } = Xenova("en-id", "b3b41f654c2fb3286d007dee1da7b0f47fd27d82",
        47_501_593, "577591fb62f86b82b9cddd799bae274b8e9b489a7439bb13ea2d5c4510f34f08",
        54_747_238, "c36b784308b4983be64f076e237332709af48f7e575a9a535fd138d9fbdd468c",
        795_925, "e88300911c2c573ec5526777a1e84bae698d20925b82dcef9c7248bb0e537ed0",
        1_366_984, "cda834905a5d478c54a73abc98cc9155dc58217baa130cdf165411265b760d6b");

    public static IReadOnlyList<ModelFile> EnglishVietnamese { get; } = Xenova("en-vi", "30bcd461c0d7338ad106b36314d3eedc2d4e998c",
        46_932_760, "0aa4c958dc2171312b15d70e2fb1a036feca9ff5e098609ee0ea31ebd21b3c98",
        54_173_961, "c1ec8c85d68119cb419518d30a504ebf625f8e36d62f588c4e0a1466cd6d6e28",
        808_612, "fdd9ab486ca8ea060967105e30db7d8928729c78a67448711d2dd7c3153b37cd",
        1_299_764, "bcc8bbafeb0b6b58fecf244f8da996da9aa45dbea7871164f9c8ce480507f9fe");

    public static IReadOnlyList<ModelFile> EnglishDutch { get; } = Xenova("en-nl", "c3a0541231a7329b4492809fc2bd7ab7d2ceb0bc",
        53_764_376, "3857b90ec2dd0d5f2f4bb637dbe6f6f9e80d9cbed55391d1aa943cffa0cc628f",
        61_058_949, "3c6bf76b6711dfc3e73d7bf85b3964bd40f425b35d6b721118233b71b9a1ccd4",
        789_525, "d05781fde84b8793191528a7a176e1b17f96265388f602379ee6ae3139f59141",
        1_794_274, "b1fba91c620564d90848c5f77b03f13d17949790f8e7c7741e4a8ea13b8b0d91");

    /// <summary>Ücretsiz modeli olan hedef diller ve dosyaları; listede olmayan dil yalnız yapay zekâyla çevrilir.</summary>
    public static IReadOnlyDictionary<string, IReadOnlyList<ModelFile>> FreeModels { get; } =
        new Dictionary<string, IReadOnlyList<ModelFile>>
        {
            ["tr"] = EnglishTurkish, ["ar"] = EnglishArabic, ["hi"] = EnglishHindi,
            ["id"] = EnglishIndonesian, ["vi"] = EnglishVietnamese, ["nl"] = EnglishDutch,
        };

    /// <summary>Hedef dile göre model dosyaları (ücretsiz modeli olmayan dilde Türkçe model döner; önce <see cref="FreeModels"/> denetlenir).</summary>
    public static IReadOnlyList<ModelFile> FilesFor(string target) =>
        FreeModels.GetValueOrDefault(target.Length >= 2 ? target[..2].ToLowerInvariant() : target, EnglishTurkish);

    /// <summary>
    /// Hedef dile göre girdinin başına konacak belirteç: çok hedefli modellerde (en-ar ">>ara<<", en-vi ">>vie<<"; belirteç
    /// modelin vocab.json'ında bulunur). Tek hedefli modellerde (en-tr, en-hi, en-id, en-nl) belirteç yoktur.
    /// </summary>
    public static string? TargetPrefixFor(string target) =>
        target.StartsWith("ar", StringComparison.OrdinalIgnoreCase) ? ArabicTargetPrefix
        : target.StartsWith("vi", StringComparison.OrdinalIgnoreCase) ? VietnameseTargetPrefix
        : null;

    /// <summary>opus-mt-en-vi de çok hedeflidir (Vietnamca ve lehçeleri).</summary>
    public const string VietnameseTargetPrefix = ">>vie<<";

    private static readonly Lazy<HttpClient> SharedClient = new(() =>
        // Büyük dosyada toplam süre sınırı anlamsız; takılmayı StallTimeout yakalar.
        new HttpClient { Timeout = Timeout.InfiniteTimeSpan });

    private readonly HttpClient _http;
    private readonly SemaphoreSlim _downloadGate = new(1, 1);

    public ModelStore(string installDirectory, HttpClient? httpClient = null)
        : this(installDirectory, EnglishTurkish, httpClient) { }

    public ModelStore(string installDirectory, IReadOnlyList<ModelFile> files, HttpClient? httpClient = null)
    {
        InstallDirectory = installDirectory;
        Files = files;
        _http = httpClient ?? SharedClient.Value;
    }

    public string InstallDirectory { get; }
    public IReadOnlyList<ModelFile> Files { get; }
    public long TotalBytes => Files.Sum(f => f.Size);

    /// <summary>Tüm dosyalar asıl adlarıyla ve doğru boyutta duruyorsa kurulu.</summary>
    public bool IsInstalled => Files.All(IsFileInstalled);

    public string PathOf(string fileName) => Path.Combine(InstallDirectory, fileName);

    private bool IsFileInstalled(ModelFile file)
    {
        var info = new FileInfo(PathOf(file.Name));
        return info.Exists && info.Length == file.Size;
    }

    /// <summary>Eksik dosyaları indirir; ilerleme 0–1 arası toplam bayt oranıdır.</summary>
    /// <exception cref="InvalidDataException">İnen dosyanın boyutu ya da özeti tutmadı.</exception>
    public async Task DownloadAsync(IProgress<double>? progress, CancellationToken ct)
    {
        await _downloadGate.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            Directory.CreateDirectory(InstallDirectory);
            var reporter = new ProgressReporter(progress, TotalBytes);
            foreach (var file in Files)
            {
                if (IsFileInstalled(file))
                {
                    reporter.Add(file.Size);
                    continue;
                }
                await DownloadFileAsync(file, reporter, ct).ConfigureAwait(false);
            }
            reporter.Complete();
        }
        finally
        {
            _downloadGate.Release();
        }
    }

    private async Task DownloadFileAsync(ModelFile file, ProgressReporter reporter, CancellationToken ct)
    {
        var finalPath = PathOf(file.Name);
        var partPath = finalPath + PartSuffix;
        // Dosya adı alt klasör içerebilir ("voices/male_1.wav").
        Directory.CreateDirectory(Path.GetDirectoryName(finalPath)!);
        var existing = File.Exists(partPath) ? new FileInfo(partPath).Length : 0;
        if (existing > file.Size)
        {
            File.Delete(partPath);
            existing = 0;
        }

        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        if (existing > 0 && existing < file.Size)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, file.Url);
            request.Headers.Range = new RangeHeaderValue(existing, null);
            using var response = await SendAsync(request, ct).ConfigureAwait(false);
            if (response.StatusCode == HttpStatusCode.PartialContent)
            {
                // Önceki inişin baytları da özete girmeli.
                await HashExistingAsync(partPath, hash, ct).ConfigureAwait(false);
                reporter.Add(existing);
                await WriteBodyAsync(response, partPath, FileMode.Append, hash, reporter, ct).ConfigureAwait(false);
            }
            else
            {
                // Sunucu kaldığı yerden vermiyorsa baştan.
                response.EnsureSuccessStatusCode();
                await WriteBodyAsync(response, partPath, FileMode.Create, hash, reporter, ct).ConfigureAwait(false);
            }
        }
        else if (existing == file.Size)
        {
            await HashExistingAsync(partPath, hash, ct).ConfigureAwait(false);
            reporter.Add(existing);
        }
        else
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, file.Url);
            using var response = await SendAsync(request, ct).ConfigureAwait(false);
            response.EnsureSuccessStatusCode();
            await WriteBodyAsync(response, partPath, FileMode.Create, hash, reporter, ct).ConfigureAwait(false);
        }

        var length = new FileInfo(partPath).Length;
        var actual = Convert.ToHexStringLower(hash.GetHashAndReset());
        if (length != file.Size || !string.Equals(actual, file.Sha256, StringComparison.OrdinalIgnoreCase))
        {
            // Bozuk parçayı tutmak, sonraki denemede de aynı hatayı verirdi.
            File.Delete(partPath);
            throw new InvalidDataException(
                $"{file.Name}: expected {file.Size} bytes / {file.Sha256}, got {length} bytes / {actual}");
        }
        File.Move(partPath, finalPath, overwrite: true);
    }

    private Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) =>
        _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);

    private static async Task HashExistingAsync(string path, IncrementalHash hash, CancellationToken ct)
    {
        await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 16, true);
        var buffer = new byte[1 << 16];
        int read;
        while ((read = await stream.ReadAsync(buffer, ct).ConfigureAwait(false)) > 0)
            hash.AppendData(buffer, 0, read);
    }

    private static async Task WriteBodyAsync(HttpResponseMessage response, string partPath, FileMode mode,
        IncrementalHash hash, ProgressReporter reporter, CancellationToken ct)
    {
        await using var body = await response.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        await using var output = new FileStream(partPath, mode, FileAccess.Write, FileShare.None, 1 << 16, true);
        var buffer = new byte[1 << 16];
        using var stall = CancellationTokenSource.CreateLinkedTokenSource(ct);
        while (true)
        {
            stall.CancelAfter(StallTimeout);
            int read;
            try
            {
                read = await body.ReadAsync(buffer, stall.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!ct.IsCancellationRequested)
            {
                throw new TimeoutException("Model download stalled");
            }
            if (read == 0) break;
            hash.AppendData(buffer, 0, read);
            await output.WriteAsync(buffer.AsMemory(0, read), ct).ConfigureAwait(false);
            reporter.Add(read);
        }
    }

    /// <summary>Arayüzü boğmamak için ilerlemeyi yalnızca binde bir değiştiğinde bildirir.</summary>
    private sealed class ProgressReporter(IProgress<double>? progress, long total)
    {
        private long _done;
        private double _lastReported = -1;

        public void Add(long bytes)
        {
            _done += bytes;
            if (progress is null || total <= 0) return;
            var value = Math.Min(1.0, (double)_done / total);
            if (value - _lastReported < 0.001) return;
            _lastReported = value;
            progress.Report(value);
        }

        public void Complete()
        {
            if (_lastReported < 1.0) progress?.Report(1.0);
        }
    }
}
