// The visitor's own choices on the web, kept in two small cookies (a year,
// readable by the page so a change applies at once): the look and the
// language of Versely's own words. Neither changes a sermon's language or
// the Bible a passage is read in.
import { isLang, type Lang } from "./i18n.ts";

export const THEME_COOKIE = "vs_theme";
export const LANG_COOKIE = "vs_lang";
export const PREF_MAX_AGE_S = 60 * 60 * 24 * 365;

/** Cream is Versely's own look and the default; "system" follows the device's light or dark setting. */
export const THEMES = ["cream", "daylight", "dark", "system"] as const;
export type Theme = (typeof THEMES)[number];
export const DEFAULT_THEME: Theme = "cream";

export function themeFrom(value: string | undefined | null): Theme {
  return (THEMES as readonly string[]).includes(value ?? "") ? (value as Theme) : DEFAULT_THEME;
}

/** The chosen language, or null to follow the browser. */
export function chosenLang(value: string | undefined | null): Lang | null {
  return isLang(value) ? value : null;
}

/** The cookie a choice is saved in (Path=/, a year, Lax). */
export function prefCookie(name: string, value: string): string {
  return `${name}=${encodeURIComponent(value)}; Path=/; Max-Age=${PREF_MAX_AGE_S}; SameSite=Lax`;
}

/** Saves and shows a look at once (browser only). */
export function applyTheme(value: Theme): void {
  document.cookie = prefCookie(THEME_COOKIE, value);
  document.documentElement.dataset.theme = value;
}

/** Saves a language and marks the page with it (browser only); the caller refreshes the page's words. */
export function applyLang(value: Lang, htmlLang: string): void {
  document.cookie = prefCookie(LANG_COOKIE, value);
  document.documentElement.lang = htmlLang;
}
