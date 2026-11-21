// The web's own words in English, Spanish and Brazilian Portuguese (the
// app's three languages). English is the key; messages.ts holds the rest,
// and i18n.test.ts fails if any t("…") in the code lacks a translation or
// a {placeholder}. Never used for Scripture or anything a church wrote.
import { messages } from "./messages.ts";

export type Lang = "en" | "es" | "pt";

export function isLang(value: unknown): value is Lang {
  return value === "en" || value === "es" || value === "pt";
}

/** The first of en/es/pt the browser asks for (Accept-Language), else English. */
export function langFromHeader(header: string | null | undefined): Lang {
  const wanted = (header ?? "")
    .split(",")
    .map((part) => {
      const [tag, q] = part.trim().split(";q=");
      return { tag: tag.toLowerCase(), q: q === undefined ? 1 : Number(q) };
    })
    .filter((x) => x.tag && x.q > 0)
    .sort((a, b) => b.q - a.q);
  for (const { tag } of wanted) {
    const base = tag.split("-")[0];
    if (isLang(base)) return base;
  }
  return "en";
}

export type Translate = (en: string, vars?: Record<string, string | number>) => string;

export function translator(lang: Lang): Translate {
  return (en, vars) => {
    const text = lang === "en" ? en : (messages[en]?.[lang] ?? en);
    return vars ? text.replace(/\{(\w+)\}/g, (m, k: string) => (k in vars ? String(vars[k]) : m)) : text;
  };
}

/** A date such as "Sunday, November 22, 2026" in the page's language (dates are plain days). */
export function formatDay(day: string, lang: Lang): string {
  const [y, m, d] = day.split("-").map(Number);
  if (!y || !m || !d) return day;
  const locale = lang === "es" ? "es" : lang === "pt" ? "pt-BR" : "en-US";
  return new Intl.DateTimeFormat(locale, { weekday: "long", year: "numeric", month: "long", day: "numeric", timeZone: "UTC" }).format(
    new Date(Date.UTC(y, m - 1, d)),
  );
}
