import { test } from "node:test";
import assert from "node:assert/strict";
import { docx, hiddenRun, para } from "./fixtures.ts";
import { importDocx, textOfPart, withoutHiddenRuns } from "./docx.ts";
import { linesFromHtml } from "./html.ts";
import { missingRuns, outlineWords, sourceWords } from "./completeness.ts";
import { reviewItems } from "./review.ts";

const en = { language: "en" } as const;

test("a Word sermon keeps its title, headings, quotes and every word", async () => {
  const file = await docx(
    para("The Good Shepherd", "Title") +
      para("I. He leads", "Heading1") +
      para("Psalm 23:1-3 (KJV)") +
      para("The Lord is my shepherd", "Quote") +
      para("We follow &amp; we rest.") +
      `<w:tbl><w:tr><w:tc>${para("Table cell words")}</w:tc></w:tr></w:tbl>`,
  );
  const result = await importDocx(file, en);
  assert.deepEqual(result.blocks.map((b) => b.kind), ["heading", "heading", "scripture", "quote", "paragraph", "paragraph"]);
  assert.equal(result.blocks[0].kind === "heading" && result.blocks[0].level, 1);
  assert.deepEqual(missingRuns(sourceWords(result.source), outlineWords(result.blocks)), []);
  assert.deepEqual(result.notes, [{ kind: "tables", count: 1 }]);
});

test("hidden text, footnotes and comments are reported, never silently dropped", async () => {
  const file = await docx(
    para("Visible words", undefined, hiddenRun("secret aside")) + `<w:p><w:r><w:t>Note here</w:t></w:r><w:r><w:footnoteReference w:id="1"/></w:r></w:p>`,
    {
      footnotes: `<w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote><w:footnote w:id="1">${para("See Calvin.")}</w:footnote>`,
      comments: `<w:comment w:id="0">${para("Check this date")}</w:comment>`,
    },
  );
  const result = await importDocx(file, en);
  const kinds = Object.fromEntries(result.notes.map((n) => [n.kind, n.count]));
  assert.equal(kinds.hidden, 1);
  assert.equal(kinds.footnotes, 1);
  assert.equal(kinds.comments, 1);
  // The footnote's words are in the outline (last); the comment's never are.
  assert.ok(outlineWords(result.blocks).includes("Calvin"));
  assert.ok(!outlineWords(result.blocks).includes("Check"));
  const items = reviewItems(result.source, result.blocks, result.notes);
  assert.ok(!items.some((i) => i.kind === "missing"), JSON.stringify(items));
});

test("words Mammoth can't carry over (a text box) appear in the review list", async () => {
  const textBox = `<w:p><w:r><w:pict><v:shape xmlns:v="urn:schemas-microsoft-com:vml"><v:textbox><w:txbxContent>${para("Boxed words")}</w:txbxContent></v:textbox></v:shape></w:pict></w:r></w:p>`;
  const result = await importDocx(await docx(para("Main text") + textBox), en);
  const missing = reviewItems(result.source, result.blocks, result.notes).filter((i) => i.kind === "missing");
  const inOutline = outlineWords(result.blocks).includes("Boxed");
  // Either Mammoth kept the words or the review list names them: never neither.
  assert.ok(inOutline || missing.some((i) => i.kind === "missing" && i.words.includes("Boxed")));
});

test("the document's own text skips deleted tracked changes and hidden runs", () => {
  const xml = `<w:p><w:r><w:t>Kept</w:t></w:r><w:del><w:r><w:delText>gone</w:delText></w:r></w:del>${hiddenRun("hidden")}<w:r><w:tab/><w:t>a&amp;b</w:t></w:r></w:p>`;
  assert.deepEqual(textOfPart(xml), { text: "Kept a&b", hidden: 1 });
});

test("Mammoth's footnote markers are dropped and the notes come last", () => {
  const html = `<p>Grace<sup><a href="#footnote-1" id="footnote-ref-1">[1]</a></sup> abounds</p><ol><li id="footnote-1"><p>Romans 5:20 <a href="#footnote-ref-1">↑</a></p></li></ol><ul><li>after</li></ul>`;
  const { lines, notes } = linesFromHtml(html);
  assert.deepEqual(lines, [
    { text: "Grace abounds", style: "p" },
    { text: "after", style: "bullet" },
    { text: "Romans 5:20", style: "p" },
  ]);
  assert.equal(notes.footnotes, 1);
});

test("hidden runs are taken out before Mammoth reads the document", () => {
  const xml = `<w:p><w:r><w:t>Shown</w:t></w:r>${hiddenRun("hidden")}<w:r><w:rPr><w:vanish w:val="0"/></w:rPr><w:t>not hidden</w:t></w:r></w:p>`;
  assert.equal(withoutHiddenRuns(xml), `<w:p><w:r><w:t>Shown</w:t></w:r><w:r><w:rPr><w:vanish w:val="0"/></w:rPr><w:t>not hidden</w:t></w:r></w:p>`);
});
