export const countries = {
  RU: { ru: "Россия", en: "Russia" },
  DE: { ru: "Германия", en: "Germany" },
  BE: { ru: "Бельгия", en: "Belgium" },
  CZ: { ru: "Чехия", en: "Czechia" },
  IE: { ru: "Ирландия", en: "Ireland" },
  GB: { ru: "Великобритания", en: "United Kingdom" },
  US: { ru: "США", en: "United States" },
  MX: { ru: "Мексика", en: "Mexico" },
  JP: { ru: "Япония", en: "Japan" },
  FR: { ru: "Франция", en: "France" },
  NL: { ru: "Нидерланды", en: "Netherlands" },
  IT: { ru: "Италия", en: "Italy" },
  ES: { ru: "Испания", en: "Spain" },
  PT: { ru: "Португалия", en: "Portugal" },
  AT: { ru: "Австрия", en: "Austria" },
  IS: { ru: "Исландия", en: "Iceland" },
  DK: { ru: "Дания", en: "Denmark" },
  CN: { ru: "Китай", en: "China" },
  TH: { ru: "Таиланд", en: "Thailand" },
  PL: { ru: "Польша", en: "Poland" },
  LT: { ru: "Литва", en: "Lithuania" },
  BY: { ru: "Беларусь", en: "Belarus" },
};
export const styles = {
  all: { ru: "Все стили", en: "All styles", icon: "layers" },
  lager: { ru: "Лагер", en: "Lager", icon: "glass" },
  wheat: { ru: "Пшеничное", en: "Wheat", icon: "wheat" },
  ipa: { ru: "IPA", en: "IPA", icon: "hop" },
  stout: { ru: "Стаут и портер", en: "Stout & porter", icon: "glass" },
  ale: { ru: "Эль", en: "Ale", icon: "glass" },
  fruit: { ru: "Фруктовое", en: "Fruit beer", icon: "fruit" },
  nonalcoholic: { ru: "Безалкогольное", en: "Alcohol-free", icon: "zero" },
};
export function flag(code) {
  return [...code]
    .map((c) => String.fromCodePoint(c.charCodeAt(0) + 127397))
    .join("");
}
export function formatAbv(n, lang) {
  return (
    new Intl.NumberFormat(lang === "ru" ? "ru-RU" : "en-GB", {
      maximumFractionDigits: 1,
    }).format(n) + "%"
  );
}
export const defaults = {
  q: "",
  origin: "all",
  style: "all",
  country: "all",
  strength: "all",
  sort: "collection",
  favorites: false,
  lang: "ru",
  limit: 20,
};
export function parseState(search) {
  const p = new URLSearchParams(search);
  return {
    ...defaults,
    q: p.get("q") || "",
    origin: ["all", "russia", "world"].includes(p.get("origin"))
      ? p.get("origin")
      : "all",
    style: Object.hasOwn(styles, p.get("style")) ? p.get("style") : "all",
    country: Object.hasOwn(countries, p.get("country"))
      ? p.get("country")
      : "all",
    strength: ["light", "medium", "strong"].includes(p.get("strength"))
      ? p.get("strength")
      : "all",
    sort: ["name", "abv-up", "abv-down"].includes(p.get("sort"))
      ? p.get("sort")
      : "collection",
    favorites: p.get("favorites") === "1",
    lang: p.get("lang") === "en" ? "en" : "ru",
    limit: Math.max(20, Math.min(200, Number(p.get("limit")) || 20)),
  };
}
export function stateParams(state, beerId) {
  const p = new URLSearchParams();
  for (const k of [
    "q",
    "origin",
    "style",
    "country",
    "strength",
    "sort",
    "lang",
  ])
    if (state[k] && state[k] !== defaults[k]) p.set(k, state[k]);
  if (state.favorites) p.set("favorites", "1");
  if (state.limit !== 20) p.set("limit", String(state.limit));
  if (beerId) p.set("beer", beerId);
  return p;
}
function normalize(str) {
  return str
    .toLocaleLowerCase()
    .replaceAll("ё", "е")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}
export function filterBeers(beers, state, favorites = new Set()) {
  const terms = normalize(state.q.trim()).split(/\s+/).filter(Boolean);
  let result = beers.filter((b) => {
    if (state.origin === "russia" && b.country !== "RU") return false;
    if (state.origin === "world" && b.country === "RU") return false;
    if (state.style !== "all" && b.style !== state.style) return false;
    if (state.country !== "all" && b.country !== state.country) return false;
    if (state.favorites && !favorites.has(b.id)) return false;
    if (state.strength === "light" && b.abv > 4.5) return false;
    if (state.strength === "medium" && (b.abv <= 4.5 || b.abv > 6))
      return false;
    if (state.strength === "strong" && b.abv <= 6) return false;
    if (!terms.length) return true;
    const hay = normalize(
      [
        b.name.ru,
        b.name.en,
        b.brewery.ru,
        b.brewery.en,
        b.city.ru,
        b.city.en,
        b.styleName.ru,
        b.styleName.en,
        b.aroma.ru,
        b.aroma.en,
        b.taste.ru,
        b.taste.en,
        countries[b.country]?.ru,
        countries[b.country]?.en,
        ...b.ingredients.ru,
        ...b.ingredients.en,
      ].join(" "),
    );
    return terms.every((t) => hay.includes(t));
  });
  if (state.sort === "name")
    result.sort((a, b) =>
      a.name[state.lang].localeCompare(b.name[state.lang], state.lang),
    );
  if (state.sort === "abv-up") result.sort((a, b) => a.abv - b.abv);
  if (state.sort === "abv-down") result.sort((a, b) => b.abv - a.abv);
  return result;
}
export function escapeHtml(s) {
  return String(s ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
}
