import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  countries,
  styles,
  defaults,
  parseState,
  stateParams,
  filterBeers,
  formatAbv,
  escapeHtml,
} from "../dist/catalog.mjs";
import { copy } from "../dist/content.mjs";
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const beers = JSON.parse(
  fs.readFileSync(path.join(root, "dist/beers.json"), "utf8"),
);
let checks = 0;
function check(condition, message) {
  assert.ok(condition, message);
  checks++;
}
check(beers.length >= 96, "Expanded collection contains at least 96 beers");
check(new Set(beers.map((b) => b.id)).size === beers.length, "Unique beer IDs");
check(
  beers.filter((b) => b.country === "RU").length >= 48,
  "At least 48 Russian beers",
);
for (const b of beers) {
  for (const field of [
    "name",
    "brewery",
    "city",
    "styleName",
    "description",
    "aroma",
    "taste",
    "serve",
    "ingredients",
    "food",
  ])
    for (const lang of ["ru", "en"])
      check(!!b[field]?.[lang]?.length, `${b.id} ${field} ${lang}`);
  check(b.country in countries && b.style in styles, `${b.id} valid filters`);
  check(
    typeof b.abv === "number" && b.abv >= 0 && b.abv <= 20,
    `${b.id} plausible ABV`,
  );
  check(
    b.sources.length && b.sources.every((s) => s.url.startsWith("https://")),
    `${b.id} manufacturer links`,
  );
  check(
    fs.existsSync(path.join(root, "dist", b.image)),
    `${b.id} image exists`,
  );
  check(
    typeof b.ingredientsVerified === "boolean",
    `${b.id} composition status`,
  );
}
check(
  JSON.stringify(Object.keys(copy.ru).sort()) ===
    JSON.stringify(Object.keys(copy.en).sort()),
  "All UI keys translated",
);
for (const lang of ["ru", "en"])
  for (const [key, val] of Object.entries(copy[lang]))
    check(typeof val === "string" && val.length, `${lang} ${key} non-empty`);
check(
  filterBeers(beers, { ...defaults, origin: "russia" }).length ===
    beers.filter((b) => b.country === "RU").length,
  "Russia origin filter",
);
check(
  filterBeers(beers, { ...defaults, origin: "world" }).length ===
    beers.filter((b) => b.country !== "RU").length,
  "International origin filter",
);
check(
  filterBeers(beers, { ...defaults, q: "zhiguli" }).some(
    (b) => b.id === "ru-zhiguli",
  ),
  "Cross-language search",
);
check(
  filterBeers(beers, { ...defaults, q: "тРеХгОрНоЕ" }).some(
    (b) => b.id === "ru-trekhgornoe-ale",
  ),
  "Case and ё insensitive search",
);
check(
  filterBeers(beers, { ...defaults, q: "no-such-beer-789" }).length === 0,
  "No-results state",
);
check(
  filterBeers(
    beers,
    { ...defaults, favorites: true },
    new Set(["world-guinness"]),
  )
    .map((b) => b.id)
    .join() === "world-guinness",
  "Favorite filtering",
);
for (const strength of ["light", "medium", "strong"]) {
  const result = filterBeers(beers, { ...defaults, strength });
  check(result.length > 0, `${strength} has matches`);
  check(
    result.every((b) =>
      strength === "light"
        ? b.abv <= 4.5
        : strength === "medium"
          ? b.abv > 4.5 && b.abv <= 6
          : b.abv > 6,
    ),
    `${strength} boundaries`,
  );
}
const sorted = filterBeers(beers, { ...defaults, sort: "abv-down" });
check(
  sorted.every((b, i) => !i || sorted[i - 1].abv >= b.abv),
  "ABV sorting",
);
const state = {
  ...defaults,
  q: "Жигули wheat",
  style: "wheat",
  origin: "russia",
  lang: "en",
  favorites: true,
  limit: 40,
};
check(
  JSON.stringify(parseState("?" + stateParams(state).toString())) ===
    JSON.stringify(state),
  "URL state round-trip",
);
check(
  parseState("?style=bad&country=XX&sort=bad&origin=bad&limit=-3").style ===
    "all",
  "Invalid filters recover",
);
check(
  formatAbv(4.9, "ru") === "4,9%" && formatAbv(4.9, "en") === "4.9%",
  "Localized ABV",
);
check(escapeHtml("<script>") === "&lt;script&gt;", "Escaped external content");
const html = fs.readFileSync(path.join(root, "dist/index.html"), "utf8");
check(
  !/<h[1-6][^>]*>[^<]*[.]\s*<\//.test(html),
  "No trailing periods in static headings",
);
for (const match of html.matchAll(/(?:href|src)="(\/(?!\/)[^"?#]+)"/g))
  check(
    fs.existsSync(path.join(root, "dist", match[1])),
    `Static asset ${match[1]}`,
  );
console.log(
  `Passed ${checks} checks: data, translations, images, filters, search, URL state, markup`,
);
