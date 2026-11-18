# Translating Easton's descriptions (VRS-8)

Each source batch, `source/NNN.json`, holds about 5,000 words of Easton's
Bible Dictionary (1897, public domain): the biographies (kind `person`)
and place descriptions (kind `place`) shown in Versely's Explore. Write
the translation to `es/NNN.json` (Spanish, Latin American, neutral) or
`pt/NNN.json` (Brazilian Portuguese):

```json
{"batch": "NNN", "lang": "es", "entries": [
  {"kind": "person", "id": 12, "sha256": "<copied from the source entry>", "text": "…"}
]}
```

Every source entry, in the same order, with its kind, id and sha256
copied exactly. Then run `python3 Tools/StudyData/bios.py check es NNN`
and fix everything it reports until it says 0 fail and 0 to do.

## Rules
- Translate everything, faithfully and completely: no summarising, no
  additions, no notes of your own, no modernising Easton's views. It's a
  dictionary entry; keep its register (formal, clear).
- Keep the paragraphs exactly: the same number of blank-line breaks
  ("\n\n", including any space after them) in the same places.
- Keep every number exactly as written, digits as digits: chapters,
  verses, years, ages, distances, counts ("300 miles" stays "300 millas" /
  "300 milhas"; don't convert units). The check compares every number.
- Bible references: keep the numbers and punctuation, write the book with
  the abbreviation in the table below ("(Gen. 12:1, 2)" -> "(Gn 12:1, 2)").
  "comp." becomes "comp." / "cf."; "ch." becomes "cap.".
- Quotations (“…”): every one stays a quotation, in the same order, with
  the same curly quotation marks “ ”, so Scripture stays apart from
  Easton's commentary. Don't add or drop any, and don't use “ ” for
  anything else. Each source entry's `quotes` says what each one is
  (`n` counts them from 0):
  - `whole`: a whole verse. Quote the entry's `es` (or `pt`) text exactly,
    letter for letter, archaic accents included ("fué", "á").
  - `partial`: words from inside a verse. Quote the matching words of
    `es` / `pt` exactly, as one unbroken run of that text (its first
    letter's case and the punctuation at its ends may change). If the
    words aren't one run there, use the shortest run holding them.
  - `loose`: Easton's quote differs from the KJV (his brackets,
    ellipses, wording). Quote the matching words of `es` / `pt` exactly;
    separate runs may be joined with "…".
  - `wording`: one or two KJV words Easton comments on. Use the word of
    the `es` / `pt` verse that renders it if there is one, otherwise
    translate; keep the quotation marks.
  - `unsure`: a short phrase also found in a verse Easton doesn't cite
    here, so maybe not a quotation of it. Translate it to fit Easton's
    meaning (use the verse's words only if it plainly is that verse).
  - `other`: not Scripture (Easton's term, a name's meaning, another
    author). Translate it.
  If the verse given plainly isn't the one Easton quotes, still follow the
  rule for its kind (the check enforces it) and mention it in your report.
  The check enforces whole, partial and loose; those three, wording and
  unsure are listed in review/NNN.md for the owner to look over.
- Names of people and places: use the batch's `glossary` (English ->
  Spanish/Portuguese, as the app shows them). For a name not in it, use
  the usual spelling of the Reina-Valera (Spanish) or Almeida/Bíblia Livre
  (Portuguese). Hebrew and Greek words given as meanings or transliterations
  ("Father of a multitude", "Heb. _kohen_") keep the transliteration; the
  English meaning is translated.
- Hebrew or Greek letters, if any, are copied unchanged.
- No English left, except names that are the same in both languages.
- Use straight JSON: escape quotes and newlines; UTF-8; no comments.

## Books

| Easton | Spanish | Portuguese |
| --- | --- | --- |
| Gen. | Gn (Génesis) | Gn (Gênesis) |
| Ex. | Éx (Éxodo) | Êx (Êxodo) |
| Lev. | Lv (Levítico) | Lv (Levítico) |
| Num. | Nm (Números) | Nm (Números) |
| Deut. | Dt (Deuteronomio) | Dt (Deuteronômio) |
| Josh. | Jos (Josué) | Js (Josué) |
| Judg. | Jue (Jueces) | Jz (Juízes) |
| Ruth | Rt (Rut) | Rt (Rute) |
| 1 Sam. | 1 S (1 Samuel) | 1 Sm (1 Samuel) |
| 2 Sam. | 2 S (2 Samuel) | 2 Sm (2 Samuel) |
| 1 Kings | 1 R (1 Reyes) | 1 Rs (1 Reis) |
| 2 Kings | 2 R (2 Reyes) | 2 Rs (2 Reis) |
| 1 Chr. | 1 Cr (1 Crónicas) | 1 Cr (1 Crônicas) |
| 2 Chr. | 2 Cr (2 Crónicas) | 2 Cr (2 Crônicas) |
| Ezra | Esd (Esdras) | Ed (Esdras) |
| Neh. | Neh (Nehemías) | Ne (Neemias) |
| Esther | Est (Ester) | Et (Ester) |
| Job | Job (Job) | Jó (Jó) |
| Ps. | Sal (Salmos) | Sl (Salmos) |
| Prov. | Pr (Proverbios) | Pv (Provérbios) |
| Eccl. | Ec (Eclesiastés) | Ec (Eclesiastes) |
| Cant. | Cnt (Cantares) | Ct (Cânticos) |
| Isa. | Is (Isaías) | Is (Isaías) |
| Jer. | Jer (Jeremías) | Jr (Jeremias) |
| Lam. | Lm (Lamentaciones) | Lm (Lamentações) |
| Ezek. | Ez (Ezequiel) | Ez (Ezequiel) |
| Dan. | Dn (Daniel) | Dn (Daniel) |
| Hos. | Os (Oseas) | Os (Oseias) |
| Joel | Jl (Joel) | Jl (Joel) |
| Amos | Am (Amós) | Am (Amós) |
| Obad. | Abd (Abdías) | Ob (Obadias) |
| Jonah | Jon (Jonás) | Jn (Jonas) |
| Micah | Mi (Miqueas) | Mq (Miqueias) |
| Nah. | Nah (Nahúm) | Na (Naum) |
| Hab. | Hab (Habacuc) | Hc (Habacuque) |
| Zeph. | Sof (Sofonías) | Sf (Sofonias) |
| Hag. | Hag (Hageo) | Ag (Ageu) |
| Zech. | Zac (Zacarías) | Zc (Zacarias) |
| Mal. | Mal (Malaquías) | Ml (Malaquias) |
| Matt. | Mt (Mateo) | Mt (Mateus) |
| Mark | Mr (Marcos) | Mc (Marcos) |
| Luke | Lc (Lucas) | Lc (Lucas) |
| John | Jn (Juan) | Jo (João) |
| Acts | Hch (Hechos) | At (Atos) |
| Rom. | Ro (Romanos) | Rm (Romanos) |
| 1 Cor. | 1 Co (1 Corintios) | 1 Co (1 Coríntios) |
| 2 Cor. | 2 Co (2 Corintios) | 2 Co (2 Coríntios) |
| Gal. | Gá (Gálatas) | Gl (Gálatas) |
| Eph. | Ef (Efesios) | Ef (Efésios) |
| Phil. | Fil (Filipenses) | Fp (Filipenses) |
| Col. | Col (Colosenses) | Cl (Colossenses) |
| 1 Thess. | 1 Ts (1 Tesalonicenses) | 1 Ts (1 Tessalonicenses) |
| 2 Thess. | 2 Ts (2 Tesalonicenses) | 2 Ts (2 Tessalonicenses) |
| 1 Tim. | 1 Ti (1 Timoteo) | 1 Tm (1 Timóteo) |
| 2 Tim. | 2 Ti (2 Timoteo) | 2 Tm (2 Timóteo) |
| Titus | Tit (Tito) | Tt (Tito) |
| Philemon | Flm (Filemón) | Fm (Filemom) |
| Heb. | He (Hebreos) | Hb (Hebreus) |
| James | Stg (Santiago) | Tg (Tiago) |
| 1 Pet. | 1 P (1 Pedro) | 1 Pe (1 Pedro) |
| 2 Pet. | 2 P (2 Pedro) | 2 Pe (2 Pedro) |
| 1 John | 1 Jn (1 Juan) | 1 Jo (1 João) |
| 2 John | 2 Jn (2 Juan) | 2 Jo (2 João) |
| 3 John | 3 Jn (3 Juan) | 3 Jo (3 João) |
| Jude | Jud (Judas) | Jd (Judas) |
| Rev. | Ap (Apocalipsis) | Ap (Apocalipse) |
