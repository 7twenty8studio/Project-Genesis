import { test } from "node:test";
import assert from "node:assert/strict";
import { blocksFromLines, linesFromText, scriptureLine } from "./lines.ts";

const en = { language: "en" } as const;

test("pasted Markdown keeps every line and its kind", () => {
  const lines = linesFromText("# Rest for the weary\n\nCome to me.\nAll of you.\n\n- Tired\n- Burdened\n1. Come\n2) Learn\n\n> Take my yoke\n> upon you\n\nAmen");
  assert.deepEqual(lines, [
    { text: "Rest for the weary", style: "h1" },
    { text: "Come to me.\nAll of you.", style: "p" },
    { text: "Tired", style: "bullet" },
    { text: "Burdened", style: "bullet" },
    { text: "Come", style: "number" },
    { text: "Learn", style: "number" },
    { text: "Take my yoke\nupon you", style: "quote" },
    { text: "Amen", style: "p" },
  ]);
  const blocks = blocksFromLines(lines, en);
  assert.deepEqual(blocks.map((b) => b.kind), ["heading", "paragraph", "list", "list", "quote", "paragraph"]);
});

test("a reference on its own line becomes Scripture, kept as written", () => {
  const ref = scriptureLine("Matthew 11:28-30 (NIV) “Come to me, all you who are weary”", en);
  assert.equal(ref?.raw, "Matthew 11:28-30");
  assert.equal(ref?.label, "NIV");
  assert.equal(ref?.quote, "“Come to me, all you who are weary”");
  assert.equal(ref?.start, 40011028);
  assert.equal(ref?.end, 40011030);
  assert.equal(scriptureLine("Juan 3:16 – RVR1960", { language: "es" })?.label, "RVR1960");
  assert.equal(scriptureLine("Romans 8", en)?.end, 45008039);
});

test("a sentence that mentions a verse stays a paragraph", () => {
  assert.equal(scriptureLine("John 3:16 is the best-known verse in the Bible.", en), null);
  assert.equal(scriptureLine("Grace is enough", en), null);
  const [block] = blocksFromLines([{ text: "In John 3:16 we read of love.", style: "p" }], en);
  assert.equal(block.kind, "paragraph");
});

test("Portuguese abbreviations win in a Portuguese outline", () => {
  assert.equal(scriptureLine("Jo 3:16", { language: "pt" })?.start, 43003016);
  assert.equal(scriptureLine("Mc 1:1", { language: "pt" })?.start, 41001001);
});
