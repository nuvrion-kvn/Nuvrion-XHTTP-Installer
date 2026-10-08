import {
  countries,
  styles,
  flag,
  formatAbv,
  defaults,
  parseState,
  stateParams,
  filterBeers,
  escapeHtml as esc,
} from "./catalog.mjs";
import { copy, guides, ingredients } from "./content.mjs";
import { startTopography } from "./topography.mjs";

const paths = {
  pause: "M8 5v14M16 5v14",
  play: "m8 4 12 8-12 8V4Z",
  heart:
    "M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.7l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.6a5.5 5.5 0 0 0 0-7.8Z",
  arrow: "M4 12h16m-6-6 6 6-6 6",
  arrowDown: "M12 4v16m-6-6 6 6 6-6",
  close: "M6 6l12 12M6 18 18 6",
  search: "M21 21l-5-5M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0",
  plus: "M12 5v14M5 12h14",
  layers: "m12 3 10 6-10 6L2 9l10-6ZM2 13l10 6 10-6M2 17l10 6 10-6",
  glass: "M6 3h12l-1 9a5 5 0 0 1-10 0L6 3Zm6 14v5m-4 0h8M7 7h10",
  wheat:
    "M12 22V3m0 5C6 8 6 4 6 4s6 0 6 4Zm0 5c-6 0-6-4-6-4s6 0 6 4Zm0 5c-6 0-6-4-6-4s6 0 6 4Zm0-10c6 0 6-4 6-4s-6 0-6 4Zm0 5c6 0 6-4 6-4s-6 0-6 4Zm0 5c6 0 6-4 6-4s-6 0-6 4Z",
  hop: "M12 2c5 2 8 5 8 10 0 4-4 8-8 10-4-2-8-6-8-10 0-5 3-8 8-10Zm0 0v20M5 8l7 5 7-5M5 13l7 5 7-5M7 4l5 4 5-4",
  drop: "M12 2s7 9 7 13a7 7 0 0 1-14 0c0-4 7-13 7-13ZM8 15a4 4 0 0 0 4 4",
  spark: "m12 2 3 7 7 3-7 3-3 7-3-7-7-3 7-3 3-7Z",
  fruit:
    "M12 8c-5-5-11 0-9 7 1 5 5 8 9 5 4 3 8 0 9-5 2-7-4-12-9-7Zm0 0c0-4 4-6 7-5-1 4-4 5-7 5Zm0-1-2-5",
  zero: "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20ZM5 5l14 14",
  external:
    "M14 3h7v7m0-7L10 14M10 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-5",
  link: "M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-2 2M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l2-2",
};
function icon(name) {
  return `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[name] || paths.glass}"/></svg>`;
}
const $ = (id) => document.getElementById(id);
let state = parseState(location.search),
  beers = [],
  loadFailed = false,
  selectedId = null,
  isAbout = false,
  returnFocus = null,
  toastTimer,
  loadRequest;
let favorites = new Set();
try {
  const saved = JSON.parse(localStorage.getItem("malt-favorites") || "[]");
  if (Array.isArray(saved))
    favorites = new Set(saved.filter((v) => typeof v === "string"));
} catch {}
const t = (key) => copy[state.lang][key];
const local = (v) => v?.[state.lang] ?? "";
const countryName = (code) => countries[code]?.[state.lang] || code;
let motionPaused = false;
try {
  motionPaused = localStorage.getItem("malt-motion-paused") === "1";
} catch {}
const topography = startTopography($("topography-bg"), {
  paused: motionPaused,
});
function renderMotion() {
  const button = $("motion-toggle");
  const key = topography.reducedMotion
    ? "staticBackground"
    : topography.paused
      ? "resumeBackground"
      : "pauseBackground";
  button.disabled = topography.reducedMotion;
  document.documentElement.dataset.motionPaused = String(topography.paused);
  document.documentElement.dataset.motionSuspended = String(document.hidden);
  button.setAttribute("aria-pressed", String(topography.paused));
  button.setAttribute("aria-label", t(key));
  button.innerHTML =
    icon(topography.paused ? "play" : "pause") + `<span>${t(key)}</span>`;
}

document
  .querySelectorAll("[data-icon]")
  .forEach((el) => (el.innerHTML = icon(el.dataset.icon)));
function notify(key) {
  clearTimeout(toastTimer);
  $("toast").hidden = true;
  $("dialog-feedback").hidden = true;
  const target = $("detail-dialog").open ? $("dialog-feedback") : $("toast");
  target.textContent = t(key);
  target.hidden = false;
  toastTimer = setTimeout(() => (target.hidden = true), 4000);
}
function url(beerId = selectedId) {
  const params = stateParams(state, beerId);
  return location.pathname + (params.size ? "?" + params.toString() : "");
}
function syncUrl(push = false) {
  history[push ? "pushState" : "replaceState"](null, "", url());
}
function renderChrome() {
  document.documentElement.lang = state.lang;
  document.title = selectedId
    ? `${local(beers.find((b) => b.id === selectedId)?.name)} — ${t("brandName")}`
    : t("title");
  document.querySelector("meta[name=description]").content =
    state.lang === "ru"
      ? "Атлас пива — интерактивный каталог российского и зарубежного пива с подробным составом, крепостью и географией."
      : "Beer Atlas — an interactive catalog of Russian and international beers with detailed ingredients, ABV and origin.";
  document
    .querySelectorAll("[data-i18n]")
    .forEach((el) => (el.textContent = t(el.dataset.i18n)));
  document
    .querySelectorAll("[data-locale]")
    .forEach((el) =>
      el.setAttribute("aria-pressed", String(el.dataset.locale === state.lang)),
    );
  const brandWords = t("brandName")
    .toLocaleUpperCase(state.lang)
    .split(" ")
    .map((word) => `<span class="brand-line">${esc(word)}</span>`)
    .join(" ");
  $("brand-name").innerHTML = brandWords;
  $("footer-brand").innerHTML = brandWords;
  $("footer-brand").setAttribute("aria-label", t("brandName"));
  $("brand-link").setAttribute(
    "aria-label",
    state.lang === "ru" ? "Атлас пива — на главную" : "Beer Atlas — home",
  );
  $("top-nav").setAttribute("aria-label", t("navigation"));
  $("origin-group").setAttribute("aria-label", t("originLabel"));
  $("style-filters").setAttribute("aria-label", t("styleLabel"));
  $("beer-search").placeholder = t("searchPlaceholder");
  $("beer-search").value = state.q;
  $("clear-search").setAttribute("aria-label", t("clearSearch"));
  $("clear-search").hidden = !state.q;
  document
    .querySelectorAll("[data-origin]")
    .forEach((el) =>
      el.setAttribute(
        "aria-pressed",
        String(el.dataset.origin === state.origin),
      ),
    );
  $("style-filters").innerHTML = Object.entries(styles)
    .map(
      ([key, s]) =>
        `<button type="button" class="filter-chip" data-style="${key}" aria-pressed="${state.style === key}">${icon(s.icon)}<span>${s[state.lang]}</span></button>`,
    )
    .join("");
  const present = [...new Set(beers.map((b) => b.country))].sort((a, b) =>
    countryName(a).localeCompare(countryName(b), state.lang),
  );
  $("country-select").innerHTML =
    `<option value="all">${t("allCountries")}</option>` +
    present
      .map((code) => `<option value="${code}">${countryName(code)}</option>`)
      .join("");
  $("country-select").value = state.country;
  $("strength-select").innerHTML = [
    ["all", "allStrengths"],
    ["light", "lightStrength"],
    ["medium", "mediumStrength"],
    ["strong", "strongStrength"],
  ]
    .map(([val, key]) => `<option value="${val}">${t(key)}</option>`)
    .join("");
  $("strength-select").value = state.strength;
  $("sort-select").innerHTML = [
    ["collection", "sortCollection"],
    ["name", "sortName"],
    ["abv-up", "sortLow"],
    ["abv-down", "sortHigh"],
  ]
    .map(([val, key]) => `<option value="${val}">${t(key)}</option>`)
    .join("");
  $("sort-select").value = state.sort;
  $("close-dialog").setAttribute("aria-label", t("closeDialog"));
  const strip = ["RU", "DE", "BE", "CZ", "IE", "GB", "US", "JP"];
  const stripItems = strip
    .map((c) => `<span>${countryName(c)}</span>`)
    .join("");
  $("country-strip").innerHTML = Array.from(
    { length: 4 },
    (_, index) =>
      `<div class="strip-copy"${index ? ' aria-hidden="true"' : ""}>${stripItems}</div>`,
  ).join("");
  $("hero-total").textContent = beers.length || "—";
  $("all-count").textContent = beers.length || "—";
  renderMotion();
  updateFavoriteUI();
  renderGuide();
}
function updateFavoriteUI() {
  $("fav-count").textContent = favorites.size;
  for (const id of ["favorites-top", "favorites-filter"])
    $(id).setAttribute("aria-pressed", String(state.favorites));
  document.querySelectorAll("[data-favorite]").forEach((button) => {
    const saved = favorites.has(button.dataset.favorite);
    const b = beers.find((b) => b.id === button.dataset.favorite);
    button.setAttribute("aria-pressed", String(saved));
    button.setAttribute(
      "aria-label",
      (saved ? t("removeFavorite") : t("addFavorite")) +
        (b ? " — " + local(b.name) : ""),
    );
    if (button.classList.contains("detail-favorite"))
      button.innerHTML =
        icon("heart") +
        `<span>${saved ? t("savedBeer") : t("saveBeer")}</span>`;
  });
}
function productImage(b, detail = false) {
  const type = b.imageType === "photo" ? "photo" : "packshot";
  const scaled = /ru-jaws-(ipa|stout)/.test(b.id) ? " image-padded" : "";
  return `<img class="${detail ? "" : "product-image "}${type}${scaled}" src="${esc(b.image)}" alt="${esc(local(b.name))}" ${detail ? "" : 'loading="lazy"'} decoding="async" width="458" height="458">`;
}
function card(b) {
  const color = /^#[a-f0-9]{6}$/i.test(b.color) ? b.color : "#e5bd7c";
  return `<article class="beer-card"><button type="button" class="card-open" data-beer="${b.id}" aria-label="${esc(local(b.name))} — ${t("beerPassport")}"><span class="card-stage" style="--beer-color:${color}">${productImage(b)}<span class="card-country"><span class="country-flag" aria-hidden="true">${flag(b.country)}</span><span class="country-text">${countryName(b.country)}</span></span><span class="card-abv">${formatAbv(b.abv, state.lang)}</span></span><span class="card-info"><span class="card-style">${esc(local(b.styleName))}</span><span class="card-name">${esc(local(b.name))}</span><span class="card-brewery"><span>${esc(local(b.brewery))}</span>${icon("arrow")}</span></span></button><button type="button" class="card-favorite" data-favorite="${b.id}" aria-pressed="${favorites.has(b.id)}" aria-label="${esc((favorites.has(b.id) ? t("removeFavorite") : t("addFavorite")) + " — " + local(b.name))}">${icon("heart")}</button></article>`;
}
function filterActive() {
  return (
    state.q ||
    state.origin !== "all" ||
    state.style !== "all" ||
    state.country !== "all" ||
    state.strength !== "all" ||
    state.sort !== "collection"
  );
}
function renderGrid() {
  $("beer-grid").setAttribute(
    "aria-busy",
    String(!beers.length && !loadFailed),
  );
  if (loadFailed) {
    $("beer-grid").innerHTML =
      `<div class="empty-state">${icon("layers")}<h3>${t("loadError")}</h3><p>${t("loadErrorText")}</p><button type="button" class="button outline" data-retry>${t("retry")}</button></div>`;
    $("results-count").textContent = t("loadError");
    $("load-more").hidden = true;
    return;
  }
  if (!beers.length) {
    $("beer-grid").innerHTML =
      `<div class="loading-state"><span class="spinner"></span><p>${t("loading")}</p></div>`;
    $("results-count").textContent = t("loading");
    return;
  }
  const filtered = filterBeers(beers, state, favorites);
  const visible = filtered.slice(0, state.limit);
  $("results-count").textContent =
    state.lang === "ru"
      ? `Найдено ${filtered.length} из ${beers.length} сортов`
      : `${filtered.length} of ${beers.length} beers found`;
  $("beer-grid").innerHTML = visible.length
    ? visible.map(card).join("")
    : `<div class="empty-state">${icon(state.favorites ? "heart" : "search")}<h3>${t(state.favorites && favorites.size === 0 ? "noFavorites" : "noResults")}</h3><p>${t(state.favorites && favorites.size === 0 ? "noFavoritesText" : "noResultsText")}</p><button type="button" class="button outline" data-reset>${t(state.favorites && favorites.size === 0 ? "backCollection" : "resetFilters")}</button></div>`;
  $("load-more").hidden = visible.length >= filtered.length;
  $("shown-count").textContent = filtered.length
    ? state.lang === "ru"
      ? `Показано ${visible.length} из ${filtered.length}`
      : `Showing ${visible.length} of ${filtered.length}`
    : "";
  $("reset-filters").hidden = !filterActive();
  updateFavoriteUI();
}
function renderGuide() {
  $("style-guide").innerHTML = guides
    .map(
      (g) =>
        `<button type="button" class="guide-card" data-guide-style="${g.style}">${icon(styles[g.style].icon)}<span class="guide-tag">${local(g.tag)}</span><h3>${styles[g.style][state.lang]}</h3><p>${local(g.description)}</p><span class="guide-action">${t("seeStyle")}${icon("arrow")}</span></button>`,
    )
    .join("");
  $("ingredient-list").innerHTML = ingredients
    .slice(0, 4)
    .map(
      (i) =>
        `<details><summary>${icon(i.icon)}<h3>${local(i.name)}</h3><span class="ingredient-hint">${local(i.hint)}</span><span class="plus" aria-hidden="true">+</span></summary><p>${local(i.text)}</p></details>`,
    )
    .join("");
}
function updateFilters(patch) {
  state = { ...state, ...patch, limit: 20 };
  syncUrl();
  renderChrome();
  renderGrid();
}
function toggleFavorite(id) {
  const button = document.activeElement;
  const added = !favorites.has(id);
  added ? favorites.add(id) : favorites.delete(id);
  try {
    localStorage.setItem("malt-favorites", JSON.stringify([...favorites]));
    notify(added ? "added" : "removed");
  } catch {
    notify("storageNote");
  }
  if (state.favorites) {
    renderGrid();
    if (button?.classList.contains("card-favorite")) {
      const next = $("beer-grid").querySelector("[data-favorite]");
      if (next) next.focus();
      else $("favorites-filter").focus();
    }
  } else updateFavoriteUI();
  updateFavoriteUI();
}
function renderDetail(b) {
  $("dialog-eyebrow").textContent = t("beerPassport");
  const known = ingredients.filter((i) =>
    i.match.test([...b.ingredients.ru, ...b.ingredients.en].join(" ")),
  );
  $("detail-content").innerHTML =
    `<div class="detail-layout"><div class="detail-stage ${b.imageType === "photo" ? "photo-stage" : ""}">${productImage(b, true)}</div><div class="detail-side"><p class="detail-style">${esc(local(b.styleName))}</p><h2 id="detail-title">${esc(local(b.name))}</h2><p class="detail-description">${esc(local(b.description))}</p><div class="detail-metrics"><div><span class="metric-label">${t("strength")} / ABV</span><strong class="metric-value abv">${formatAbv(b.abv, state.lang)}</strong></div><div><span class="metric-label">${t("origin")}</span><strong class="metric-value">${flag(b.country)} ${countryName(b.country)}</strong><span class="metric-sub">${esc(local(b.city))}</span></div></div><div class="detail-actions"><button class="detail-favorite" type="button" data-favorite="${b.id}" aria-pressed="${favorites.has(b.id)}">${icon("heart")}<span>${t(favorites.has(b.id) ? "savedBeer" : "saveBeer")}</span></button><button class="detail-share" type="button" data-share>${icon("link")}<span>${t("share")}</span></button></div><section class="detail-section"><h3>${t("composition")}</h3><div class="ingredient-tags">${b.ingredients[state.lang].map((i) => `<span>${esc(i)}</span>`).join("")}</div><p class="composition-note ${b.ingredientsVerified ? "verified" : ""}">${t(b.ingredientsVerified ? "compositionVerified" : "compositionPartial")}</p></section><section class="detail-section"><h3>${t("ingredientMeaning")}</h3><div class="ingredient-list detail-ingredients">${known.map((i) => `<details><summary>${icon(i.icon)}<h3>${local(i.name)}</h3><span class="plus" aria-hidden="true">+</span></summary><p>${local(i.text)}</p></details>`).join("")}</div></section><section class="detail-section"><h3>${t("tasteTitle")}</h3><div class="detail-info-grid"><div><p class="info-label">${t("aroma")}</p><p>${esc(local(b.aroma))}</p></div><div><p class="info-label">${t("taste")}</p><p>${esc(local(b.taste))}</p></div><div class="full"><p class="info-label">${t("serving")}</p><p>${esc(local(b.serve))}</p></div></div></section><section class="detail-section"><h3>${t("pairing")}</h3><div class="pairing-tags">${b.food[state.lang].map((f) => `<span>${esc(f)}</span>`).join("")}</div><p class="detail-legal">${t("pairingNote")}</p></section><section class="detail-section"><h3>${t("brewery")}</h3><p>${esc(local(b.brewery))} · ${esc(local(b.city))}</p>${b.note ? `<p class="detail-legal">${esc(local(b.note))}</p>` : ""}</section><section class="detail-section"><h3>${t("sources")}</h3><div class="source-links">${b.sources.map((s) => `<a href="${esc(s.url)}" target="_blank" rel="noopener noreferrer">${t("sourceLabel")} · ${esc(new URL(s.url).hostname.replace(/^www\./, ""))}${icon("external")}</a>`).join("")}<a href="${esc(b.imageCredit)}" target="_blank" rel="noopener noreferrer">${state.lang === "ru" ? "Источник фотографии" : "Image source"}${icon("external")}</a></div><p class="detail-legal">${t("marketNote")}</p></section></div></div>`;
  updateFavoriteUI();
}
function showModal() {
  if (!$("detail-dialog").open) {
    returnFocus = document.activeElement;
    $("detail-dialog").showModal();
    document.body.style.overflow = "hidden";
  }
  $("detail-content").scrollTop = 0;
  $("close-dialog").focus({ preventScroll: true });
}
function openBeer(id, push = true) {
  const b = beers.find((b) => b.id === id);
  if (!b) return;
  isAbout = false;
  selectedId = id;
  renderDetail(b);
  if (push) syncUrl(true);
  document.title = `${local(b.name)} — ${t("brandName")}`;
  showModal();
}
function closeDialog(sync = true) {
  selectedId = null;
  isAbout = false;
  if (sync) syncUrl();
  $("dialog-feedback").hidden = true;
  if ($("detail-dialog").open) $("detail-dialog").close();
  document.body.style.overflow = "";
  document.title = t("title");
  if (returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
  else $("beer-search").focus({ preventScroll: true });
}
function renderAbout() {
  $("dialog-eyebrow").textContent = t("about");
  $("detail-content").innerHTML =
    `<div class="about-content"><h2 id="detail-title">${t("aboutTitle")}</h2><p>${t("aboutIntro")}</p>${["Data", "Taste", "Favorites", "Images"].map((k) => `<h3>${t("about" + k + "Title")}</h3><p>${t("about" + k)}</p>`).join("")}<p>${t("footerNote")}</p></div>`;
}
function openAbout() {
  isAbout = true;
  selectedId = null;
  renderAbout();
  showModal();
}
async function loadCatalog() {
  loadRequest?.abort();
  loadRequest = new AbortController();
  const current = loadRequest;
  loadFailed = false;
  renderGrid();
  const timeout = setTimeout(() => current.abort(), 15000);
  try {
    const response = await fetch("./beers.json", { signal: current.signal });
    if (!response.ok) throw new Error("Catalog unavailable");
    const data = await response.json();
    if (!Array.isArray(data) || data.length === 0)
      throw new Error("Empty catalog");
    if (loadRequest !== current) return;
    beers = data;
    renderChrome();
    renderGrid();
    const initialId = new URLSearchParams(location.search).get("beer");
    if (initialId) openBeer(initialId, false);
  } catch {
    if (loadRequest !== current) return;
    loadFailed = true;
    renderGrid();
  } finally {
    clearTimeout(timeout);
  }
}
document.addEventListener("click", async (event) => {
  const locale = event.target.closest("[data-locale]");
  if (locale) {
    if (state.lang === locale.dataset.locale) return;
    state.lang = locale.dataset.locale;
    syncUrl();
    renderChrome();
    renderGrid();
    if (selectedId) renderDetail(beers.find((b) => b.id === selectedId));
    else if (isAbout) renderAbout();
    return;
  }
  const favorite = event.target.closest("[data-favorite]");
  if (favorite) {
    toggleFavorite(favorite.dataset.favorite);
    return;
  }
  const beer = event.target.closest("[data-beer]");
  if (beer) {
    openBeer(beer.dataset.beer);
    return;
  }
  const origin = event.target.closest("[data-origin]");
  if (origin) {
    updateFilters({ origin: origin.dataset.origin, country: "all" });
    return;
  }
  const style = event.target.closest("[data-style]");
  if (style) {
    updateFilters({ style: style.dataset.style });
    document
      .querySelector(`[data-style="${state.style}"]`)
      ?.focus({ preventScroll: true });
    return;
  }
  const guide = event.target.closest("[data-guide-style]");
  if (guide) {
    updateFilters({
      style: guide.dataset.guideStyle,
      favorites: false,
      origin: "all",
      country: "all",
      q: "",
      strength: "all",
    });
    $("catalog").scrollIntoView();
    return;
  }
  if (event.target.closest("[data-reset]")) {
    updateFilters({ ...defaults, lang: state.lang });
    $("beer-search").focus({ preventScroll: true });
    return;
  }
  if (event.target.closest("[data-retry]")) {
    loadCatalog();
    return;
  }
  if (event.target.closest("[data-about]")) {
    openAbout();
    return;
  }
  if (event.target.closest("[data-share]")) {
    try {
      await navigator.clipboard.writeText(location.origin + url());
      notify("copied");
    } catch {
      notify("copyFailed");
    }
  }
});
for (const id of ["favorites-top", "favorites-filter"])
  $(id).addEventListener("click", () => {
    updateFilters({ favorites: !state.favorites });
    if (id === "favorites-top") $("catalog").scrollIntoView();
  });
let composing = false;
$("beer-search").addEventListener("compositionstart", () => (composing = true));
$("beer-search").addEventListener("compositionend", () => {
  composing = false;
  search();
});
function search() {
  state.q = $("beer-search").value;
  state.limit = 20;
  syncUrl();
  $("clear-search").hidden = !state.q;
  renderGrid();
}
$("beer-search").addEventListener("input", () => {
  if (!composing) search();
});
$("beer-search").addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.isComposing) search();
});
$("clear-search").addEventListener("click", () => {
  $("beer-search").value = "";
  search();
  $("beer-search").focus();
});
for (const [id, key] of [
  ["country-select", "country"],
  ["strength-select", "strength"],
  ["sort-select", "sort"],
])
  $(id).addEventListener("change", () => updateFilters({ [key]: $(id).value }));
$("reset-filters").addEventListener("click", () =>
  updateFilters({ ...defaults, lang: state.lang, favorites: state.favorites }),
);
$("load-more").addEventListener("click", () => {
  const current = state.limit;
  state.limit += 20;
  syncUrl();
  renderGrid();
  const next = $("beer-grid").querySelectorAll("[data-beer]")[current];
  next?.focus({ preventScroll: true });
});
$("about-button").addEventListener("click", openAbout);
$("close-dialog").addEventListener("click", () => closeDialog());
$("detail-dialog").addEventListener("cancel", (event) => {
  event.preventDefault();
  closeDialog();
});
$("detail-dialog").addEventListener("click", (event) => {
  if (event.target === $("detail-dialog")) {
    const box = $("detail-dialog").getBoundingClientRect();
    if (
      event.clientX < box.left ||
      event.clientX > box.right ||
      event.clientY < box.top ||
      event.clientY > box.bottom
    )
      closeDialog();
  }
});
window.addEventListener("popstate", () => {
  state = parseState(location.search);
  renderChrome();
  renderGrid();
  const id = new URLSearchParams(location.search).get("beer");
  if (id && beers.some((b) => b.id === id)) openBeer(id, false);
  else if ($("detail-dialog").open) closeDialog(false);
});
window.addEventListener("storage", (event) => {
  if (event.key === "malt-favorites") {
    try {
      const next = JSON.parse(event.newValue || "[]");
      if (Array.isArray(next)) {
        favorites = new Set(next);
        state.favorites ? renderGrid() : updateFavoriteUI();
        updateFavoriteUI();
      }
    } catch {}
  }
});
document.addEventListener(
  "error",
  (event) => {
    const image = event.target;
    if (image.tagName === "IMG" && image.closest(".card-stage,.detail-stage")) {
      image.outerHTML = `<span class="photo-fallback">${icon("glass")}<span>${t("noPhoto")}</span></span>`;
    }
  },
  true,
);
$("motion-toggle").addEventListener("click", () => {
  motionPaused = topography.toggle();
  try {
    localStorage.setItem("malt-motion-paused", motionPaused ? "1" : "0");
  } catch {}
  renderMotion();
});
window
  .matchMedia?.("(prefers-reduced-motion: reduce)")
  .addEventListener?.("change", renderMotion);
document.addEventListener("visibilitychange", renderMotion);
window.addEventListener("pagehide", () => topography.setPaused(true));
window.addEventListener("pageshow", () => topography.setPaused(motionPaused));
renderChrome();
renderGrid();
loadCatalog();
