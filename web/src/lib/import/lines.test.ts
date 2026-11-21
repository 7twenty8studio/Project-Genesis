import { test } from "node:test";
import assert from "node:assert/strict";
import { blocksFromLines, linesFromText, mayQuoteScripture, scriptureLine } from "./lines.ts";
import { missingRuns, outlineWords, sourceWords } from "./completeness.ts";
import { appendReview, reviewDone, reviewItems, stillOpen } from "./review.ts";

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

// The owner's review (21 Nov 2026): a labelled NIV quotation in a Markdown
// quote was kept as a plain quote and its words published.
const quoteOf = (markdown: string) => blocksFromLines(linesFromText(markdown), en);

test("a quote that is a labelled verse goes through the Scripture rules", () => {
  for (const markdown of [
    "> John 3:16 (NIV) For God so loved the world",
    "> John 3:16 NIV For God so loved the world",
    "> John 3:16 (NIV)\n> For God so loved the world",
    "> John 3:16\n> For God so loved the world",
    "> “For God so loved the world” (John 3:16, NIV)",
    "> For God so loved the world\n> — John 3:16 NIV",
    "> For God so loved the world (John 3:16 NIV)",
  ]) {
    const [block, ...rest] = quoteOf(markdown);
    assert.equal(rest.length, 0, markdown);
    assert.equal(block.kind, "scripture", markdown);
    if (block.kind !== "scripture") continue;
    assert.equal(block.ref.start, 43003016, markdown);
    assert.ok(block.ref.quote?.includes("For God so loved the world"), markdown);
  }
  const [labelled] = quoteOf("> John 3:16 (NIV) For God so loved the world");
  assert.equal(labelled.kind === "scripture" && labelled.ref.label, "NIV");
});

test("lists and headings that quote a verse become Scripture; bare references stay", () => {
  const blocks = quoteOf("- Rest\n- John 3:16 (NIV) “For God so loved the world”\n- Trust\n\n## “The Lord is my shepherd” — Psalm 23:1 NIV\n\n## Psalm 23\n\n- Romans 8:28");
  assert.deepEqual(blocks.map((b) => b.kind), ["list", "scripture", "list", "scripture", "heading", "list"]);
  assert.equal(blocks[1].kind === "scripture" && blocks[1].ref.label, "NIV");
  assert.equal(blocks[3].kind === "scripture" && blocks[3].ref.start, 19023001);
  // Every word is still there, whichever side of the reference the quotation was on.
  const source = "- Rest\n- John 3:16 (NIV) “For God so loved the world”\n- Trust\n\n## “The Lord is my shepherd” — Psalm 23:1 NIV\n\n## Psalm 23\n\n- Romans 8:28";
  assert.deepEqual(missingRuns(sourceWords(source), outlineWords(blocks)), []);
});

test("a pastor's own quote stays a quote", () => {
  for (const markdown of ["> Grace is not a reward.", "> “Faith is taking the first step.” — Martin Luther King Jr."]) {
    assert.deepEqual(quoteOf(markdown).map((b) => b.kind), ["quote"], markdown);
  }
});

test("anything that may quote Scripture but isn't clearly a verse goes on the review list", () => {
  const may = (block: Parameters<typeof mayQuoteScripture>[0]) => mayQuoteScripture(block, en);
  assert.ok(may({ id: "a", kind: "quote", text: "As Jesus said in John 3:16, God so loved the world." }));
  assert.ok(may({ id: "b", kind: "quote", text: "For God so loved the world. (NIV)" }));
  assert.ok(may({ id: "c", kind: "paragraph", text: "Jesus said “I am the good shepherd” in John 10:11." }));
  assert.ok(may({ id: "d", kind: "list", items: ["Rest", "In John 10:11 (ESV) he says he is the good shepherd"], ordered: false }));
  assert.ok(may({ id: "e", kind: "heading", text: "The NIV of John 3:16", level: 2 }));
  assert.ok(!may({ id: "f", kind: "paragraph", text: "In John 3:16 we read of love." }));
  assert.ok(!may({ id: "g", kind: "quote", text: "Grace is not a reward." }));
  assert.ok(!may({ id: "h", kind: "paragraph", text: "“Faith is taking the first step,” he said." }));
  assert.ok(!may({ id: "i", kind: "scripture", ref: { raw: "John 3:16", start: 43003016, end: 43003016, status: "verified", label: "NIV", quote: "For God" } }));
});

test("a possible quotation is a review item until it is made Scripture or answered", () => {
  const source = "> As John 10:11 (ESV) puts it, he is the good shepherd\n\nAmen.";
  const blocks = blocksFromLines(linesFromText(source), en);
  const items = reviewItems(source, blocks, [], en).filter((i) => i.kind === "quotation");
  assert.equal(items.length, 1);
  assert.equal(stillOpen(items, blocks).length, 1);
  assert.ok(!reviewDone(stillOpen(items, blocks), {}));
  assert.ok(reviewDone(stillOpen(items, blocks), { [items[0].key]: "kept" }));
  const fixed = blocks.map((b) => (b.kind === "quote" ? { id: b.id, kind: "scripture" as const, ref: { raw: "John 10:11", start: 43010011, end: 43010011, status: "verified" as const, label: "ESV", quote: null } } : b));
  assert.equal(stillOpen(items, fixed).length, 0);
});

// The owner's review (21 Nov 2026): appending an import replaced the earlier checklist.
test("adding an import keeps the earlier review items and answers", () => {
  const first = reviewItems("Grace abounds.", [], [], en);
  const earlier = { items: [...first, { key: "quotation:q", kind: "quotation" as const, blockId: "q", text: "x" }], decisions: { "note:comments": "kept" as const } };
  const second = reviewItems("More words.", [], [], en);
  const merged = appendReview(earlier, second, "i2");
  assert.ok(merged);
  assert.deepEqual(merged.items.slice(0, earlier.items.length), earlier.items);
  assert.deepEqual(merged.decisions, earlier.decisions);
  assert.ok(merged.items.slice(earlier.items.length).every((i) => i.key.startsWith("i2:")));
  // An earlier answer never covers a new item with the same name.
  assert.ok(merged.items.some((i) => i.key === "i2:note:comments") && merged.decisions["i2:note:comments"] === undefined);
  assert.equal(appendReview(null, [], "i3"), null);
});
