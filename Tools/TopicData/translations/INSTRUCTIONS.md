# Translating Nave's topics (VRS-8 part 3)

Each source batch, `source/NNN.json`, holds about 5,000 words of Nave's
Topical Bible (1896, public domain): whole topics, in order, as `items`.
A `topic` item is a topic's name ("Aaron", "Humility"); the `entry` items
after it are its headings ("Death of", "Instances of"), each with the
`topic` it belongs to and, for a sub-heading, the heading it's `under`.
People read a heading together with its topic: "Aaron › Death of". Write
the translation to `es/NNN.json` (Spanish, Latin American, neutral) or
`pt/NNN.json` (Brazilian Portuguese):

```json
{"batch": "NNN", "lang": "es", "items": [
  {"kind": "topic", "id": 1, "sha256": "<copied from the source item>", "text": "Aarón"},
  {"kind": "entry", "id": 1, "sha256": "<copied>", "text": "Linaje de"}
]}
```

Every source item, in the same order, with its kind, id and sha256 copied
exactly (leave out `topic`, `under` and `quotes`). Then run
`python3 Tools/TopicData/naves.py check es NNN` and fix everything it
reports until it says 0 fail and 0 to do. Write the file with a short
Python script (json.dump, ensure_ascii=False) rather than by hand, so the
JSON is valid; one batch has about 1,200 items.

## Rules
- Translate every item, faithfully: no summarising, no additions, no
  notes. Headings stay short and in Nave's style. A heading that ends in
  "of", "to", "concerning" reads with its topic: keep that shape
  ("Death of" -> "Muerte de" / "Morte de").
- Sentence case as in the source: topic names start with a capital;
  headings start with a capital only where the English does.
- Fixed phrases: the batch's `phrases` gives the translation of headings
  that recur hundreds of times ("General scriptures concerning" ->
  "Pasajes generales sobre"). Use them exactly. If one plainly doesn't
  fit a particular topic (the gender of "Conquistada", say), write what
  fits and add `"phrase_note": "<why>"` to that item.
- Names of people and places: use the batch's `glossary` (English ->
  Spanish/Portuguese, as the app shows them). A topic named after one
  person or place must be the glossary's spelling, or add
  `"name_note": "<why>"` (for example when the topic is a common word,
  "Hope", not the name). Where the glossary lists several ("Abdón
  (person); Adón (person)"), pick the one meant. For a name not in it,
  use the usual spelling of the Reina-Valera (Spanish) or Almeida /
  Bíblia Livre (Portuguese), modernized as the glossary is.
- Keep every number exactly ("2. A Levite" -> "2. Un levita").
- Bible references inside a heading ("So 4:8" is the Song of Solomon,
  "Jude 1:14") are checked whole, book, chapter and verse: write them with
  Easton's table, `Tools/StudyData/translations/bios/INSTRUCTIONS.md`
  › Books ("So 4:8" -> "Cnt 4:8" / "Ct 4:8"). "R. V." stays "R. V.".
- Quotations ("…" in Nave's, straight double quotes): every one stays a
  quotation, in the same order, with the same straight quotes `"`. Each
  source item's `quotes` says what each one is (`n` counts from 0):
  - `whole`, `partial`, `loose`: Scripture. Quote the item's `es` (or
    `pt`) text exactly, letter for letter, archaic accents included
    ("fué", "á"): one unbroken run for `partial`, runs joined with "…"
    for `loose`.
  - `wording`: one or two KJV words Nave's uses. Use the word of the
    `es` / `pt` verse that renders it if there is one, otherwise
    translate; keep the quotation marks.
  - `unsure`: a phrase also found in a verse the heading doesn't list.
    Translate it to fit (use the verse's words only if it plainly is it).
  - `other`: not Scripture. Translate it.
  If the verses given aren't the ones quoted, add a `quote_fixes` entry
  to the item as Easton's instructions describe
  (`{"n": 0, "reference": "Josh 5:14", "mode": "verbatim", "reason": "…"}`,
  then `naves.py fix es --rv1909 …`; or `"mode": "translated"` with a
  reason). Never drop part of a quotation.
- No English left, except names that are the same in both languages.
- Theological terms: use the usual evangelical/Protestant Spanish and
  Portuguese terms, consistently across batches ("Atonement" ->
  "Expiación" / "Expiação", "Sanctification" -> "Santificación" /
  "Santificação", "Faith" -> "Fe" / "Fé"). Keep it
  non-denominational.
