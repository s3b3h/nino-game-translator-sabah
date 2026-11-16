// SPDX-License-Identifier: AGPL-3.0-only

using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using CouchSubs.Core;
using CouchSubs.Translation;
using Xunit;

namespace CouchSubs.Translation.Tests;

/// <summary>Nino: Arapça hedef. Motorlar Arapça istemle gider; Türkçe sözlük, düzeltmeler ve resmiyet ayarı kullanılmaz.</summary>
public class ArabicTargetTests
{
    private sealed class Recorder(Func<string, string> reply) : HttpMessageHandler
    {
        public List<string> Bodies { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var body = request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken);
            Bodies.Add(body);
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(reply(body), Encoding.UTF8, "application/json") };
        }
    }

    [Fact]
    public async Task AiRequestUsesTheArabicPrompt()
    {
        var request = AiRequest.Build(AiProvider.Gemini, "k", AiProvider.Gemini.Model(null), ["Stay close."],
            [new AiContextLine("Arthur?", "آرثر؟")], target: "ar");
        var body = await request.Content!.ReadAsStringAsync();
        Assert.Contains("Modern Standard Arabic", body);
        Assert.Contains("into Arabic", body);
        Assert.Contains("Arabic: آرثر؟", JsonNode.Parse(body)!.ToJsonString(new JsonSerializerOptions
            { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }));
        Assert.DoesNotContain("Turkish", body);
        Assert.Equal(AiRequest.SystemPrompt, AiRequest.SystemPromptFor("tr"));
    }

    [Fact]
    public void TranslationModelsGetTheArabicPrompt()
    {
        Assert.Contains("English (en) to Arabic (ar)", TranslateGemma.Prompt("Hi", "ar"));
        Assert.Equal("Translate this from English to Arabic:\nEnglish: Hi\nArabic:", MiLMMT.Prompt("Hi", "ar"));
        Assert.Equal("Translate this from English to Turkish:\nEnglish: Hi\nTurkish:", MiLMMT.Prompt("Hi"));
    }

    [Fact]
    public async Task DeepLTranslatesIntoArabicWithoutTheTurkishGlossary()
    {
        var deepL = new Recorder(body =>
        {
            var texts = JsonDocument.Parse(body).RootElement.GetProperty("text").EnumerateArray().Select(t => "[ar] " + t.GetString());
            return JsonSerializer.Serialize(new { translations = texts.Select(t => new { text = t }) });
        });
        var translator = new DeepLTranslator("abc:fx", null, new HttpClient(deepL), glossary: new GlossaryStore(null), target: "ar");

        await translator.TranslateAsync("Soul began to fight.");

        var json = JsonDocument.Parse(deepL.Bodies[0]).RootElement;
        Assert.Equal("AR", json.GetProperty("target_lang").GetString());
        Assert.False(json.TryGetProperty("formality", out _));
        Assert.False(json.TryGetProperty("tag_handling", out _));
        Assert.Equal("Soul began to fight.", json.GetProperty("text")[0].GetString());
    }

    [Fact]
    public void ArabicModelFiles()
    {
        Assert.Same(ModelStore.EnglishArabic, ModelStore.FilesFor("ar"));
        Assert.Same(ModelStore.EnglishTurkish, ModelStore.FilesFor("tr"));
        Assert.Equal(">>ara<<", ModelStore.TargetPrefixFor("ar"));
        Assert.Null(ModelStore.TargetPrefixFor("tr"));
        Assert.All(ModelStore.EnglishArabic, file => Assert.Contains("Xenova/opus-mt-en-ar", file.Url.AbsoluteUri));
    }

    private sealed class Engine : ISentenceEngine
    {
        public List<string> Calls { get; } = [];
        public string Translate(string sentence, CancellationToken cancellationToken)
        {
            Calls.Add(sentence);
            return "ترجمة";
        }
        public void Dispose() { }
    }

    /// Arapçada sözlük yer tutucusu ve Türkçe düzeltmeler yok: cümle olduğu gibi (büyük harf düzeniyle) modele gider.
    [Fact]
    public async Task FreeArabicTranslationSkipsTurkishProcessing()
    {
        var engine = new Engine();
        var translator = new MarianTranslator(() => engine, () => true, glossary: new GlossaryStore(null), turkish: false);
        Assert.Equal("KRATOS: ترجمة", await translator.TranslateAsync("KRATOS: THROW THE LEVIATHAN AXE, BOY!"));
        var call = Assert.Single(engine.Calls);
        Assert.Equal("throw the leviathan axe, boy!", call.ToLowerInvariant());
    }

    /// Gerçek opus-mt-en-ar belirteçleyicisi (source.spm, vocab.json): girdinin başında "&gt;&gt;ara&lt;&lt;", sonunda &lt;/s&gt;.
    [Fact]
    public void ArabicTokenizerAddsTheTargetToken()
    {
        var directory = Environment.GetEnvironmentVariable("COUCHSUBS_TEST_MODELS_AR") is { Length: > 0 } fromEnv ? fromEnv
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Library", "Caches", "couchsubs-test-models", "en-ar");
        var spm = Path.Combine(directory, ModelStore.SourceSpmFile);
        var vocab = Path.Combine(directory, ModelStore.VocabFile);
        if (!File.Exists(spm) || !File.Exists(vocab)) return; // dosyalar yoksa denetlenmez (xunit 2'de çalışırken atlama yok)
        var tokenizer = MarianTokenizer.Load(spm, vocab, ModelStore.ArabicTargetPrefix);
        Assert.Equal(0, tokenizer.Eos);
        Assert.Equal(1, tokenizer.Unk);
        Assert.Equal(62801, tokenizer.Pad);
        var ids = tokenizer.Encode("Where is the camp?");
        Assert.Equal(4, ids[0]);
        Assert.Equal(0, ids[^1]);
        Assert.True(ids.Length > 3);
    }
}
