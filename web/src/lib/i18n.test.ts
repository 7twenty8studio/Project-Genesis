import { test } from "node:test";
import assert from "node:assert/strict";
// @ts-expect-error: a plain .mjs script shared with the command line.
import { strings } from "../../scripts/strings.mjs";
import { formatDay, langFromHeader, translator } from "./i18n.ts";
import { messages } from "./messages.ts";

const placeholders = (s: string) => [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort();

test("every string shown has Spanish and Portuguese with the same placeholders", () => {
  const shown: string[] = strings();
  const missing = shown.filter((en) => !messages[en]?.es || !messages[en]?.pt);
  assert.deepEqual(missing, [], "add these to messages.ts");
  for (const en of shown) {
    for (const lang of ["es", "pt"] as const) {
      assert.deepEqual(placeholders(messages[en][lang]), placeholders(en), `${lang}: ${en}`);
    }
  }
  const unused = Object.keys(messages).filter((en) => !shown.includes(en));
  assert.deepEqual(unused, [], "no longer used: remove from messages.ts");
});

test("the browser's language picks one of the three, else English", () => {
  assert.equal(langFromHeader("pt-PT,pt;q=0.9,en;q=0.8"), "pt");
  assert.equal(langFromHeader("fr-FR,es;q=0.5"), "es");
  assert.equal(langFromHeader("de"), "en");
  assert.equal(langFromHeader(null), "en");
});

test("translation fills placeholders and dates read naturally", () => {
  assert.equal(translator("es")("Series: {name}", { name: "Gracia" }), "Serie: Gracia");
  assert.equal(translator("en")("Opens {passage}", { passage: "John 3:16" }), "Opens John 3:16");
  assert.equal(formatDay("2026-11-22", "en"), "Sunday, November 22, 2026");
  assert.equal(formatDay("2026-11-22", "pt"), "domingo, 22 de novembro de 2026");
});
