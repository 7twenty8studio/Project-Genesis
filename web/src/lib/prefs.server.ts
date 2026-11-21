// The visitor's look and language for this request (server components).
import { cookies, headers } from "next/headers";
import { langFromHeader, type Lang } from "./i18n.ts";
import { chosenLang, LANG_COOKIE, THEME_COOKIE, themeFrom, type Theme } from "./prefs.ts";

/** Versely's language: the one chosen in the menu, else the browser's. */
export async function requestLang(): Promise<Lang> {
  return (await chosenLanguage()) ?? langFromHeader((await headers()).get("accept-language"));
}

/** The language chosen in the menu, or null when the visitor hasn't chosen. */
export async function chosenLanguage(): Promise<Lang | null> {
  return chosenLang((await cookies()).get(LANG_COOKIE)?.value);
}

export async function requestTheme(): Promise<Theme> {
  return themeFrom((await cookies()).get(THEME_COOKIE)?.value);
}
