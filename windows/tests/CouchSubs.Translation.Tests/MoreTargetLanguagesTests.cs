// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Translation;
using Xunit;

namespace CouchSubs.Translation.Tests;

/// <summary>Nino: yeni dillerin ücretsiz modelleri ve yapay zekâ istemi.</summary>
public class MoreTargetLanguagesTests
{
    [Fact]
    public void FreeModelsForHindiIndonesianVietnameseDutch()
    {
        foreach (var code in new[] { "tr", "ar", "hi", "id", "vi", "nl" })
        {
            var files = ModelStore.FreeModels[code];
            // Türkçe CTranslate2 modelidir (Ct2ModelStore); burada yalnız belirteçleyici dosyaları (source.spm, vocab.json)
            // durur. Öteki diller ONNX: kodlayıcı, kod çözücü, source.spm, vocab.json.
            Assert.Equal(code == "tr" ? 2 : 4, files.Count);
            Assert.All(files, file => Assert.Equal(64, file.Sha256.Length));
        }
        // Çok hedefli modellerin belirteci (vocab.json'da var); tek hedeflilerde belirteç yok.
        Assert.Equal(">>vie<<", ModelStore.TargetPrefixFor("vi"));
        Assert.Equal(">>ara<<", ModelStore.TargetPrefixFor("ar"));
        foreach (var code in new[] { "tr", "hi", "id", "nl" }) Assert.Null(ModelStore.TargetPrefixFor(code));
        Assert.Contains("opus-mt-en-hi", ModelStore.FilesFor("hi")[0].Url.ToString());
        Assert.False(ModelStore.FreeModels.ContainsKey("th"));
        Assert.False(ModelStore.FreeModels.ContainsKey("tl"));
    }

    [Fact]
    public void AiPromptNamesTheChosenLanguage()
    {
        Assert.Contains("natural Thai", AiRequest.SystemPromptFor("th"));
        Assert.DoesNotContain("Arabic", AiRequest.SystemPromptFor("vi"));
        Assert.Equal(AiRequest.ArabicSystemPrompt, AiRequest.SystemPromptFor("ar"));
        Assert.Equal(AiRequest.SystemPrompt, AiRequest.SystemPromptFor("tr"));
    }

    /// Gerçek model (Xenova opus-mt-en-vi / en-id) ~/Library/Caches/couchsubs-test-models altındaysa bir cümle çevrilir;
    /// yoksa denetlenmez. Vietnamca ">>vie<<" belirteciyle çevirir.
    [Theory]
    [InlineData("vi")]
    [InlineData("id")]
    public void RealModelTranslatesASentence(string code)
    {
        var directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Library", "Caches",
            "couchsubs-test-models", "en-" + code);
        if (!File.Exists(Path.Combine(directory, ModelStore.EncoderFile))) return;
        using var engine = new OnnxMarianEngine(directory, 64, OnnxMarianEngine.DefaultBeams, ModelStore.TargetPrefixFor(code));
        var text = engine.Translate("Where is the camp?", CancellationToken.None);
        Console.WriteLine($"en-{code}: {text}");
        Assert.False(string.IsNullOrWhiteSpace(text));
        Assert.DoesNotContain("camp?", text);
    }
}
