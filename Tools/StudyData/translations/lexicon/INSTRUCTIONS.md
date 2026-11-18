# Translating the word-study lexicon (VRS-8 part 4)

Each source batch, `source/NNN.json`, holds about 6,000 words of the
lexicon that opens when someone taps a Hebrew or Greek word: Strong's
Hebrew Dictionary (1890; `"language": "hebrew"`) and Abbott-Smith's
Manual Greek Lexicon of the New Testament (1922; `"greek"`), both via
STEPBible / Open Scriptures (CC BY 4.0). Each entry has its Strong's number
(`strongs`), the `lemma` (context only, don't translate it), its `sha256`
and up to three fields to translate:

- `gloss`: one or two words ("father", "love"), the word's basic meaning.
- `definition`: the lexicon's article. Line breaks are its layout.
- `derivation`: Strong's note on where the word comes from ("from 2336").

Write the translation to `es/NNN.json` (Spanish, Latin American, neutral)
or `pt/NNN.json` (Brazilian Portuguese):

```json
{"batch": "NNN", "lang": "es", "entries": [
  {"strongs": "H0001G", "sha256": "<copied>", "gloss": "padre",
   "definition": "padre, en una aplicación literal e inmediata, o figurada y remota",
   "derivation": "palabra primitiva;"}
]}
```

Every source entry, in order, with `strongs` and `sha256` copied exactly,
and exactly the fields the source has. Write the file with a short Python
script (json.dump, ensure_ascii=False). Then run
`python3 Tools/StudyData/lexicon.py check es NNN` and fix everything until
it says 0 fail and 0 to do.

## Keep exactly as written
- Every Hebrew and Greek word, letter for letter, accents and breathings
  included, in the same order ("ἀγάπη, -ης, ἡ" stays at the start). Never
  transliterate, translate or drop one.
- Strong's numbers and every other number ("from 2336", "§ 47", "70f.").
- STEPBible references: "Jhn.13:35", "1Co.2:3", "Act.4:5 4:7", "2Ma.4:1"
  are codes: copy them unchanged, with their "†" or "*" marks.
- References with English book names (Strong's: "Ezekiel 29:4",
  "Psalm 45:1") are written with Spanish / Portuguese names, as in Easton's
  table (`../bios/INSTRUCTIONS.md` › Books): "Ezequiel 29:4" / "Ezequiel 29:4".
- Sigla of works, editions and versions: LXX, MM, VGT, WH, ICC, DB, LS,
  AV, RV, EV, BDB, Cremer, Deiss., Thayer, Field and the rest, and Roman
  numerals ("Exp. Times, xxvi" keeps its numerals). "NT" stays NT; "OT"
  becomes "AT".
- Marks †, * and §, and grammatical forms of the Greek ("-ης, ἡ", "-ῶ").
- Morphology codes and grammatical abbreviations use the table in
  `abbreviations.json` (English -> es/pt, the same every time: "pass." ->
  "pas." / "pass.", "aor." -> "aor.", "c. gen." -> "c. gen."). An
  abbreviation not in the table: keep it if it's Latin or a siglum,
  otherwise use the usual Spanish / Portuguese one.

## Translate
- Everything else, faithfully and completely: no summarising, no notes,
  nothing added. Keep the punctuation pattern (Strong's lists of senses
  separated by ";" and ",", Abbott-Smith's "1. … (a) …" outlines) and the
  same line breaks.
- Recurring phrases, the same in every batch:

| English | Spanish | Portuguese |
| --- | --- | --- |
| a primitive root | raíz primitiva | raiz primitiva |
| from 1234 | de 1234 | de 1234 |
| the same as 1234 | lo mismo que 1234 | o mesmo que 1234 |
| corresponding to 1234 | correspondiente a 1234 | correspondente a 1234 |
| feminine of 1234 | femenino de 1234 | feminino de 1234 |
| compare 1234 | compárese 1234 | compare 1234 |
| (Aramaic) | (arameo) | (aramaico) |
| properly | propiamente | propriamente |
| figuratively | figuradamente | figuradamente |
| literally or figuratively | literal o figuradamente | literal ou figuradamente |
| by implication | por implicación | por implicação |
| specifically | específicamente | especificamente |
| causatively | causativamente | causativamente |
| hence | de ahí | daí |
| i.e. | es decir | isto é |
| an Israelite | un israelita | um israelita |
| the name of two Israelites | nombre de dos israelitas | nome de dois israelitas |
| a place in Palestine | un lugar en Palestina | um lugar na Palestina |
| see word | véase la palabra | veja a palavra |
| which see | véase | veja |
| see MM, VGT | véase MM, VGT | veja MM, VGT |
| in l. with | en l. con | em l. com |
| Notes | Notas | Notas |
| with accusative of person | con acusativo de persona | com acusativo de pessoa |

- Names of people and places: the Reina-Valera 1909 spelling, modernized
  (Spanish), Almeida / Bíblia Livre (Portuguese), as Explore spells them.
- Theological terms: the usual evangelical/Protestant ones, the same
  across batches (as in Easton's and Nave's: expiación / expiação,
  santificación / santificação, pacto / aliança). Non-denominational.
- English words the lexicon discusses as words ("AV renders it 'charity'")
  stay in English inside the quotation, with the rest translated.
- `gloss`: the plain word or two, lower case as in the English.

If something must stay as it is (an English quotation, a siglum the check
doesn't know), add `"note": "<why>"` to that entry; notes are listed for
review.
