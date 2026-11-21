import { test } from "node:test";
import assert from "node:assert/strict";
import { linesFromPdf, pageLines, type PdfText } from "./pdf.ts";

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
