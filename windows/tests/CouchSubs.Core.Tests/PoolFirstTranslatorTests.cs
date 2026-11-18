// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

/// <summary>Havuz öncelikli oyunlarda kullanıcının motoru hiç çağrılmaz (Mac: PoolFirstTranslatorTests).</summary>
public sealed class PoolFirstTranslatorTests
{
    private sealed class Counting(string answer, bool prefetches = false) : ITextTranslator
    {
        public readonly List<string> Translated = [];
        public readonly List<string> Prefetched = [];
        public Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default)
        {
            lock (Translated) Translated.Add(text);
            return Task.FromResult(answer);
        }
        public bool Prefetches => prefetches;
        public void Prefetch(string text) => Prefetched.Add(text);
        public bool TranslatesTogether => true;
    }

    [Fact]
    public async Task PoolFirstGameUsesPoolAndNeverTheEngine()
    {
        var engine = new Counting("gemini", prefetches: true);
        var free = new Counting("ücretsiz");
        var asked = new List<string>();
        var translator = new PoolFirstTranslator(engine, free, () => true, (line, _) => { asked.Add(line); return Task.FromResult<string?>("havuz"); });
        Assert.Equal("havuz", await translator.TranslateAsync("Get in the car!"));
        translator.Prefetch("Get in");
        Assert.False(translator.TranslatesTogether);
        Assert.Equal(["havuz", "havuz"], await translator.TranslateAllAsync(["a line", "another line"]));
        Assert.Empty(engine.Translated);
        Assert.Empty(engine.Prefetched);
        Assert.Empty(free.Translated);
        Assert.Equal(3, asked.Count);
        Assert.Equal("havuz", translator.LastSource);
    }

    [Fact]
    public async Task PoolSilenceFallsBackToFreeTranslationOnly()
    {
        var engine = new Counting("gemini");
        var free = new Counting("ücretsiz");
        var translator = new PoolFirstTranslator(engine, free, () => true, (_, _) => Task.FromResult<string?>(null));
        Assert.Equal("ücretsiz", await translator.TranslateAsync("Get in the car!"));
        var failing = new PoolFirstTranslator(engine, free, () => true, (_, _) => throw new HttpRequestException("kapalı"));
        Assert.Equal("ücretsiz", await failing.TranslateAsync("Get in the car!"));
        Assert.Empty(engine.Translated);
        Assert.Equal(2, free.Translated.Count);
        Assert.Equal("ücretsiz", failing.LastSource);
    }

    [Fact]
    public async Task OtherGamesUseTheEngineAsBefore()
    {
        var engine = new Counting("gemini", prefetches: true);
        var free = new Counting("ücretsiz");
        var asked = 0;
        var translator = new PoolFirstTranslator(engine, free, () => false, (_, _) => { asked++; return Task.FromResult<string?>("havuz"); });
        Assert.Equal("gemini", await translator.TranslateAsync("Hello there."));
        translator.Prefetch("Hello");
        Assert.True(translator.Prefetches);
        Assert.True(translator.TranslatesTogether);
        Assert.Equal(0, asked);
        Assert.Single(engine.Prefetched);
        Assert.Empty(free.Translated);
    }

    [Fact]
    public async Task GameChangeIsFollowedLineByLine()
    {
        var engine = new Counting("gemini");
        var free = new Counting("ücretsiz");
        var poolFirst = false;
        var translator = new PoolFirstTranslator(engine, free, () => poolFirst, (_, _) => Task.FromResult<string?>("havuz"));
        Assert.Equal("gemini", await translator.TranslateAsync("one"));
        poolFirst = true;
        Assert.Equal("havuz", await translator.TranslateAsync("two"));
        Assert.Single(engine.Translated);
    }
}
