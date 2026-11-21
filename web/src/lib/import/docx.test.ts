import { test } from "node:test";
import assert from "node:assert/strict";
import { docx, documentXml, hiddenRun, para } from "./fixtures.ts";
import { importDocx, readStyles, textOfPart, withoutHiddenRuns } from "./docx.ts";
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
  const xml = documentXml(`<w:p><w:r><w:t>Kept</w:t></w:r><w:del><w:r><w:delText>gone</w:delText></w:r></w:del>${hiddenRun("hidden")}<w:r><w:tab/><w:t>a&amp;b</w:t></w:r></w:p>`);
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
  const xml = documentXml(`<w:p><w:r><w:t>Shown</w:t></w:r>${hiddenRun("hidden")}<w:r><w:rPr><w:vanish w:val="0"/></w:rPr><w:t>not hidden</w:t></w:r></w:p>`);
  const out = withoutHiddenRuns(xml);
  assert.ok(out.includes("Shown") && out.includes("not hidden") && !out.includes(">hidden<"), out);
});

// Every way Word (or another editor) can write "hidden", including the one
// the owner's review found: <w:vanish /> with a space.
const spellings: [string, string][] = [
  ["an empty element with a space", `<w:r><w:rPr><w:vanish /></w:rPr><w:t>secret</w:t></w:r>`],
  ["an open and close pair", `<w:r><w:rPr><w:vanish></w:vanish></w:rPr><w:t>secret</w:t></w:r>`],
  ['w:val="1"', `<w:r><w:rPr><w:vanish w:val="1"/></w:rPr><w:t>secret</w:t></w:r>`],
  ['w:val="true" after other settings', `<w:r><w:rPr><w:b/><w:i w:val="1"/><w:vanish w:val="true" /><w:sz w:val="24"/></w:rPr><w:t>secret</w:t></w:r>`],
  ["attributes on the run", `<w:r w:rsidR="00AB12" w:rsidRPr="00CD34"><w:rPr><w:vanish/></w:rPr><w:t xml:space="preserve">secret</w:t></w:r>`],
  ["inside a hyperlink", `<w:hyperlink r:id="x" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:r><w:rPr><w:vanish/></w:rPr><w:t>secret</w:t></w:r></w:hyperlink>`],
  ["inside an inserted change", `<w:ins w:id="1" w:author="A"><w:r><w:rPr><w:vanish/></w:rPr><w:t>secret</w:t></w:r></w:ins>`],
  ["across line breaks", `<w:r>\n  <w:rPr>\n    <w:vanish\n    />\n  </w:rPr>\n  <w:t>secret</w:t>\n</w:r>`],
];

for (const [name, run] of spellings) {
  test(`hidden text written as ${name} is never imported`, async () => {
    const result = await importDocx(await docx(`<w:p><w:r><w:t xml:space="preserve">Visible words </w:t></w:r>${run}</w:p>`), en);
    assert.ok(!outlineWords(result.blocks).includes("secret"), JSON.stringify(result.blocks));
    assert.ok(!sourceWords(result.source).includes("secret"));
    assert.deepEqual(result.notes.find((n) => n.kind === "hidden"), { kind: "hidden", count: 1 });
  });
}

test("another namespace prefix is read the same way", () => {
  const xml = `<?xml version="1.0"?><x:document xmlns:x="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><x:body><x:p><x:r><x:t>Shown</x:t></x:r><x:r><x:rPr><x:vanish /></x:rPr><x:t>secret</x:t></x:r></x:p></x:body></x:document>`;
  assert.deepEqual(textOfPart(xml), { text: "Shown", hidden: 1 });
  assert.ok(!withoutHiddenRuns(xml).includes("secret"));
});

const hiddenStyles =
  `<w:style w:type="character" w:styleId="Aside"><w:name w:val="Aside"/><w:rPr><w:vanish/></w:rPr></w:style>` +
  `<w:style w:type="character" w:styleId="QuietAside"><w:name w:val="Quiet Aside"/><w:basedOn w:val="Aside"/></w:style>` +
  `<w:style w:type="character" w:styleId="ShownAside"><w:name w:val="Shown Aside"/><w:basedOn w:val="Aside"/><w:rPr><w:vanish w:val="0"/></w:rPr></w:style>` +
  `<w:style w:type="paragraph" w:styleId="PastorNote"><w:name w:val="Pastor Note"/><w:rPr><w:vanish/></w:rPr></w:style>` +
  `<w:style w:type="paragraph" w:styleId="PastorNote2"><w:name w:val="Pastor Note 2"/><w:basedOn w:val="PastorNote"/></w:style>`;

test("hidden by a character style, or a style it is based on", async () => {
  const result = await importDocx(
    await docx(
      `<w:p><w:r><w:t xml:space="preserve">Open </w:t></w:r><w:r><w:rPr><w:rStyle w:val="Aside"/></w:rPr><w:t>secretone</w:t></w:r></w:p>` +
        `<w:p><w:r><w:rPr><w:rStyle w:val="QuietAside"/></w:rPr><w:t>secrettwo</w:t></w:r><w:r><w:t>after</w:t></w:r></w:p>` +
        `<w:p><w:r><w:rPr><w:rStyle w:val="ShownAside"/></w:rPr><w:t>shownthree</w:t></w:r></w:p>`,
      { styles: hiddenStyles },
    ),
    en,
  );
  const words = outlineWords(result.blocks);
  assert.ok(!words.includes("secretone") && !words.includes("secrettwo"), JSON.stringify(result.blocks));
  assert.ok(words.includes("shownthree") && words.includes("after"));
  assert.deepEqual(result.notes.find((n) => n.kind === "hidden"), { kind: "hidden", count: 2 });
});

test("hidden by a paragraph style, unless the run says otherwise", async () => {
  const result = await importDocx(
    await docx(
      para("Shown paragraph") +
        para("secretpara", "PastorNote") +
        para("secretchild", "PastorNote2") +
        `<w:p><w:pPr><w:pStyle w:val="PastorNote"/></w:pPr><w:r><w:rPr><w:vanish w:val="false"/></w:rPr><w:t>overridden</w:t></w:r></w:p>`,
      { styles: hiddenStyles },
    ),
    en,
  );
  const words = outlineWords(result.blocks);
  assert.ok(!words.includes("secretpara") && !words.includes("secretchild"), JSON.stringify(result.blocks));
  assert.ok(words.includes("overridden") && words.includes("Shown"));
  assert.deepEqual(result.notes.find((n) => n.kind === "hidden"), { kind: "hidden", count: 2 });
});

test("a document whose default hides runs hides them all but those shown on purpose", () => {
  const styles = readStyles(`<?xml version="1.0"?><w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:docDefaults><w:rPrDefault><w:rPr><w:vanish/></w:rPr></w:rPrDefault></w:docDefaults></w:styles>`);
  const xml = documentXml(`<w:p><w:r><w:t>secret</w:t></w:r><w:r><w:rPr><w:vanish w:val="off"/></w:rPr><w:t>Shown</w:t></w:r></w:p>`);
  assert.deepEqual(textOfPart(xml, styles), { text: "Shown", hidden: 1 });
});

test("hidden text in a footnote is left out too", async () => {
  const file = await docx(`<w:p><w:r><w:t>Body</w:t></w:r><w:r><w:footnoteReference w:id="1"/></w:r></w:p>`, {
    footnotes: `<w:footnote w:id="1"><w:p><w:r><w:t xml:space="preserve">Shown note </w:t></w:r><w:r><w:rPr><w:vanish /></w:rPr><w:t>secretnote</w:t></w:r></w:p></w:footnote>`,
  });
  const result = await importDocx(file, en);
  assert.ok(!outlineWords(result.blocks).includes("secretnote"), JSON.stringify(result.blocks));
  assert.ok(outlineWords(result.blocks).includes("note"));
});

test("a bilingual Word sermon keeps both languages word for word and links each reference", async () => {
  const file = await docx(
    para("Gracia sobre gracia / Grace upon Grace", "Title") +
      para("Bienvenidos. Welcome, everyone; hoy leemos juntos.") +
      para("Juan 1:16 (RV1909)") +
      para("John 1:16 (KJV)") +
      para("¿Qué significa «gracia»? What does “grace” mean?") +
      para("Señor, gracias. Lord, thank you.", "Quote"),
  );
  const result = await importDocx(file, { language: "es" });
  assert.deepEqual(missingRuns(sourceWords(result.source), outlineWords(result.blocks)), []);
  const refs = result.blocks.flatMap((b) => (b.kind === "scripture" ? [b.ref] : []));
  assert.deepEqual(refs.map((r) => [r.raw, r.start, r.label]), [
    ["Juan 1:16", 43001016, "RV1909"],
    ["John 1:16", 43001016, "KJV"],
  ]);
});
