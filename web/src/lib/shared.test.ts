import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// The web reads references exactly as the server tests and the app do: `npm run sync` refreshes the copies.
test("the reference parser and book data match supabase/functions/_shared", () => {
  for (const name of ["references.ts", "bibleBooks.json"]) {
    const here = readFileSync(join(import.meta.dirname, "shared", name), "utf8");
    const there = readFileSync(join(import.meta.dirname, "../../../supabase/functions/_shared", name), "utf8");
    assert.equal(here, there, `${name} is stale: npm run sync`);
  }
});
