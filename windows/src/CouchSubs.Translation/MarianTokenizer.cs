// SPDX-License-Identifier: AGPL-3.0-only

using System.Text;
using System.Text.Json;
using Microsoft.ML.Tokenizers;

namespace CouchSubs.Translation;

/// <summary>
/// OPUS-MT (Marian) belirteçleyicisi. SentencePiece yalnızca metni parçalara ayırır; kimlikler
/// spm'den değil modelin ortak <c>vocab.json</c> sözlüğünden gelir (Hugging Face MarianTokenizer ile aynı).
/// </summary>
public sealed class MarianTokenizer
{
    // İngilizce→Türkçe (tc-big) modelinin kimlikleri. Başka modelde (ör. İngilizce→Arapça) kimlikler vocab.json'dan
    // okunur: bkz. Eos, Unk, Pad.
    public const int EosId = 43741;
    public const int UnkId = 52508;
    public const int PadId = 57059;

    /// <summary>Bu modelin &lt;/s&gt;, &lt;unk&gt; ve &lt;pad&gt; kimlikleri (sözlükte yoksa Türkçe modelinkiler).</summary>
    public int Eos { get; }
    public int Unk { get; }
    public int Pad { get; }
    /// <summary>
    /// Çok hedefli modellerde girdinin başına konan hedef dil belirteci (opus-mt-en-ar: "&gt;&gt;ara&lt;&lt;"); yoksa null.
    /// </summary>
    public int? TargetPrefixId { get; }

    /// <summary>SentencePiece'in sözcük başı işareti; çözerken boşluğa döner.</summary>
    private const char WordStart = '▁';

    private readonly SentencePieceTokenizer _pieces;
    private readonly Dictionary<string, int> _vocab;
    private readonly string[] _idToPiece;

    private MarianTokenizer(SentencePieceTokenizer pieces, Dictionary<string, int> vocab, string? targetPrefix)
    {
        _pieces = pieces;
        _vocab = vocab;
        Eos = vocab.TryGetValue("</s>", out var eos) ? eos : EosId;
        Unk = vocab.TryGetValue("<unk>", out var unk) ? unk : UnkId;
        Pad = vocab.TryGetValue("<pad>", out var pad) ? pad : PadId;
        if (targetPrefix is not null)
            TargetPrefixId = vocab.TryGetValue(targetPrefix, out var prefix) ? prefix
                : throw new InvalidDataException($"vocab.json has no target token {targetPrefix}");
        _idToPiece = new string[vocab.Values.Max() + 1];
        foreach (var (piece, id) in vocab) _idToPiece[id] = piece;
    }

    public int VocabularySize => _idToPiece.Length;

    /// <param name="targetPrefix">Çok hedefli modelde hedef dil belirteci (ör. "&gt;&gt;ara&lt;&lt;"); tek hedefli modelde null.</param>
    public static MarianTokenizer Load(string sourceSpmPath, string vocabJsonPath, string? targetPrefix = null)
    {
        using var spm = File.OpenRead(sourceSpmPath);
        // BOS/EOS'u spm eklemesin: Marian yalnızca sona kendi </s> kimliğini koyar.
        var pieces = SentencePieceTokenizer.Create(spm, addBeginningOfSentence: false, addEndOfSentence: false);
        return new MarianTokenizer(pieces, ReadVocab(vocabJsonPath), targetPrefix);
    }

    /// <summary>Yansımasız okuma: uygulama kırpılarak (trim) yayımlansa da çalışsın.</summary>
    private static Dictionary<string, int> ReadVocab(string path)
    {
        using var doc = JsonDocument.Parse(File.ReadAllBytes(path));
        var vocab = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var entry in doc.RootElement.EnumerateObject()) vocab[entry.Name] = entry.Value.GetInt32();
        if (vocab.Count == 0) throw new InvalidDataException("vocab.json is empty");
        return vocab;
    }

    /// <summary>Kodlayıcı girdisi: parçaların kimlikleri + sonda &lt;/s&gt;.</summary>
    public int[] Encode(string text)
    {
        var tokens = _pieces.EncodeToTokens(text, out _, addBeginningOfSentence: false, addEndOfSentence: false,
            considerPreTokenization: true, considerNormalization: true);
        var ids = new List<int>(tokens.Count + 2);
        if (TargetPrefixId is { } prefix) ids.Add(prefix);
        var unknown = _pieces.UnknownId;
        for (var i = 0; i < tokens.Count; i++)
        {
            var piece = tokens[i].Value;
            if (tokens[i].Id == unknown)
            {
                // Özgün SentencePiece ardışık bilinmeyen karakterleri tek parça yapar ("Óð"); bu kitaplık ayrı
                // verir. Birleşik parça yine vocab.json'da aranır: "ğ" spm'de bilinmez ama ortak sözlükte vardır.
                var run = new StringBuilder(piece);
                while (i + 1 < tokens.Count && tokens[i + 1].Id == unknown) run.Append(tokens[++i].Value);
                piece = run.ToString();
            }
            ids.Add(_vocab.TryGetValue(piece, out var id) ? id : Unk);
        }
        ids.Add(Eos);
        return ids.ToArray();
    }

    /// <summary>Kod çözücü çıktısını metne çevirir; özel belirteçler atlanır.</summary>
    public string Decode(IEnumerable<int> ids)
    {
        var sb = new StringBuilder();
        foreach (var id in ids)
        {
            if (id == Eos || id == Unk || id == Pad || id < 0 || id >= _idToPiece.Length) continue;
            var piece = _idToPiece[id];
            if (piece is not null) sb.Append(piece);
        }
        sb.Replace(WordStart, ' ');
        return sb.ToString().Trim();
    }
}
