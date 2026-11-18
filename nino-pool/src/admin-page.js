// SPDX-License-Identifier: AGPL-3.0-only
// Nino paneli (GET /panel). Sayfa veri içermez; anahtarla /v1/stats'tan çeker, 15 saniyede bir yeniler.
export const ADMIN_PAGE = `<!doctype html>
<html lang="tr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Nino Panel</title>
<style>
:root{--bg:#F3F6FB;--card:#fff;--ink:#0A1430;--soft:#5B6782;--line:#E3E9F3;--blue:#1E6FE8;--green:#1FA971;--red:#E5484D}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.4 -apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",Roboto,sans-serif}
main{max-width:1180px;margin:0 auto;padding:28px 20px 60px}
header{display:flex;align-items:center;gap:14px;margin-bottom:22px}
header h1{font-size:26px;letter-spacing:-.4px;margin:0}header .sub{color:var(--soft);font-size:13px}
header .right{margin-left:auto;display:flex;gap:10px;align-items:center;color:var(--soft);font-size:13px}
.logo{width:40px;height:40px;border-radius:11px;background:linear-gradient(135deg,#0A1430,#1E6FE8);display:grid;place-items:center;color:#fff;font-weight:800}
.hero{background:linear-gradient(135deg,#0A1430 0%,#13285A 60%,#1E6FE8 140%);color:#fff;border-radius:24px;padding:28px 30px;display:grid;grid-template-columns:1.2fr 1fr;gap:24px;box-shadow:0 18px 40px rgba(10,20,48,.18)}
.hero .label{opacity:.75;font-size:14px;display:flex;align-items:center;gap:8px}
.hero .big{font-size:84px;font-weight:800;letter-spacing:-3px;line-height:1;margin:10px 0 6px}
.dot{width:10px;height:10px;border-radius:50%;background:#35E39B;box-shadow:0 0 0 0 rgba(53,227,155,.7);animation:p 1.8s infinite}
@keyframes p{70%{box-shadow:0 0 0 12px rgba(53,227,155,0)}100%{box-shadow:0 0 0 0 rgba(53,227,155,0)}}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin-top:8px}.chip{background:rgba(255,255,255,.12);border-radius:999px;padding:5px 12px;font-size:13px}
.hero h3{margin:0 0 10px;font-size:14px;opacity:.75;font-weight:600}
.games div{display:flex;justify-content:space-between;padding:7px 0;border-bottom:1px solid rgba(255,255,255,.12);font-size:14px}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-top:16px}
.card{background:var(--card);border:1px solid var(--line);border-radius:20px;padding:18px 18px 16px;box-shadow:0 6px 18px rgba(10,20,48,.05)}
.card .k{color:var(--soft);font-size:13px;font-weight:600}.card .v{font-size:34px;font-weight:800;letter-spacing:-1px;margin-top:6px}
.card .s{color:var(--soft);font-size:12.5px;margin-top:4px}
.wide{grid-column:span 2}.rows div{display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid var(--line);font-size:14px}
.rows div:last-child{border:0}.bar{height:8px;border-radius:99px;background:var(--line);overflow:hidden;margin-top:10px}.bar i{display:block;height:100%;background:var(--blue)}
svg{width:100%;height:90px;margin-top:10px}
#gate{max-width:420px;margin:12vh auto;background:#fff;border:1px solid var(--line);border-radius:22px;padding:28px;text-align:center}
#gate input{width:100%;padding:12px 14px;border:1px solid var(--line);border-radius:12px;font-size:15px;margin:14px 0}
button{background:var(--ink);color:#fff;border:0;border-radius:999px;padding:11px 22px;font-weight:600;font-size:14px;cursor:pointer}
@media(max-width:900px){.grid{grid-template-columns:repeat(2,1fr)}.hero{grid-template-columns:1fr}.hero .big{font-size:64px}}
@media(max-width:520px){.grid{grid-template-columns:1fr}.wide{grid-column:span 1}}
</style></head><body>
<div id="gate" hidden><div class="logo" style="margin:0 auto">N</div><h2>Nino Panel</h2><p class="sub" style="color:#5B6782">Panel anahtarını gir (bu cihazda hatırlanır).</p>
<input id="key" type="password" placeholder="Anahtar" autocomplete="off"><button id="go">Aç</button></div>
<main id="app" hidden>
<header><div class="logo">N</div><div><h1>Nino Panel</h1><div class="sub">Canlı · 15 saniyede bir yenilenir</div></div>
<div class="right"><span id="when"></span><button id="out" style="background:#E3E9F3;color:#0A1430">Çıkış</button></div></header>
<section class="hero"><div><div class="label"><span class="dot"></span>Şu an oynayan</div><div class="big" id="now">–</div>
<div class="chips" id="nowPlat"></div></div><div class="games"><h3>Şu an oynanan oyunlar</h3><div id="games"></div></div></section>
<section class="grid">
<div class="card"><div class="k">Son 24 saatte açan</div><div class="v" id="a24">–</div><div class="s">Farklı kurulum</div></div>
<div class="card"><div class="k">Toplam kurulum</div><div class="v" id="inst">–</div><div class="s" id="instNew"></div></div>
<div class="card"><div class="k">İndirme (GitHub)</div><div class="v" id="dl">–</div><div class="s" id="dlBy"></div></div>
<div class="card"><div class="k">Çevrilen satır</div><div class="v" id="lines">–</div><div class="s" id="words"></div></div>
<div class="card wide"><div class="k">Son 24 saatte saatlik çeviri</div><svg id="spark" viewBox="0 0 480 90" preserveAspectRatio="none"></svg><div class="s" id="today"></div></div>
<div class="card"><div class="k">Bugünkü çeviri harcaması</div><div class="v" id="spend">–</div><div class="bar"><i id="spendBar" style="width:0"></i></div><div class="s" id="spendCap"></div></div>
<div class="card"><div class="k">Gözden geçirilen</div><div class="v" id="rev">–</div><div class="s">Bağlamla düzeltilip onaylanan</div></div>
<div class="card"><div class="k">Toplanan İngilizce satır</div><div class="v" id="pool">–</div><div class="s" id="poolSeen"></div></div>
<div class="card"><div class="k">Nino'ya Sor (bugün)</div><div class="v" id="ask">–</div><div class="s" id="askCost"></div></div>
<div class="card"><div class="k">Sorun bildirimi</div><div class="v" id="rep">–</div><div class="s" id="repNew"></div></div>
<div class="card"><div class="k">En yeni sürüm</div><div class="v" id="latest" style="font-size:26px">–</div><div class="s">GitHub</div></div>
<div class="card wide rows"><div class="k" style="border:0">Kurulumlar (platform)</div><div id="plat"></div></div>
<div class="card wide rows"><div class="k" style="border:0">Diller (çeviri)</div><div id="langs"></div></div>
</section></main>
<script>
const $=id=>document.getElementById(id);const fmt=n=>(n??0).toLocaleString('tr-TR');
const NAMES={mac:'Mac',windows:'Windows',android:'Android',ios:'iPhone / iPad',tv:'TV',linux:'Linux','':'Bilinmiyor (eski sürüm)'};
const LANGS={tr:'🇹🇷 Türkçe',ar:'🇸🇦 Arapça',hi:'🇮🇳 Hintçe',id:'🇮🇩 Endonezce',th:'🇹🇭 Tayca',vi:'🇻🇳 Vietnamca',ur:'🇵🇰 Urduca',bn:'🇧🇩 Bengalce',ms:'🇲🇾 Malayca',tl:'🇵🇭 Filipince',nl:'🇳🇱 Felemenkçe'};
let key='';try{key=localStorage.getItem('ninoPanelKey')||''}catch{}
function gate(show){$('gate').hidden=!show;$('app').hidden=show}
$('go').onclick=()=>{key=$('key').value.trim();try{localStorage.setItem('ninoPanelKey',key)}catch{};load()};
$('out').onclick=()=>{try{localStorage.removeItem('ninoPanelKey')}catch{};key='';gate(true)};
function rows(el,list,name,value){el.innerHTML=list.length?list.map(r=>'<div><span>'+name(r)+'</span><b>'+value(r)+'</b></div>').join(''):'<div><span style="color:#5B6782">Henüz yok</span></div>'}
async function load(){if(!key){gate(true);return}
 const r=await fetch('/v1/stats',{headers:{authorization:'Bearer '+key}}).catch(()=>null);
 if(!r||r.status===401){gate(true);return} if(!r.ok)return; const d=await r.json(); gate(false);
 const p=d.players;$('now').textContent=fmt(p.now);
 $('nowPlat').innerHTML=p.byPlatform.map(x=>'<span class="chip">'+(NAMES[x.platform]||x.platform)+' · '+x.n+'</span>').join('')||'<span class="chip">Şu an kimse oynamıyor</span>';
 $('games').innerHTML=p.games.length?p.games.map(g=>'<div><span>'+(g.game||'Oyun bilinmiyor')+'</span><b>'+g.n+'</b></div>').join(''):'<div><span>—</span></div>';
 $('a24').textContent=fmt(p.active24h);$('inst').textContent=fmt(p.installs);$('instNew').textContent='Bugün yeni: '+fmt(p.newToday);
 const dl=d.downloads;$('dl').textContent=dl?fmt(dl.total):'–';$('dlBy').textContent=dl?'Mac '+fmt(dl.mac)+' · Windows '+fmt(dl.windows)+' · Android '+fmt(dl.android)+' · TV '+fmt(dl.tv):'';
 $('latest').textContent=dl&&dl.latest||'–';
 const t=d.translations;$('lines').textContent=fmt(t.lines);$('words').textContent=fmt(t.words)+' kelime · bugün '+fmt(t.today)+' satır';
 $('rev').textContent=fmt(t.reviewed);$('today').textContent='Bugün '+fmt(t.today)+' satır, '+fmt(t.wordsToday)+' kelime çevrildi';
 const hours=[];const base=Math.floor(d.now/3600)*3600;const map=new Map(t.hourly.map(h=>[h.hour,h.n]));for(let i=23;i>=0;i--)hours.push(map.get(base-i*3600)||0);
 const max=Math.max(1,...hours);$('spark').innerHTML=hours.map((n,i)=>{const h=Math.max(2,n/max*80);return '<rect x="'+(i*20+3)+'" y="'+(88-h)+'" width="14" height="'+h+'" rx="4" fill="'+(i===23?'#1E6FE8':'#BFD3F6')+'"><title>'+n+'</title></rect>'}).join('');
 const s=d.spend;$('spend').textContent='$'+s.translateToday.toFixed(2);$('spendCap').textContent='Günlük sınır $'+s.translateCap;$('spendBar').style.width=Math.min(100,s.translateToday/s.translateCap*100)+'%';
 $('pool').textContent=fmt(d.pool.lines);$('poolSeen').textContent=fmt(d.pool.seen)+' kez görüldü';
 $('ask').textContent=fmt(d.assistant.questionsToday);$('askCost').textContent='Harcama $'+s.assistantToday.toFixed(2);
 $('rep').textContent=fmt(d.reports.total);$('repNew').textContent='Okunmamış: '+fmt(d.reports.fresh);
 rows($('plat'),p.installsByPlatform,r=>NAMES[r.platform]||r.platform,r=>fmt(r.n));
 rows($('langs'),t.byLang,r=>LANGS[r.lang]||r.lang,r=>fmt(r.n)+' satır');
 $('when').textContent=new Date(d.now*1000).toLocaleTimeString('tr-TR');
}
load();setInterval(load,15000);
</script></body></html>`;
