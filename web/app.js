// Ponk – webová aplikace bez build kroku. Data bere z lokálního serveru (/api).

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const view = $("#view");

const ICON = {
  home: '<path d="M3 11 12 4l9 7"/><path d="M5 10v10h5v-6h4v6h5V10"/>',
  grid: '<rect x="4" y="4" width="7" height="7"/><rect x="13" y="4" width="7" height="7"/><rect x="4" y="13" width="7" height="7"/><rect x="13" y="13" width="7" height="7"/>',
  tag: '<path d="M11 3h8a2 2 0 0 1 2 2v8l-9.5 9.5a2 2 0 0 1-2.8 0l-6.2-6.2a2 2 0 0 1 0-2.8Z"/><circle cx="16.5" cy="7.5" r="1.5"/>',
  eye: '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  filter: '<path d="M4 6h16M7 12h10M10 18h4"/>',
  sort: '<path d="M8 4v16m0 0-4-4m4 4 4-4M16 20V4m0 0-4 4m4-4 4 4"/>',
  list: '<path d="M9 6h11M9 12h11M9 18h11M4 6h.01M4 12h.01M4 18h.01"/>',
  tiles: '<rect x="4" y="4" width="7" height="7"/><rect x="13" y="4" width="7" height="7"/><rect x="4" y="13" width="7" height="7"/><rect x="13" y="13" width="7" height="7"/>',
  ext: '<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>',
  refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7"/>',
  back: '<path d="M15 5 8 12l7 7"/>',
  search: '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m15.5 15.5 5 5"/>',
};
const icon = (n) => `<svg viewBox="0 0 24 24" aria-hidden="true">${ICON[n]}</svg>`;

const TABS = [
  { href: "#/", label: "Domů", icon: "home", match: (r) => r.name === "home" },
  { href: "#/kategorie", label: "Kategorie", icon: "grid", match: (r) => r.name === "kategorie" },
  // Katalog: všechny položky najednou, hledání + filtry na jednom místě
  { href: "#/hledat", label: "Katalog", icon: "search", match: (r) => r.name === "hledat" },
  { href: "#/hlidane", label: "Hlídané", icon: "eye", match: (r) => r.name === "hlidane" },
  { href: "#/vice", label: "Více", icon: "menu", match: (r) => r.name === "vice" },
];

const SORTS = [
  ["relevance", "Doporučené"], ["price_asc", "Od nejlevnějšího"], ["price_desc", "Od nejdražšího"],
  ["discount", "Největší skutečná sleva"], ["drop", "Naposledy zlevněné"], ["unit", "Nejnižší cena za jednotku"],
  ["rating", "Nejlépe hodnocené"], ["newest", "Nejnovější v nabídce"],
];

const FONTS = [
  ["barlow", "Barlow Semi Condensed"], ["sofia", "Sofia Sans Semi Condensed"],
  ["encode", "Encode Sans Semi Condensed"], ["fira", "Fira Sans Condensed"], ["saira", "Saira Semi Condensed"],
];

const state = { meta: null, route: null, cache: new Map(), syncTimer: null };

// --- pomocníci ----------------------------------------------------------
const nf0 = new Intl.NumberFormat("cs-CZ", { maximumFractionDigits: 0 });
const nf2 = new Intl.NumberFormat("cs-CZ", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const money = (n) => (n == null ? "–" : nf0.format(Math.round(n)));
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const day = (iso) => { if (!iso) return ""; const d = new Date(iso.length <= 10 ? iso + "T00:00:00" : iso); return d.toLocaleDateString("cs-CZ", { day: "numeric", month: "numeric" }); };
const dayTime = (iso) => { if (!iso) return "zatím nikdy"; const d = new Date(iso); return d.toLocaleString("cs-CZ", { day: "numeric", month: "numeric", hour: "2-digit", minute: "2-digit" }); };
const img = (p, w = 300, h = 372) => (p ? `https://www.bauhaus.cz/img/${w}/${h}/resize/catalog/product${p}` : "");
const plural = (n, one, few, many) => (n === 1 ? one : n >= 2 && n <= 4 ? few : many);
const storeName = (code) => state.meta?.stores.find((s) => s.code === code)?.name || code;

async function api(path, opts = {}) {
  const init = { ...opts };
  if (opts.json) { init.method = init.method || "POST"; init.headers = { "Content-Type": "application/json" }; init.body = JSON.stringify(opts.json); }
  const r = await fetch("/api/" + path, init);
  const data = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(data.error || `Server vrátil chybu ${r.status}`);
  return data;
}

function toast(msg) {
  const t = $("#toast");
  t.textContent = msg; t.hidden = false;
  clearTimeout(toast.t); toast.t = setTimeout(() => (t.hidden = true), 2600);
}

function sanitize(html) {
  const doc = new DOMParser().parseFromString(html || "", "text/html");
  const keep = new Set(["P", "UL", "OL", "LI", "BR", "STRONG", "B", "EM", "I", "H3", "H4", "TABLE", "TBODY", "TR", "TD", "TH"]);
  const walk = (node) => {
    [...node.children].forEach((el) => {
      if (["SCRIPT", "STYLE", "IFRAME", "OBJECT", "IMG"].includes(el.tagName)) return el.remove();
      walk(el);
      if (!keep.has(el.tagName)) el.replaceWith(...el.childNodes);
      else [...el.attributes].forEach((a) => el.removeAttribute(a.name));
    });
  };
  walk(doc.body);
  return doc.body.innerHTML;
}

// --- router ---------------------------------------------------------------
function parseRoute() {
  const h = location.hash.slice(1) || "/";
  const [path, qs = ""] = h.split("?");
  const parts = path.split("/").filter(Boolean);
  return { name: parts[0] || "home", arg: parts[1] ? decodeURIComponent(parts[1]) : null, params: new URLSearchParams(qs), hash: location.hash || "#/" };
}

function renderNav() {
  const r = state.route;
  const drops = state.meta?.watched_drops || 0;
  const html = TABS.map((t) => `<a href="${t.href}"${t.match(r) ? ' aria-current="page"' : ""}>${icon(t.icon)}<span>${t.label}</span>${t.icon === "eye" && drops ? `<b class="badge-dot">${drops}</b>` : ""}</a>`).join("");
  $(".tabbar").innerHTML = html;
  $(".desk-nav").innerHTML = html;
}

async function render() {
  const prev = state.route;
  if (prev) state.cache.set(prev.hash, { ...(state.cache.get(prev.hash) || {}), scroll: window.scrollY });
  state.route = parseRoute();
  closeSheet();
  view.onclick = null;
  $("#suggest").hidden = true;
  renderNav();
  const r = state.route;
  $("#q").value = r.name === "hledat" ? r.params.get("q") || "" : "";
  $("#q-clear").hidden = !$("#q").value;
  try {
    if (r.name === "home") await Home();
    else if (r.name === "kategorie") await Categories();
    else if (r.name === "hledat") await Results();
    else if (r.name === "p") await Product(r.arg);
    else if (r.name === "hlidane") await Watch();
    else if (r.name === "vice") await More();
    else view.innerHTML = `<div class="empty"><h2>Tahle stránka neexistuje</h2><p><a href="#/">Zpět domů</a></p></div>`;
  } catch (e) {
    view.innerHTML = `<div class="empty"><h2>Data se nepodařilo načíst</h2><p>${esc(e.message)}</p><p>Zkontroluj, že na počítači běží <b>python run.py</b>.</p><p><button class="btn" onclick="location.reload()">Načíst znovu</button></p></div>`;
  }
  const saved = state.cache.get(r.hash)?.scroll;
  window.scrollTo(0, saved || 0);
}

// --- dlaždice a cenovky --------------------------------------------------
function ptag(it, big = false) {
  const sale = it.real_discount > 0;
  return `<span class="ptag${sale ? " sale" : ""}${big ? " big" : ""}"><span class="amt">${money(it.price)}<small>Kč</small></span>${sale ? `<span class="cut">−${it.real_discount} %</span>` : ""}</span>`;
}

function priceMeta(it) {
  const bits = [];
  if (it.min30_price && it.real_discount) bits.push(`nejníže za 30 dní ${money(it.min30_price)} Kč`);
  else if (it.was_price) bits.push(`<s>${money(it.was_price)} Kč</s>`);
  if (it.price_changed_at && it.prev_price) {
    const diff = it.price - it.prev_price;
    bits.push(`<span class="${diff < 0 ? "down" : "up"}">${diff < 0 ? "↓" : "↑"} ${money(Math.abs(diff))} Kč ${day(it.price_changed_at)}</span>`);
  }
  if (it.unit_price) bits.push(`${nf2.format(it.unit_price)} Kč/${esc(it.unit)}`);
  return bits.length ? `<div class="pmeta">${bits.join("<br>")}</div>` : "";
}

function avail(it) {
  const store = state.meta?.settings.store;
  if (store && it.store_qty > 0) return `<div class="avail yes">${esc(storeName(store))}: ${money(it.store_qty)} ks</div>`;
  if (it.online_in_stock) return `<div class="avail">Skladem online</div>`;
  return `<div class="avail">Nedostupné</div>`;
}

// Hodnocení zákazníků: 0–5 hvězdiček (rating 0–100), bez recenzí prázdné šedé.
function stars(rating, count, text = true) {
  const v = (rating || 0) / 20;
  const s = [0, 1, 2, 3, 4].map((i) => { const d = v - i; return d >= 0.75 ? "full" : d >= 0.25 ? "half" : ""; });
  const label = rating ? `Hodnocení ${v.toFixed(1).replace(".", ",")} z 5${count ? `, ${count} recenzí` : ""}` : "Bez hodnocení";
  return `<span class="stars ${rating ? "" : "none"}" role="img" aria-label="${label}">${s.map((c) => `<i class="${c}"></i>`).join("")}${text
    ? (rating ? `<b>${v.toFixed(1).replace(".", ",")}</b>${count ? `<span>(${count})</span>` : ""}` : "<span>(0)</span>") : ""}</span>`;
}

function tile(it) {
  const flags = [];
  if (it.labels?.includes("sell_off")) flags.push('<span class="flag red">Výprodej</span>');
  if (it.price_changed_at && it.price_changed_at === state.meta?.last_change && it.drop_pct > 0) flags.push('<span class="flag green">Zlevněno</span>');
  if (it.labels?.includes("only_online")) flags.push('<span class="flag">Jen online</span>');
  const name = it.brand && it.name.startsWith(it.brand) ? `<b>${esc(it.brand)}</b>${esc(it.name.slice(it.brand.length))}` : esc(it.name);
  return `<a class="tile" href="#/p/${encodeURIComponent(it.sku)}">
    <div class="pic">${it.image ? `<img src="${img(it.image)}" alt="" loading="lazy" onerror="this.replaceWith(Object.assign(document.createElement('span'),{className:'noimg',textContent:'Obrázek není k dispozici'}))">` : '<span class="noimg">Bez obrázku</span>'}
      ${flags.length ? `<div class="flags">${flags.join("")}</div>` : ""}</div>
    <div class="body"><p class="name">${name}</p>${stars(it.rating, it.rating_count)}
    <div class="bottom">${ptag(it)}${priceMeta(it)}${avail(it)}</div></div></a>`;
}

const shelf = (items, cls = "") => `<div class="shelf ${cls}">${items.map(tile).join("")}</div>`;
const qs = (obj) => new URLSearchParams(Object.entries(obj).filter(([, v]) => v != null && v !== "")).toString();

// --- Domů ------------------------------------------------------------------
async function Home() {
  state.meta = await api("meta");
  renderNav();
  const m = state.meta;
  if (!m.products) {
    view.innerHTML = `<div class="page-title"><h1>Stahuji katalog Bauhausu</h1><p>Poprvé to trvá zhruba 30–40 minut. Aplikace se mezitím plní a můžeš ji normálně používat.</p></div>${syncPanel()}`;
    watchSync();
    return;
  }
  const home = await api("home");
  const store = m.settings.store;
  const quick = [
    ["Výprodej", { label: "sell_off", sort: "discount" }],
    ["Výprodej skladem", { label: "sell_off", store, sort: "discount" }],
    ["Zlevněno za 7 dní", { drop_days: 7, sort: "drop" }],
    ["Sleva 50 % a víc", { disc: 50, sort: "discount" }],
    ["Doprava zdarma", { label: "free_shipping" }],
    ["Cena za jednotku", { unit: 1, sort: "unit" }],
  ];
  view.innerHTML = `
    <div class="chips" aria-label="Rychlé filtry">${quick.map(([t, q]) => `<a class="chip" href="#/hledat?${qs(q)}">${t}</a>`).join("")}</div>
    ${home.sections.map((s) => `<section class="section"><div class="section-head"><h2>${esc(s.title)}</h2>
      <a href="#/hledat?${qs(s.query)}">Zobrazit vše</a></div>${shelf(s.items, "rail")}</section>`).join("")}
    ${home.sections.length ? "" : `<div class="empty"><h2>Zatím žádné změny cen</h2><p>Po druhé denní kontrole se tu objeví zlevněné zboží.</p></div>`}
    <p class="muted" style="padding:18px 14px">V katalogu je ${money(m.products)} produktů. Poslední kontrola cen ${dayTime(m.last_run?.finished)}.</p>`;
  if (m.sync.running) toast("Právě probíhá kontrola cen");
}

// --- Kategorie -------------------------------------------------------------
async function Categories() {
  const p = state.route.params;
  const c1 = p.get("cat1"), c2 = p.get("cat2");
  const data = await api("categories?" + qs({ cat1: c1, cat2: c2 }));
  const crumbs = [`<a href="#/kategorie">Všechny kategorie</a>`];
  if (c1) crumbs.push(`<a href="#/kategorie?${qs({ cat1: c1 })}">${esc(c1)}</a>`);
  const title = c2 || c1 || "Kategorie";
  const target = (v) => data.level === "cat3"
    ? `#/hledat?${qs({ cat1: c1, cat2: c2, cat3: v })}`
    : data.level === "cat2" ? `#/kategorie?${qs({ cat1: c1, cat2: v })}` : `#/kategorie?${qs({ cat1: v })}`;
  view.innerHTML = `
    <div class="page-title">${c1 ? `<div class="crumbs">${crumbs.join("<span>/</span>")}</div>` : ""}<h1>${esc(title)}</h1>
      ${c1 ? `<p><a class="link" href="#/hledat?${qs({ cat1: c1, cat2: c2 })}">Zobrazit všechny produkty</a></p>` : ""}</div>
    <div class="catgrid" style="margin-top:12px">${data.values.map((c) => `<a class="cat" href="${target(c.value)}">
      ${c.image ? `<img src="${img(c.image, 240, 298)}" alt="" loading="lazy">` : ""}<b>${esc(c.value)}</b><span>${money(c.count)} ${plural(c.count, "produkt", "produkty", "produktů")}</span></a>`).join("")}</div>`;
}

// --- Výsledky + filtry -----------------------------------------------------
const results = { params: null, data: null, items: [], view: localStorage.getItem("ponk.view") || "grid" };

function resultsTitle(p) {
  if (p.get("q")) return `„${p.get("q")}“`;
  if (p.get("cat3") || p.get("cat2") || p.get("cat1")) return p.get("cat3") || p.get("cat2") || p.get("cat1");
  if (p.get("label") === "sell_off") return "Výprodej";
  if (p.get("drop_days")) return "Zlevněné zboží";
  return p.get("q") ? "Nabídka" : "Katalog";
}

async function Results() {
  const cached = state.cache.get(state.route.hash);
  results.params = new URLSearchParams(state.route.params);
  if (cached?.data && Date.now() - cached.ts < 300000) { results.data = cached.data; results.items = cached.items; }
  else await loadResults();
  drawResults();
}

async function loadResults(append = false) {
  const p = new URLSearchParams(results.params);
  if (append) p.set("page", (results.data.page || 1) + 1);
  const data = await api("search?" + p.toString());
  if (append) { results.items = results.items.concat(data.items); results.data = { ...data, facets: results.data.facets }; }
  else { results.data = data; results.items = data.items; }
  state.cache.set("#/hledat?" + results.params.toString(), { data: results.data, items: results.items, ts: Date.now() });
}

async function applyParams(p) {
  p.delete("page");
  results.params = p;
  history.replaceState(null, "", "#/hledat?" + p.toString());
  state.route = parseRoute();
  renderNav();
  await loadResults();
  drawResults();
  if (!$("#sheet").hidden && $("#sheet").dataset.kind === "filters") fillFilterSheet();
}

function activeChips(p) {
  const chips = [];
  const drop = (keys, val) => { const n = new URLSearchParams(p); keys.forEach((k) => { if (val == null) n.delete(k); else n.set(k, n.get(k).split("|").filter((x) => x !== val).join("|")); if (n.get(k) === "") n.delete(k); }); return n.toString(); };
  if (p.get("cat3")) chips.push([p.get("cat3"), drop(["cat3"])]);
  else if (p.get("cat2")) chips.push([p.get("cat2"), drop(["cat2", "cat3"])]);
  else if (p.get("cat1")) chips.push([p.get("cat1"), drop(["cat1", "cat2", "cat3"])]);
  (p.get("brand") || "").split("|").filter(Boolean).forEach((b) => chips.push([b, drop(["brand"], b)]));
  if (p.get("pmin") || p.get("pmax")) chips.push([`${p.get("pmin") || 0}–${p.get("pmax") || "∞"} Kč`, drop(["pmin", "pmax"])]);
  if (p.get("disc")) chips.push([`Sleva ${p.get("disc")} %+`, drop(["disc"])]);
  (p.get("label") || "").split("|").filter(Boolean).forEach((l) => chips.push([state.meta.labels[l] || l, drop(["label"], l)]));
  if (p.get("store")) chips.push([`Skladem: ${storeName(p.get("store"))}`, drop(["store"])]);
  if (p.get("online")) chips.push(["Skladem online", drop(["online"])]);
  if (p.get("drop_days")) chips.push([`Zlevněno za ${p.get("drop_days")} ${plural(+p.get("drop_days"), "den", "dny", "dní")}`, drop(["drop_days"])]);
  if (p.get("rating")) chips.push([`Hodnocení ${p.get("rating")}+`, drop(["rating"])]);
  if (p.get("unit")) chips.push(["S cenou za jednotku", drop(["unit"])]);
  for (const [k, v] of p) if (k.startsWith("a_")) v.split("|").forEach((x) => chips.push([x, drop([k], x)]));
  return chips;
}

function drawResults() {
  const p = results.params, d = results.data;
  const chips = activeChips(p);
  const nFilters = chips.length - (p.get("cat1") ? 1 : 0);
  const sortName = (SORTS.find(([k]) => k === (p.get("sort") || "relevance")) || SORTS[0])[1];
  view.innerHTML = `<div class="results">
    <div class="page-title" style="grid-column:1/-1"><h1>${esc(resultsTitle(p))}</h1><p>${money(d.total)} ${plural(d.total, "produkt", "produkty", "produktů")}</p></div>
    <aside class="filters-aside" aria-label="Filtry">${filterPanel(d.facets, p)}</aside>
    <div>
      <div class="toolbar">
        <button class="btn open-filters" data-act="filters">${icon("filter")}Filtry${nFilters ? ` (${nFilters})` : ""}</button>
        <button class="btn" data-act="sort">${icon("sort")}<span>${esc(sortName)}</span></button>
        <button class="btn" data-act="view" aria-label="Přepnout zobrazení">${icon(results.view === "grid" ? "list" : "tiles")}</button>
        <span class="count">${d.page < d.pages ? `${money(results.items.length)} z ${money(d.total)}` : ""}</span>
      </div>
      ${chips.length ? `<div class="chips">${chips.map(([t, q]) => `<a class="chip on" href="#/hledat?${q}" data-q="${esc(q)}">${esc(t)}<span class="x" aria-hidden="true">×</span></a>`).join("")}
        <button class="chip" data-act="save">Hlídat toto hledání</button></div>`
        : `<div class="chips"><button class="chip" data-act="save">Hlídat toto hledání</button></div>`}
      ${results.items.length ? shelf(results.items, (results.view === "list" ? "list" : "") + " wide")
        : `<div class="empty"><h2>Nic neodpovídá filtrům</h2><p>Zkus některý filtr zrušit nebo hledat obecněji.</p></div>`}
      ${d.page < d.pages ? `<div class="load-more"><button class="btn" data-act="more">Načíst dalších ${Math.min(30, d.total - results.items.length)}</button></div>` : ""}
    </div></div>`;
  bindFilterPanel($(".filters-aside"));
  view.onclick = async (e) => {
    const chip = e.target.closest("a.chip.on");
    if (chip) { e.preventDefault(); return applyParams(new URLSearchParams(chip.dataset.q)); }
    const b = e.target.closest("[data-act]");
    if (!b) return;
    const act = b.dataset.act;
    if (act === "filters") openFilterSheet();
    if (act === "sort") openSortSheet();
    if (act === "view") { results.view = results.view === "grid" ? "list" : "grid"; localStorage.setItem("ponk.view", results.view); drawResults(); }
    if (act === "save") openSaveSheet();
    if (act === "more") await loadMore(b);
  };
  setupInfinite();
}

async function loadMore(btn) {
  if (btn.disabled) return;
  btn.disabled = true; btn.textContent = "Načítám…";
  const before = results.items.length;
  try { await loadResults(true); } catch (e) { btn.disabled = false; btn.textContent = "Zkusit znovu"; return; }
  const d = results.data;
  $(".results .shelf").insertAdjacentHTML("beforeend", results.items.slice(before).map(tile).join(""));
  $(".toolbar .count").textContent = d.page < d.pages ? `${money(results.items.length)} z ${money(d.total)}` : "";
  const wrap = $(".load-more");
  if (d.page < d.pages) { btn.disabled = false; btn.textContent = `Načíst dalších ${Math.min(30, d.total - results.items.length)}`; setupInfinite(); }
  else wrap.remove();
}

function setupInfinite() {
  const btn = $(".load-more .btn");
  if (!btn || !("IntersectionObserver" in window)) return;
  const io = new IntersectionObserver((entries) => { if (entries[0].isIntersecting) { io.disconnect(); btn.click(); } }, { rootMargin: "600px" });
  io.observe(btn);
}

function filterPanel(f, p) {
  if (!f) return "";
  const store = state.meta.settings.store;
  const brands = p.get("brand")?.split("|") || [];
  const labels = p.get("label")?.split("|") || [];
  const catKey = f.categories.level;
  const up = p.get("cat3") ? ["cat3"] : p.get("cat2") ? ["cat2", "cat3"] : p.get("cat1") ? ["cat1", "cat2", "cat3"] : null;
  const grp = (title, body, cnt = "") => `<div class="fgroup"><h3>${title}${cnt ? `<span class="cnt">${cnt}</span>` : ""}</h3>${body}</div>`;
  let html = "";

  if (f.labels.length) html += grp("Nabídka", f.labels.map((l) => `<label class="check"><input type="checkbox" data-multi="label" value="${l.value}" ${labels.includes(l.value) ? "checked" : ""}><span>${esc(l.label)}</span><span class="c">${money(l.count)}</span></label>`).join(""));
  html += grp("Dostupnost", `
    <label class="toggle"><span>Skladem na prodejně ${esc(storeName(store))}</span><input type="checkbox" data-toggle="store" data-on="${store}" ${p.get("store") ? "checked" : ""}></label>
    <label class="toggle"><span>Skladem v e-shopu</span><input type="checkbox" data-toggle="online" data-on="1" ${p.get("online") ? "checked" : ""}></label>`);
  html += grp("Cena", `<div class="range"><input class="field" inputmode="numeric" data-price="pmin" placeholder="od ${money(f.price.min)}" value="${esc(p.get("pmin") || "")}">
    <span>–</span><input class="field" inputmode="numeric" data-price="pmax" placeholder="do ${money(f.price.max)}" value="${esc(p.get("pmax") || "")}"></div>`);
  html += grp("Skutečná sleva", `<p class="muted" style="margin:0 0 8px;font-size:14px">Počítá se proti nejnižší ceně za posledních 30 dní, ne proti „původní“ ceně.</p>
    <div class="chipset">${[10, 20, 30, 50, 70].map((v) => `<button class="chip" data-set="disc" data-v="${v}" aria-pressed="${p.get("disc") == v}">${v} %+</button>`).join("")}</div>`);
  html += grp("Zlevněno za posledních", `<div class="chipset">${[[1, "1 den"], [7, "7 dní"], [30, "30 dní"]].map(([v, t]) => `<button class="chip" data-set="drop_days" data-v="${v}" aria-pressed="${p.get("drop_days") == v}">${t}</button>`).join("")}</div>`);
  if (f.brands.length) {
    const top = f.brands.slice(0, 8), selectedExtra = f.brands.slice(8).filter((b) => brands.includes(b.value));
    html += grp("Značka", `${f.brands.length > 12 ? `<input class="field" data-brandfilter placeholder="Najít značku" style="margin-bottom:6px">` : ""}
      <div data-brandlist>${[...top, ...selectedExtra].map((b) => brandRow(b, brands)).join("")}</div>
      ${f.brands.length > 8 ? `<button class="link more-btn" data-allbrands>Všech ${f.brands.length} značek</button>` : ""}`, brands.length ? `${brands.length}` : "");
  }
  html += grp("Hodnocení", `<div class="chipset">${[4, 3].map((v) => `<button class="chip" data-set="rating" data-v="${v}" aria-pressed="${p.get("rating") == v}">${"★".repeat(v)} a víc</button>`).join("")}</div>`);
  html += grp("Ostatní", `<label class="toggle"><span>Jen s cenou za jednotku (Kč/m², Kč/kg…)</span><input type="checkbox" data-toggle="unit" data-on="1" ${p.get("unit") ? "checked" : ""}></label>`);
  for (const a of f.attrs || []) {
    const sel = p.get("a_" + a.code)?.split("|") || [];
    const open = sel.length > 0;
    html += `<div class="fgroup"><button class="fhead" aria-expanded="${open}" data-collapse><span>${esc(a.label)}</span><span class="cnt">${sel.length || ""}</span></button>
      <div ${open ? "" : "hidden"}>${a.values.map((v) => `<label class="check"><input type="checkbox" data-multi="a_${a.code}" value="${esc(v.value)}" ${sel.includes(v.value) ? "checked" : ""}><span>${esc(v.value)}</span><span class="c">${money(v.count)}</span></label>`).join("")}</div></div>`;
  }
  // kategorie až na konci, nahoře je Nabídka (Výprodej, Akce…)
  if (f.categories.values.length || up) {
    html += grp("Kategorie", `${up ? `<button class="catlink up" data-up="${up.join(",")}">← ${esc(p.get("cat2") && !p.get("cat3") ? p.get("cat1") : p.get("cat3") ? p.get("cat2") : "Všechny kategorie")}</button>` : ""}
      ${f.categories.values.filter((c) => c.value !== p.get(catKey)).slice(0, 40).map((c) => `<button class="catlink" data-cat="${catKey}" data-v="${esc(c.value)}"><span>${esc(c.value)}</span><span class="c">${money(c.count)}</span></button>`).join("")}`);
  }
  return html;
}

const brandRow = (b, sel) => `<label class="check"><input type="checkbox" data-multi="brand" value="${esc(b.value)}" ${sel.includes(b.value) ? "checked" : ""}><span>${esc(b.value)}</span><span class="c">${money(b.count)}</span></label>`;

function bindFilterPanel(root) {
  if (!root) return;
  const p = () => new URLSearchParams(results.params);
  root.onclick = (e) => {
    const t = e.target;
    const cat = t.closest("[data-cat]");
    if (cat) { const n = p(); n.set(cat.dataset.cat, cat.dataset.v); return applyParams(n); }
    const up = t.closest("[data-up]");
    if (up) { const n = p(); up.dataset.up.split(",").forEach((k) => n.delete(k)); return applyParams(n); }
    const set = t.closest("[data-set]");
    if (set) { const n = p(); const k = set.dataset.set; if (n.get(k) === set.dataset.v) n.delete(k); else n.set(k, set.dataset.v); if (k === "drop_days" && n.get(k)) n.set("sort", "drop"); return applyParams(n); }
    const col = t.closest("[data-collapse]");
    if (col) { const open = col.getAttribute("aria-expanded") !== "true"; col.setAttribute("aria-expanded", open); col.nextElementSibling.hidden = !open; }
    if (t.closest("[data-allbrands]")) {
      const sel = p().get("brand")?.split("|") || [];
      root.querySelector("[data-brandlist]").innerHTML = results.data.facets.brands.map((b) => brandRow(b, sel)).join("");
      t.remove();
    }
  };
  root.onchange = (e) => {
    const t = e.target;
    const n = p();
    if (t.dataset.toggle) { if (t.checked) n.set(t.dataset.toggle, t.dataset.on); else n.delete(t.dataset.toggle); return applyParams(n); }
    if (t.dataset.multi) {
      const k = t.dataset.multi, cur = new Set((n.get(k) || "").split("|").filter(Boolean));
      t.checked ? cur.add(t.value) : cur.delete(t.value);
      if (cur.size) n.set(k, [...cur].join("|")); else n.delete(k);
      return applyParams(n);
    }
    if (t.dataset.price) { const v = t.value.replace(/\D/g, ""); if (v) n.set(t.dataset.price, v); else n.delete(t.dataset.price); return applyParams(n); }
  };
  root.oninput = (e) => {
    if (!e.target.matches("[data-brandfilter]")) return;
    const term = e.target.value.toLowerCase();
    const sel = p().get("brand")?.split("|") || [];
    const list = results.data.facets.brands.filter((b) => b.value.toLowerCase().includes(term)).slice(0, 40);
    root.querySelector("[data-brandlist]").innerHTML = list.map((b) => brandRow(b, sel)).join("") || '<p class="muted">Žádná značka</p>';
  };
}

// --- spodní panely --------------------------------------------------------
function openSheet(kind, title, body, foot = "") {
  const s = $("#sheet");
  s.dataset.kind = kind;
  s.innerHTML = `<div class="sheet-head"><h2>${title}</h2><button data-close aria-label="Zavřít">×</button></div><div class="sheet-body">${body}</div>${foot ? `<div class="sheet-foot">${foot}</div>` : ""}`;
  s.hidden = false; $("#sheet-backdrop").hidden = false;
  document.body.style.overflow = "hidden";
  s.querySelector("[data-close]").onclick = closeSheet;
  return s;
}
function closeSheet() { $("#sheet").hidden = true; $("#sheet-backdrop").hidden = true; document.body.style.overflow = ""; }
$("#sheet-backdrop").onclick = closeSheet;
document.addEventListener("keydown", (e) => { if (e.key === "Escape") { closeSheet(); $("#suggest").hidden = true; } });

function openFilterSheet() {
  const s = openSheet("filters", "Filtry", "", `<button class="btn btn-quiet" data-reset>Zrušit vše</button><button class="btn btn-primary" data-close2></button>`);
  fillFilterSheet();
  s.querySelector("[data-close2]").onclick = closeSheet;
  s.querySelector("[data-reset]").onclick = () => { const n = new URLSearchParams(); ["q", "sort"].forEach((k) => results.params.get(k) && n.set(k, results.params.get(k))); applyParams(n); };
}
function fillFilterSheet() {
  const s = $("#sheet");
  const body = s.querySelector(".sheet-body");
  const y = body.scrollTop;
  body.innerHTML = filterPanel(results.data.facets, results.params);
  body.scrollTop = y;
  bindFilterPanel(body);
  s.querySelector("[data-close2]").textContent = `Zobrazit ${money(results.data.total)} ${plural(results.data.total, "produkt", "produkty", "produktů")}`;
}
function openSortSheet() {
  const cur = results.params.get("sort") || "relevance";
  const s = openSheet("sort", "Řazení", SORTS.map(([k, t]) => `<label class="radio-row"><input type="radio" name="sort" value="${k}" ${k === cur ? "checked" : ""}>${t}</label>`).join(""));
  s.onchange = (e) => { const n = new URLSearchParams(results.params); n.set("sort", e.target.value); closeSheet(); applyParams(n); };
}
function openSaveSheet() {
  const name = resultsTitle(results.params).replace(/[„“]/g, "");
  const s = openSheet("save", "Hlídat hledání", `<p class="muted">Po každé denní kontrole uvidíš v sekci Hlídané, kolik nových nebo zlevněných produktů odpovídá tomuto hledání.</p>
    <label class="lbl" for="sv-name" style="font-weight:800">Název</label><input class="field" id="sv-name" value="${esc(name)}" style="margin:6px 0 16px">`,
    `<button class="btn btn-primary" data-ok>Uložit hledání</button>`);
  s.querySelector("[data-ok]").onclick = async () => {
    const query = Object.fromEntries([...results.params].filter(([k]) => !["page", "sort"].includes(k)));
    await api("saved", { json: { name: $("#sv-name").value || name, query } });
    closeSheet(); toast("Hledání uloženo");
  };
}

// --- Detail produktu -------------------------------------------------------
async function Product(sku, refresh = false) {
  if (!refresh) view.innerHTML = `<div class="skeleton"></div>`;
  const p = await api(`product/${encodeURIComponent(sku)}${refresh ? "?refresh=1" : ""}`);
  if (!p) throw new Error("Produkt nebyl nalezen.");
  const my = state.meta.settings.store;
  const pics = [p.image, ...p.gallery.filter((g) => g !== p.image)].filter(Boolean).slice(0, 12);
  const stores = [...state.meta.stores].sort((a, b) => (a.code === my ? -1 : b.code === my ? 1 : a.name.localeCompare(b.name, "cs")));
  const pos = (code) => {
    const x = p.positions[code];
    if (!x || !x.shelf) return "";
    const note = x.zone && !/^R\d+\s+F\d+/.test(x.zone) ? ` <span>${esc(x.zone)}</span>` : "";
    return `<span class="aisle">Regál ${esc(x.shelf)}, pole ${esc(x.field)}${note}</span>`;
  };
  const why = p.real_discount
    ? `<div class="why">O <b>${p.real_discount} %</b> levnější než nejnižší cena za posledních 30 dní (${money(p.min30_price)} Kč).</div>` : "";
  const change = p.price_changed_at && p.prev_price
    ? `${p.price < p.prev_price ? "Zlevněno" : "Zdraženo"} ${day(p.price_changed_at)} z ${money(p.prev_price)} Kč.`
    : `Cena se nezměnila od ${day(p.first_seen)}, kdy ji Ponk začal sledovat.`;
  const watching = !!p.watch;
  view.innerHTML = `<article class="pd">
    <div><div class="gallery" id="gal">${pics.length ? pics.map((g, i) => `<img src="${img(g, 600, 744)}" alt="${i ? "" : esc(p.name)}" ${i ? 'loading="lazy"' : ""}>`).join("") : '<div class="empty noimg">Bez obrázku</div>'}</div>
      ${pics.length > 1 ? `<div class="dots">${pics.map((_, i) => `<i class="${i ? "" : "on"}"></i>`).join("")}</div>` : ""}</div>
    <div class="pd-main">
      <div><div class="crumbs">${p.cat_path.map((c, i) => `<a href="#/${i < 2 ? "kategorie" : "hledat"}?${qs({ cat1: p.cat_path[0], cat2: i >= 1 ? p.cat_path[1] : null, cat3: i >= 2 ? p.cat_path[2] : null })}">${esc(c)}</a>`).join("<span>/</span>")}</div>
        <h1>${esc(p.name)}</h1>${stars(p.rating, p.rating_count)}<div class="sub">${p.brand ? `${esc(p.brand)}, ` : ""}kód ${esc(p.sku)}${p.ean ? `, EAN ${esc(p.ean)}` : ""}${p.dims ? `<br>${esc(p.dims)}` : ""}</div></div>
      <div class="pricebox">${ptag(p, true)}${why}
        ${p.was_price ? `<div class="pmeta">Původně <s>${money(p.was_price)} Kč</s></div>` : ""}
        ${p.unit_price ? `<div class="pmeta">${nf2.format(p.unit_price)} Kč/${esc(p.unit)}</div>` : ""}
        <div class="pmeta">${change}</div></div>
      <div class="btn-row">
        <button class="btn ${watching ? "" : "btn-primary"}" id="watch">${icon("eye")}${watching ? "Přestat hlídat" : "Hlídat cenu"}</button>
        <a class="btn btn-quiet" href="https://www.bauhaus.cz/${esc(p.url_path)}" target="_blank" rel="noopener">${icon("ext")}Na bauhaus.cz</a>
        <button class="btn btn-quiet" id="refresh" aria-label="Aktualizovat cenu a sklad teď">${icon("refresh")}</button>
      </div>
      ${watching ? `<div class="pmeta">Hlídáš od ${day(p.watch.added)} (tehdy ${money(p.watch.added_price)} Kč)${p.watch.target ? `, cílová cena ${money(p.watch.target)} Kč` : ""}.</div>` : ""}
      ${p.labels.length ? `<div class="chipset">${p.labels.map((l) => `<span class="flag ${l === "sell_off" ? "red" : ""}">${esc(state.meta.labels[l] || l)}</span>`).join("")}</div>` : ""}
      ${p.usps.length ? `<ul class="usps">${p.usps.map((u) => `<li>${esc(u)}</li>`).join("")}</ul>` : ""}
      <section class="block"><h2>Kde je skladem</h2><div class="stores">
        <div class="store"><span class="sname">E-shop</span><span class="sq ${p.online_in_stock && p.online_qty > 0 ? "" : "no"}">${p.online_in_stock && p.online_qty > 0 ? `${money(p.online_qty)} ks` : "není"}</span></div>
        ${stores.map((s) => `<div class="store ${s.code === my ? "mine" : ""}"><span class="sname">${esc(s.name)}</span>
          <span class="sq ${p.stock[s.code] ? "" : "no"}">${p.stock[s.code] ? `${money(p.stock[s.code])} ks` : "není"}</span>${p.stock[s.code] ? pos(s.code) : ""}</div>`).join("")}
      </div></section>
      <section class="block"><h2>Vývoj ceny</h2>${chart(p.history, p.price)}</section>
      <section class="block"><h2>Hodnocení zákazníků</h2><div id="reviews"><p class="muted">Načítám recenze…</p></div></section>
      ${p.params.length ? `<section class="block"><h2>Parametry</h2><table class="params">${p.params.map((x) => `<tr><th>${esc(x.label)}</th><td>${esc(x.value)}</td></tr>`).join("")}</table></section>` : ""}
      ${p.description ? `<section class="block"><h2>Popis</h2><div class="desc">${sanitize(p.description)}</div></section>` : ""}
    </div></article>`;
  const gal = $("#gal");
  if (gal && pics.length > 1) gal.onscroll = () => { const i = Math.round(gal.scrollLeft / gal.clientWidth); $$(".dots i").forEach((d, j) => d.classList.toggle("on", i === j)); };
  $("#watch").onclick = () => (watching ? unwatch(p.sku) : openWatchSheet(p));
  loadReviews(p.sku);
  $("#refresh").onclick = async (e) => { e.currentTarget.disabled = true; try { await Product(sku, true); toast("Cena a sklad aktualizovány"); } catch { toast("Bauhaus teď nejde načíst. Jsi online?"); } };
}

// Recenze živě z Bauhausu (přes lokální server), i přeložené ze zahraničních webů BAUHAUS.
async function loadReviews(sku, cursor = null) {
  const box = $("#reviews");
  if (!box) return;
  let r;
  try { r = await api(`reviews/${encodeURIComponent(sku)}${cursor ? `?cursor=${encodeURIComponent(cursor)}` : ""}`); }
  catch { if (!cursor) box.innerHTML = `<p class="muted">Recenze se nepodařilo načíst.</p>`; return; }
  if (!cursor && !r.count && !r.items.length) { box.innerHTML = `<p class="muted">Zatím bez recenzí. Hodnocení se sbírá ze všech webů BAUHAUS (Česko, Německo, Rakousko…).</p>`; return; }
  const card = (x) => `<div class="review">
      <div class="rhead">${stars(x.rating * 20, 0, false)}${x.title ? `<b>${esc(x.title)}</b>` : ""}</div>
      <p data-t="${esc(x.text)}" data-o="${esc(x.original || "")}">${esc(x.text)}</p>
      <div class="rmeta">${esc(x.author)} · ${new Date(x.date).toLocaleDateString("cs-CZ")}${x.verified ? " · ověřený nákup" : ""}${x.recommended ? " · 👍" : ""}</div>
      ${x.translated ? `<button class="link" data-orig>Přeloženo · ${esc(x.country)}${x.source ? ` (${esc(x.source)})` : ""} · originál</button>` : ""}
      ${x.replies.map((rep) => `<div class="reply"><b>Odpověď BAUHAUS</b><br>${esc(rep.text)}</div>`).join("")}</div>`;
  const more = r.next ? `<button class="btn" data-more="${esc(r.next)}">Další recenze</button>` : "";
  if (!cursor) {
    const bars = r.distribution.map((n, i) => `<div class="bar"><span>${5 - i}</span><i><u style="width:${r.count ? (n / r.count) * 100 : 0}%"></u></i><span>${n}</span></div>`).join("");
    box.innerHTML = `<div class="rsum"><div class="ravg"><b>${r.average.toFixed(1).replace(".", ",")}</b>${stars(Math.round(r.average * 20), r.count, false)}<span>${r.count} hodnocení</span></div><div class="rbars">${bars}</div></div>
      <div class="rlist">${r.items.map(card).join("")}</div>${more}`;
  } else {
    box.querySelector("[data-more]")?.remove();
    box.querySelector(".rlist").insertAdjacentHTML("beforeend", r.items.map(card).join(""));
    box.insertAdjacentHTML("beforeend", more);
  }
  box.onclick = (e) => {
    const m = e.target.closest("[data-more]");
    if (m) { m.disabled = true; return loadReviews(sku, m.dataset.more); }
    const o = e.target.closest("[data-orig]");
    if (o) {
      const p = o.parentElement.querySelector("p[data-o]");
      const showOrig = p.textContent === p.dataset.t;
      p.textContent = showOrig ? p.dataset.o : p.dataset.t;
      o.textContent = showOrig ? "Zobrazit překlad" : o.dataset.label || "Přeloženo · originál";
    }
  };
  box.querySelectorAll("[data-orig]").forEach((b) => { if (!b.dataset.label) b.dataset.label = b.textContent; });
}

async function unwatch(sku) { await api("watch/" + encodeURIComponent(sku), { method: "DELETE" }); toast("Už nehlídáš"); refreshMeta(); Product(sku); }

function openWatchSheet(p) {
  const s = openSheet("watch", "Hlídat cenu", `<p class="muted">Zlevnění uvidíš v sekci Hlídané a na úvodní stránce. Cílová cena je nepovinná.</p>
    <label for="w-target" style="font-weight:800">Upozornit, až cena klesne na</label>
    <div class="range" style="grid-template-columns:1fr auto;margin:6px 0 16px"><input class="field" id="w-target" inputmode="numeric" placeholder="např. ${money(p.price * 0.8)}"><span>Kč</span></div>`,
    `<button class="btn btn-primary" data-ok>Hlídat cenu</button>`);
  s.querySelector("[data-ok]").onclick = async () => {
    const t = $("#w-target").value.replace(/\D/g, "");
    await api("watch", { json: { sku: p.sku, target: t ? +t : null } });
    closeSheet(); toast("Hlídáš cenu"); refreshMeta(); Product(p.sku);
  };
}

function chart(hist, price) {
  if (!hist.length || hist.length < 2) return `<p class="muted">Ponk zatím zná jen dnešní cenu. Každá další denní kontrola přidá bod a uvidíš, jak se cena vyvíjí.</p>`;
  const W = 380, H = 170, L = 44, R = 8, T = 10, B = 24;
  const pts = hist.map((h) => ({ t: new Date(h.day + "T00:00:00").getTime(), v: h.price }));
  pts.push({ t: Date.now(), v: price });
  const t0 = pts[0].t, t1 = pts[pts.length - 1].t || t0 + 1;
  let lo = Math.min(...pts.map((p) => p.v)), hi = Math.max(...pts.map((p) => p.v));
  if (hi === lo) { hi += hi * 0.1 || 1; lo -= lo * 0.1 || 1; }
  const pad = (hi - lo) * 0.12; lo -= pad; hi += pad;
  const x = (t) => L + ((t - t0) / (t1 - t0 || 1)) * (W - L - R);
  const y = (v) => T + (1 - (v - lo) / (hi - lo)) * (H - T - B);
  let d = `M${x(pts[0].t)},${y(pts[0].v)}`;
  for (let i = 1; i < pts.length; i++) d += `H${x(pts[i].t)}V${y(pts[i].v)}`;
  const area = `${d}V${H - B}H${x(pts[0].t)}Z`;
  const ticks = [lo + pad, (lo + hi) / 2, hi - pad];
  const min = Math.min(...hist.map((h) => h.price)), max = Math.max(...hist.map((h) => h.price));
  return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="Vývoj ceny od ${day(hist[0].day)}: nejníže ${money(min)} Kč, nejvýš ${money(max)} Kč">
    ${ticks.map((v) => `<line class="grid" x1="${L}" x2="${W - R}" y1="${y(v)}" y2="${y(v)}"/><text x="${L - 6}" y="${y(v) + 4}" text-anchor="end">${money(v)}</text>`).join("")}
    <path class="area" d="${area}"/><path class="ln" d="${d}"/>
    <circle class="now" cx="${x(pts[pts.length - 1].t)}" cy="${y(price)}" r="5"/>
    <text x="${L}" y="${H - 6}">${day(hist[0].day)}</text><text x="${W - R}" y="${H - 6}" text-anchor="end">dnes</text></svg>
    <p class="pmeta">Nejníže ${money(min)} Kč, nejvýš ${money(max)} Kč za dobu sledování.</p>`;
}

// --- Hlídané -----------------------------------------------------------------
async function Watch() {
  const [w, s] = await Promise.all([api("watch"), api("saved")]);
  view.innerHTML = `<div class="page-title"><h1>Hlídané</h1></div>
    <section class="section"><div class="section-head"><h2>Produkty</h2></div>
      ${w.items.length ? shelf(w.items.map((it) => ({ ...it, prev_price: it.added_price && it.added_price !== it.price ? it.added_price : null })), "list")
        : `<div class="empty"><h2>Zatím nic nehlídáš</h2><p>V detailu produktu klepni na Hlídat cenu.</p></div>`}</section>
    <section class="section"><div class="section-head"><h2>Hledání</h2></div>
      ${s.items.length ? `<div class="rowlist">${s.items.map((x) => `<div class="row"><a class="grow" href="#/hledat?${qs(x.query)}" data-seen="${x.id}" style="text-decoration:none">
          <div class="title">${esc(x.name)}</div><div class="meta">${money(x.total)} ${plural(x.total, "produkt", "produkty", "produktů")}</div></a>
          ${x.fresh ? `<span class="fresh">${x.fresh} ${plural(x.fresh, "novinka", "novinky", "novinek")}</span>` : ""}
          <button class="link" data-del="${x.id}">Smazat</button></div>`).join("")}</div>`
        : `<div class="empty"><h2>Žádná uložená hledání</h2><p>Ve výsledcích hledání klepni na Hlídat toto hledání.</p></div>`}</section>`;
  view.onclick = async (e) => {
    const del = e.target.closest("[data-del]");
    if (del) { await api("saved/" + del.dataset.del, { method: "DELETE" }); Watch(); }
    const seen = e.target.closest("[data-seen]");
    if (seen) api(`saved/${seen.dataset.seen}/seen`, { method: "DELETE" });
  };
}

// --- Více / nastavení ---------------------------------------------------------
function syncPanel() {
  const st = state.meta.sync;
  const pct = st.total ? Math.round((st.done / st.total) * 100) : 0;
  return `<div class="panel" data-sync style="display:grid;gap:10px">
    <div style="display:flex;justify-content:space-between;gap:12px;align-items:center"><div>
      <div style="font-weight:800;font-size:17px">${st.running ? esc(st.phase) : "Kontrola cen"}</div>
      <div class="muted" style="font-size:14px">${st.running ? `${money(st.done)} z ${money(st.total)}` : st.message ? esc(st.message) : `Naposledy ${dayTime(state.meta.last_run?.finished)}`}</div></div>
      <button class="btn btn-quiet" data-syncnow ${st.running ? "disabled" : ""}>${st.running ? "Probíhá…" : "Zkontrolovat teď"}</button></div>
    ${st.running ? `<div class="progress"><i style="width:${pct}%"></i></div>` : ""}</div>`;
}

function watchSync() {
  clearInterval(state.syncTimer);
  const tick = async () => {
    state.meta.sync = await api("sync");
    $$("[data-sync]").forEach((el) => (el.outerHTML = syncPanel()));
    bindSyncButtons();
    if (!state.meta.sync.running) { clearInterval(state.syncTimer); refreshMeta(); }
  };
  bindSyncButtons();
  state.syncTimer = setInterval(tick, 2500);
}
function bindSyncButtons() {
  $$("[data-syncnow]").forEach((b) => (b.onclick = async () => { state.meta.sync = await api("sync", { method: "POST" }); $$("[data-sync]").forEach((el) => (el.outerHTML = syncPanel())); watchSync(); }));
}

async function More() {
  state.meta = await api("meta");
  const m = state.meta, s = m.settings;
  const theme = localStorage.getItem("ponk.theme") || "system";
  const font = document.documentElement.dataset.font || "barlow";
  view.innerHTML = `<div class="page-title"><h1>Více</h1></div>
    <section class="section">${syncPanel()}</section>
    <section class="section"><div class="panel" style="padding:0">
      <div class="setting"><label for="st-store">Moje prodejna</label>
        <select class="field" id="st-store">${m.stores.map((x) => `<option value="${x.code}" ${x.code === s.store ? "selected" : ""}>${esc(x.name)}</option>`).join("")}</select>
        <span class="muted" style="font-size:14px">Podle ní se ukazuje skladovost na dlaždicích a filtr Skladem na prodejně.</span></div>
      <div class="setting"><label for="st-time">Denní kontrola cen</label>
        <input class="field" type="time" id="st-time" value="${esc(s.sync_time)}" style="max-width:160px">
        <span class="muted" style="font-size:14px">Počítač musí běžet. Když v tu dobu neběží, kontrola proběhne hned po zapnutí. Celý katalog trvá zhruba 30–40 minut.</span></div>
      <div class="setting"><label class="toggle" style="padding:0"><span class="lbl" style="font-weight:800">Stahovat skladovost na prodejnách</span><input type="checkbox" id="st-stock" ${s.sync_stock === "1" ? "checked" : ""}></label>
        <span class="muted" style="font-size:14px">Bez ní je kontrola asi o polovinu rychlejší, ale nepůjde filtrovat podle prodejny.</span></div>
      <div class="setting"><span class="lbl">Vzhled</span><div class="seg" role="group" aria-label="Vzhled">
        ${[["system", "Podle systému"], ["light", "Světlý"], ["dark", "Tmavý"]].map(([k, t]) => `<button data-theme="${k}" aria-pressed="${theme === k}">${t}</button>`).join("")}</div></div>
      <div class="setting"><span class="lbl">Písmo</span><div class="fontpick">
        ${FONTS.map(([k, n]) => `<button data-font="${k}" aria-pressed="${font === k}" style="font-family:'${n}'"><span class="fs">Akumulátorový šroubovák</span><span class="fp">1 290 Kč</span><span class="fn">${n}</span></button>`).join("")}</div></div>
    </div></section>
    <section class="section"><div class="panel">
      <p style="margin:0 0 8px"><b>Ponk</b> je neoficiální open-source klient pro veřejně dostupná data z bauhaus.cz. Není nijak spojený se společností BAUHAUS. Názvy, ceny a obrázky patří jejich vlastníkům.</p>
      <p class="muted" style="margin:0">Verze ${esc(m.version || "")}. V databázi je ${money(m.products)} aktivních produktů. Licence MIT.</p></div></section>`;
  if (m.sync.running) watchSync(); else bindSyncButtons();
  const save = async (obj) => { await api("settings", { json: obj }); state.meta = await api("meta"); toast("Uloženo"); };
  $("#st-store").onchange = (e) => { state.cache.clear(); save({ store: e.target.value }); };
  $("#st-time").onchange = (e) => save({ sync_time: e.target.value });
  $("#st-stock").onchange = (e) => save({ sync_stock: e.target.checked ? "1" : "0" });
  view.querySelector(".seg").onclick = (e) => {
    const b = e.target.closest("[data-theme]"); if (!b) return;
    const t = b.dataset.theme;
    if (t === "system") { localStorage.removeItem("ponk.theme"); delete document.documentElement.dataset.theme; }
    else { localStorage.setItem("ponk.theme", t); document.documentElement.dataset.theme = t; }
    $$(".seg button").forEach((x) => x.setAttribute("aria-pressed", x === b));
  };
  view.querySelector(".fontpick").onclick = (e) => {
    const b = e.target.closest("[data-font]"); if (!b) return;
    localStorage.setItem("ponk.font", b.dataset.font);
    document.documentElement.dataset.font = b.dataset.font;
    $$(".fontpick button").forEach((x) => x.setAttribute("aria-pressed", x === b));
  };
}

async function refreshMeta() { try { state.meta = await api("meta"); renderNav(); } catch {} }

// --- vyhledávání s našeptávačem -----------------------------------------------
(function setupSearch() {
  const form = $("#search-form"), input = $("#q"), box = $("#suggest"), clear = $("#q-clear");
  let timer, active = -1;
  form.onsubmit = (e) => {
    e.preventDefault();
    const a = box.querySelectorAll("a")[active];
    if (a && !box.hidden) { location.hash = a.getAttribute("href"); }
    else if (input.value.trim()) location.hash = "#/hledat?" + qs({ q: input.value.trim() });
    box.hidden = true; input.blur();
  };
  clear.onclick = () => { input.value = ""; clear.hidden = true; box.hidden = true; input.focus(); };
  input.oninput = () => {
    clear.hidden = !input.value;
    clearTimeout(timer);
    timer = setTimeout(async () => {
      const t = input.value.trim();
      if (t.length < 2) { box.hidden = true; return; }
      const s = await api("suggest?" + qs({ q: t }));
      active = -1;
      const rows = [
        ...s.categories.map((c) => `<a href="#/hledat?${qs({ cat1: c.cat1, cat2: c.cat2, cat3: c.cat3 })}"><span>${esc(c.name)}</span><span class="s-kind">kategorie</span></a>`),
        ...s.brands.map((b) => `<a href="#/hledat?${qs({ brand: b })}"><span>${esc(b)}</span><span class="s-kind">značka</span></a>`),
        ...s.products.map((p) => `<a href="#/p/${encodeURIComponent(p.sku)}">${p.image ? `<img src="${img(p.image, 80, 99)}" alt="">` : ""}<span>${esc(p.name)}</span><span class="s-price">${money(p.price)} Kč</span></a>`),
      ];
      box.innerHTML = rows.join("") + `<a href="#/hledat?${qs({ q: t })}"><span>Všechny výsledky pro „${esc(t)}“</span></a>`;
      box.hidden = false;
    }, 140);
  };
  input.onkeydown = (e) => {
    const links = box.querySelectorAll("a");
    if (box.hidden || !links.length) return;
    if (e.key === "ArrowDown" || e.key === "ArrowUp") {
      e.preventDefault();
      active = (active + (e.key === "ArrowDown" ? 1 : -1) + links.length) % links.length;
      links.forEach((l, i) => l.classList.toggle("active", i === active));
    }
  };
  box.onclick = () => { box.hidden = true; input.blur(); };
  document.addEventListener("click", (e) => { if (!form.contains(e.target)) box.hidden = true; });
})();

// --- start ---------------------------------------------------------------------
window.addEventListener("hashchange", render);
(async () => {
  try { state.meta = await api("meta"); } catch (e) { state.meta = { settings: {}, stores: [], labels: {}, sync: {}, products: 0 }; }
  render();
})();
