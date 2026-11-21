import { test } from "node:test";
import assert from "node:assert/strict";
import { chosenLang, DEFAULT_THEME, prefCookie, themeFrom } from "./prefs.ts";

test("Cream unless another look was chosen", () => {
  assert.equal(DEFAULT_THEME, "cream");
  assert.equal(themeFrom(undefined), "cream");
  assert.equal(themeFrom("neon"), "cream");
  assert.equal(themeFrom("dark"), "dark");
  assert.equal(themeFrom("system"), "system");
  assert.equal(themeFrom("daylight"), "daylight");
});

test("a chosen language wins; anything else follows the browser", () => {
  assert.equal(chosenLang("es"), "es");
  assert.equal(chosenLang("fr"), null);
  assert.equal(chosenLang(undefined), null);
});

test("choices are kept for a year on the whole site", () => {
  assert.equal(prefCookie("vs_theme", "dark"), "vs_theme=dark; Path=/; Max-Age=31536000; SameSite=Lax");
});
