// Builds small DOCX files for the tests (JSZip), so no binary fixtures live in the repo.
import JSZip from "jszip";

export const W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';

export const para = (text: string, style?: string, extra = "") =>
  `<w:p>${style ? `<w:pPr><w:pStyle w:val="${style}"/></w:pPr>` : ""}<w:r><w:t xml:space="preserve">${text}</w:t></w:r>${extra}</w:p>`;
export const hiddenRun = (text: string) => `<w:r><w:rPr><w:vanish/></w:rPr><w:t>${text}</w:t></w:r>`;

/** A whole document.xml (or styles.xml) around a body, for tests of the XML readers. */
export const documentXml = (body: string, ns = W) => `<?xml version="1.0" encoding="UTF-8"?><w:document ${ns}><w:body>${body}</w:body></w:document>`;

export async function docx(body: string, parts: { footnotes?: string; comments?: string; styles?: string } = {}): Promise<ArrayBuffer> {
  const zip = new JSZip();
  zip.file("[Content_Types].xml", `<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>`);
  zip.file("_rels/.rels", `<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>`);
  const rels = [`<Relationship Id="rS" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>`];
  if (parts.footnotes) rels.push(`<Relationship Id="rF" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>`);
  if (parts.comments) rels.push(`<Relationship Id="rC" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/comments" Target="comments.xml"/>`);
  zip.file("word/_rels/document.xml.rels", `<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${rels.join("")}</Relationships>`);
  const style = (id: string, name: string) => `<w:style w:type="paragraph" w:styleId="${id}"><w:name w:val="${name}"/></w:style>`;
  zip.file("word/styles.xml", `<?xml version="1.0" encoding="UTF-8"?><w:styles ${W}>${style("Title", "Title")}${style("Heading1", "heading 1")}${style("Heading2", "heading 2")}${style("Quote", "Quote")}${style("ListParagraph", "List Paragraph")}${parts.styles ?? ""}</w:styles>`);
  zip.file("word/document.xml", `<?xml version="1.0" encoding="UTF-8"?><w:document ${W}><w:body>${body}</w:body></w:document>`);
  if (parts.footnotes) zip.file("word/footnotes.xml", `<?xml version="1.0" encoding="UTF-8"?><w:footnotes ${W}>${parts.footnotes}</w:footnotes>`);
  if (parts.comments) zip.file("word/comments.xml", `<?xml version="1.0" encoding="UTF-8"?><w:comments ${W}>${parts.comments}</w:comments>`);
  return zip.generateAsync({ type: "arraybuffer" });
}
