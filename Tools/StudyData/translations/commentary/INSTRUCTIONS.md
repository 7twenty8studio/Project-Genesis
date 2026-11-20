# Translating Matthew Henry's Concise Commentary (VRS-8)

Each source batch, `source/NNN.json`, holds about 7,000 words of Matthew
Henry's Concise Commentary (public domain), in Bible order: a book's
introduction (kind `intro`, id = book number) and its sections (kind
`section`, id = the section's id, with the verses it comments on). Versely
shows it beside the verse, apart from Scripture, labelled as translated
commentary. Write the translation to `es/NNN.json` (Spanish, Latin
American, neutral) or `pt/NNN.json` (Brazilian Portuguese):

```json
{"batch": "NNN", "lang": "es", "entries": [
  {"kind": "section", "id": 12, "sha256": "<copied from the source entry>",
   "title": "…", "text": "…",
   "quotes": [{"n": 0, "text": "<the Bible's words you used>"},
              {"n": 1, "mode": "translated", "reason": "…"}],
   "flags": ["…"]}
]}
```

Every source entry, in the same order, with kind, id and sha256 copied
exactly; `title` only where the source has one. Then run
`python3 Tools/StudyData/commentary.py check es NNN` and fix everything it
reports until it says 0 fail and 0 to do.

## Rules
- Translate everything, faithfully and completely: no summarising, no
  additions, no softening or modernising Henry's views or his doctrine.
  Keep his voice: warm, earnest, plain devotional prose, his exclamations
  ("Oh, …!") and short applications. Write natural, readable present-day
  Spanish / Portuguese, not archaic, but keep it dignified.
- Keep the paragraphs exactly: the same blank-line breaks ("\n\n") and
  line breaks in the same places. Henry's chapter outlines (a list of
  headings each followed by "(Jr 1:1-10)") stay one paragraph, as given.
- Keep every number exactly as written, digits as digits (his "1. … 2. …"
  points, verse numbers, ages). The check compares every number.
- Bible references: keep the numbers and punctuation, write the book with
  the abbreviation in the Books table of `../bios/INSTRUCTIONS.md`
  ("Is 53:11" -> "Is 53:11", "He 2:11, 14" -> "Heb 2:11, 14" / "Hb 2:11,
  14", "1Jo 5:20" -> "1 Jn 5:20" / "1 Jo 5:20"). Henry's own short forms
  ("Jr", "He", "Ro", "Joh", "Lu", "Ep", "Re", "Jud" = Judges, or Jude in
  Jude) are listed in commentary.py (`HENRY_BOOKS`). "ver. 5" becomes
  "v. 5"; "chap. 3" / "ch. 3" becomes "cap. 3".
- Scripture Henry works into his sentences (`quotes`): he quotes the KJV
  without quotation marks ("God said, Let there be light; he willed it").
  Each source entry's `quotes` lists the runs of KJV words found
  (`english`), with the verses and their RV1909 (`es`) / Bíblia Livre
  (`pt`) text. For each, `n` counting from 0:
  - Use the target Bible's own words at that place, exactly, as one
    unbroken run of `es` / `pt` (its first letter's case and the
    punctuation at its ends may change; separate runs may be joined with
    "…"), archaic spellings and accents included ("fué", "á", "Jehová";
    "SENHOR" in the Bíblia Livre). Write the words you used in the
    answer's `text`; the check finds them in your translation and in the
    verse. Fit Henry's sentence around them, and keep his quotation the
    same length: don't quote more or less of the verse than he does.
  - If the Bible's words can't stand there (Henry changes the person or
    tense, or the RV1909 / Bíblia Livre says it so differently that his
    point would be lost) or it isn't really a quotation (a common phrase:
    "the name of the Lord" in his own sentence), answer
    `{"n": 1, "mode": "translated", "reason": "…"}` and translate.
  - Don't add quotation marks Henry doesn't have. His own quotation marks
    stay.
  - A verse he quotes that isn't listed (or listed with the wrong
    verse): if you recognise it, look it up, never quote from memory:
    `GENESIS_RV1909=<RV1909.sqlite> python3 Tools/StudyData/commentary.py
    verse es "Rom 8:28"` (or `verse pt "Rom 8:28"`; book codes as in
    scripture_quotes.BOOKS), use those words exactly and add a flag
    ("unlisted quotation of Rom 8:28"). If you can't place it, translate
    it and flag it. Never invent Bible text.
- `flags`: anything a reviewer should look at, one line each, above all
  explanations that depend on the KJV's English wording (Henry explaining
  an English word, "the word *mansions*", that the RV1909 / Bíblia Livre
  renders differently: translate his explanation and say which word the
  target Bible uses). Also uncertain readings of the English.
  Begin a flag with "sensitive:" wherever Henry speaks harshly of a people,
  race, nation or faith (the Jews as a whole, Africans or skin colour,
  Roman Catholics or the pope, Muslims or Turks, "heathens", women): the
  owner decides on an editorial note for each. Translate those passages
  faithfully and in full all the same; never soften or leave anything out.
- "the Lord", "God", "Christ" in Henry's own sentences: "el Señor" /
  "o Senhor", "Dios" / "Deus", "Cristo"; inside a quotation, the Bible's
  own word ("Jehová", "SENHOR").
- Names of people and places: use the batch's `glossary` (English ->
  Spanish/Portuguese, as the app shows them). For a name not in it, use
  the usual spelling of the Reina-Valera (Spanish) or Almeida/Bíblia Livre
  (Portuguese), modernized as the app writes them (Spanish: "Jacob",
  "Isaac", "Josué", "Jerusalén"; Portuguese: "Jacó", "Isaque", "Josué",
  "Jerusalém").
- Terms, the same everywhere: grace gracia / graça; covenant pacto /
  aliança (pacto where the Bíblia Livre has it in a quotation); the
  gospel el evangelio / o evangelho; atonement expiación / expiação;
  sanctification santificación / santificação; justification
  justificación / justificação; repentance arrepentimiento /
  arrependimento; Providence la Providencia / a Providência; the church
  la iglesia / a igreja; the Mediator el Mediador / o Mediador; the
  Redeemer el Redentor / o Redentor; the Saviour el Salvador / o
  Salvador; the Holy Spirit / the Spirit el Espíritu Santo / el Espíritu,
  o Espírito Santo / o Espírito; saints santos; sinners pecadores; heaven
  el cielo / o céu; hell el infierno / o inferno; the sabbath el sábado /
  o sábado (the Bibles' word); the Christian sabbath el sábado cristiano /
  o sábado cristão, explained at its first use in each section, in square
  brackets so it reads as the translators' note, not Henry's: "el sábado
  cristiano [es decir, el domingo, el día del Señor]" / "o sábado cristão
  [isto é, o domingo, o dia do Senhor]" (it keeps the link Henry makes
  between the Sabbath and Sunday); the Lord's day, where Henry says so,
  el día del Señor / o dia do Senhor; the Seed of the woman la Simiente de
  la mujer / a Semente da mulher.
- No English left, except names that are the same in both languages.
- Use straight JSON: escape quotes and newlines; UTF-8; no comments.
