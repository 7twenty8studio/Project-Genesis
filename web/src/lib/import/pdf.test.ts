import { test } from "node:test";
import assert from "node:assert/strict";
import { importPdfPages, linesFromPdf, pageLines, type PdfText } from "./pdf.ts";
import { ScannedPDF } from "./result.ts";
import { missingRuns, outlineWords, sourceWords } from "./completeness.ts";

const item = (str: string, x: number, y: number, size = 12, width = str.length * size * 0.5): PdfText => ({ str, transform: [size, 0, 0, size, x, y], height: size, width });

test("positioned text becomes headings, paragraphs and list items", () => {
  const page = pageLines(
    [
      item("Living Water", 72, 750, 24),
      item("Jesus met", 72, 700),
      item("a woman.", 130, 700),
      item("She came at noon.", 72, 686),
      item("• Thirst", 72, 640),
      item("that lasts", 90, 626),
      item("1. Ask", 72, 600),
    ],
    1,
  );
  assert.equal(page[1].text, "Jesus met a woman.");
  assert.deepEqual(linesFromPdf(page), [
    { text: "Living Water", style: "h1" },
    { text: "Jesus met a woman. She came at noon.", style: "p" },
    { text: "Thirst that lasts", style: "bullet" },
    { text: "Ask", style: "number" },
  ]);
});

test("a new page starts a new paragraph", () => {
  const lines = [...pageLines([item("End of page one", 72, 100)], 1), ...pageLines([item("Start of two", 72, 750)], 2)];
  assert.deepEqual(linesFromPdf(lines).map((l) => l.text), ["End of page one", "Start of two"]);
});

test("a scanned PDF asks for the text instead of importing nothing", () => {
  // A scan has at most a page number or a stamp the scanner recognized.
  const pages = [[item("1", 300, 40)], [item("2", 300, 40), item("CONFIDENTIAL", 72, 760)]];
  assert.throws(() => importPdfPages(pages, { language: "en" }), ScannedPDF);
  assert.throws(() => importPdfPages([], { language: "en" }), ScannedPDF);
});

test("a Portuguese text PDF keeps every word, accents and references as written", () => {
  const pages = [[
    item("A Água Viva", 72, 760, 24),
    item("Jesus encontrou uma mulher samaritana à beira do poço, ao meio-dia.", 72, 720),
    item("Ela não esperava ser vista, mas ele já a conhecia.", 72, 706),
    item("João 4:13-14", 72, 670),
    item("• Quem beber desta água tornará a ter sede", 72, 640),
    item("• Sede de quê? De perdão, de propósito e de comunhão", 72, 620),
    item("Oração: Senhor, dá-nos dessa água.", 72, 590),
  ]];
  const result = importPdfPages(pages, { language: "pt" });
  assert.deepEqual(missingRuns(sourceWords(result.source), outlineWords(result.blocks)), []);
  const scripture = result.blocks.find((b) => b.kind === "scripture");
  assert.ok(scripture && scripture.kind === "scripture");
  assert.equal(scripture.ref.raw, "João 4:13-14");
  assert.equal(scripture.ref.start, 43004013);
  assert.equal(scripture.ref.end, 43004014);
  assert.equal(result.blocks[0].kind, "heading");
});

test("a Google Docs PDF: ● bullets with a hidden space, and headings that wrap", () => {
  const page = pageLines(
    [
      item("POINT 1 — UNITY IS MORE THAN JUST BEING", 72, 750, 18),
      item("TOGETHER", 72, 728, 18),
      item("1 Corinthians 12:25–27", 72, 700),
      item("Key Notes:", 72, 670),
      item("●\u200B Physical presence does not equal spiritual unity.", 90, 650),
      item("●\u200B Attending the same church doesn't automatically", 90, 636),
      item("create unity.", 108, 622),
      item("POINT 2 — GRACE", 72, 580, 18),
      item("Colossians 3:13", 72, 552),
    ],
    1,
  );
  assert.deepEqual(linesFromPdf(page), [
    { text: "POINT 1 — UNITY IS MORE THAN JUST BEING TOGETHER", style: "h2" },
    { text: "1 Corinthians 12:25–27", style: "p" },
    { text: "Key Notes:", style: "p" },
    { text: "Physical presence does not equal spiritual unity.", style: "bullet" },
    { text: "Attending the same church doesn't automatically create unity.", style: "bullet" },
    { text: "POINT 2 — GRACE", style: "h2" },
    { text: "Colossians 3:13", style: "p" },
  ]);
});
