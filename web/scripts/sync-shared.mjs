// Copies the reference parser and its book data from supabase/functions/_shared,
// so the web reads references exactly as the server tests and the app do.
// `npm run sync` after BibleBook.swift changes (export_reference_books.py first);
// src/lib/shared.test.ts fails while the copies differ.
import { copyFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const from = join(here, "../../supabase/functions/_shared");
const to = join(here, "../src/lib/shared");
for (const name of ["references.ts", "bibleBooks.json"]) copyFileSync(join(from, name), join(to, name));
console.log("copied references.ts and bibleBooks.json");
