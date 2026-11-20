# Translator notes to review (word-study lexicon)

All 74 batches (17,431 entries: 11,636 Hebrew from Strong's, 5,795 Greek
from Abbott-Smith via STEPBible) pass `lexicon.py check` in Spanish and
Brazilian Portuguese, and `add_lexicon_translations.py` puts all 34,862 rows
in WordStudy.sqlite's `lexicon_translations`. Translated: gloss, definition,
derivation. "In the KJV" (usage) stays English. Every entry's own notes are
in `<lang>/review/NNN.md` (and its `note` field); these are the judgement
calls across batches.

## What the check holds fixed
Every Hebrew and Greek word in order, every number, Strong's numbers,
STEPBible codes ("Jhn.13:35") and, in the Greek, Abbott-Smith's short
references ("Jn 2:13") verbatim; Strong's English-named references compared
whole (refs.py); sigla (LXX, MM, WH… with OT → AT, SW → SO), marks † * §
and Greek punctuation. Dates (BC/AD), TIME/QUESTION-style gloss tags and
"Mid./Med./Méd." (middle voice) are translated, not copied.

## Source fixes (`SOURCE_FIXES` in lexicon.py, English and both languages)
- H3654: "Hebrews 13:14" was STEPBible's expansion of "[Heb. 13, 14]",
  the Hebrew Bible's verse numbers: now "[Hebrew 8:13,14]".
- G3985G/H/I: "af6ictions" (scan slip) is "afflictions".
- G0237 "(seeMM", G0373 "ofIs 11:2", G3636 "forPro.6:6": words run together.
- G0622, G0629: "WH." is a misread "which", not Westcott-Hort.
- G0483: "contradict" typed with a Greek omicron.
- G5418: "Soph., OT, 1387" is Sophocles' Oedipus Tyrannus, not the Old Testament.
- G1296: "WH., however, is found in LXX" is "which, however" too.
- H0930: "in form a plural or 929" is Strong's "a plural of 929".

## STEPBible's machine expansions, rendered the same way everywhere
- "(with)", "§ with", "853 with", "l.with", "ll. with" are a misread "c."
  (cum / page section): "(c.)", "853 c.", "l. con" / "l. com",
  "ll. con" / "ll. com". "Syn., § with" is Trench § c (100): "§ c".
- "accusative to" (acc. to = according to): "según" / "segundo"; but
  "C. accusative, to attend to" (G3191) is "with the accusative".
- "dupl. accusative": doble / duplo acusativo.
- Strong's "espec." expanded as "expectation" (H2384, H5059, H5104G/H):
  "especialmente".
- Normalized at the end: "(c)" → "(c.)", "l.c."/"l. c." → "l. con"/"l. com",
  "Field, Notes" / "Lft., Notes" → "Notas", es "espanto" → "terror"
  (the other "terror" glosses), es "Sion" → "Sión" (RV1909).

## Glosses that don't fit their article (STEPBible's lists; kept or fixed)
- Translated as given, with a note: G0062 "unschooled" (ἀγραυλέω),
  G1744 "to sneak" (ἐνδύω), G1749 "hinderance"
  (ἐνέδρα), G2600 "descent", G4821 "to reign with" (to advise),
  G2450/G2452 "Jew", G2491K/G2495G "John" on Jonah's article, G1212
  "Urim" (δῆλος), H4519 "Moses", H8176 "to know", H2256A "Mahalab",
  H6905G "Ible", H7316G "Dumah" on Rumah, H8483 "Kadesh".
- Corrected: G2985 λαμπάς "window" → antorcha / tocha; G3426 μόδιος
  "bucket" → almud / alqueire (a dry measure); G3479/G3480 "Nazareth" → nazareno; G2858 "Colossae" → colosense (es).

## Misplaced articles fixed (`ARTICLE_FIXES` in lexicon.py)
STEPBible's TBESG put another word's article in some entries, whole or
appended. They are fixed in the English (WordStudy.sqlite's lexicon, by
`fix_database`, which add_lexicon_translations.py runs first) and in both
translations, cut at the same line:
- Appended articles cut: G3772 οὐρανός (βασιλεία's, and a stray "\"),
  G1605 ἐκπλήσσω (δειλία's), G3925 παρεμβολή (παρεμβάλλω's), G3982 πείθω
  (Πειθώ's), G3988 πεισμονή (πείθω's), G4007 πέρ (ὥσπερ's), G4076 πήγανον
  (περισσῶς's; only its heading is left).
- Prefixed article cut: G1633 ἐκχωρέω (ἐκχύννω's before its own).
- No article of its own, so the gloss stands alone: G3426 μόδιος
  (μοιχαλίς's), G1623 ἕκτος, sixth (ἐκτός's), G4776 συγκαθίζω (περικαθίζω's).
- Forms of σύ given σύ's article (G4771) instead of αὐτός's or a garble:
  G4571, G4671, G4675, G5209, G5210, G5213, G5216.
- Kept: G3746 ὅσπερ ("see: ὅς" followed by ὅς's article, the word it
  refers to), G3755 ὅτου (ὅστις's article, whose form it is), the forms of
  εἰμί, ἐγώ, οὗτος and εἰ that share their word's article, and the short
  LSJ/Mounce notes that stand in for Abbott-Smith (G4055, G4056, G4069,
  G4191, G4193, G1622 ἐκτός).

## Names (RV1909 modernized / Bíblia Livre, else Almeida)
- Check in review: es G3104 Μεννά "Mainán" (RV1909 Lk 3:31; pt Mainã);
  pt mixes Almeida where the Bíblia Livre differs (H7535 Zair, H7906 Seco,
  H8197A/B Sefufã, H8556B Timnate-Sera, H7486G/H Raamsés); pt Gershom and
  Gershon are both "Gérson", Joses and Joseph both "José", Aram and Aaron
  both "Arão", as the Bíblia Livre spells them; pt H7956 Shelah "Selá"
  (Strong's says the patriarch); pt batch 065 merges "Sala, Shalah" to "Salá";
  Jehovah → Jehová / Jeová, Yahweh (3, as Strong's writes it) → Yahvé / Javé.
- G6632 "(Ne, i.e.;" read as a misread "l.c." in both languages: check.

## Source oddities copied as they are
Impossible or odd codes (Jas.22:25, Mat.92:6, Luk.34:17, Act.2:1-2 for
Tertullus, "Joshua 16:19" probably Job), digit misprints the check counts
("a1.", "p1.", "131.", "B1."), unclear "seel.", garbles ("severallyrally",
"everny", "rabundant", "overgrowhoke"), truncated Strong's derivations
(H1511, H7789, H8338, H8501, H8567), unclosed parentheses (H7320, G5037).
Rhegium "in Sicily" as Abbott-Smith has it.

## AI review, 19 November 2026 (not qualified sign-off)
Fifteen AI reviewers each read every entry of 4 or 5 batches (gloss,
definition, derivation) in Spanish and in Portuguese against the English,
all 74 batches, and fixed errors of meaning, grammar and terminology in
place; a corpus-wide sweep then carried the patterns they found to every
batch. 516 fixes (292 es, 224 pt; 274 meaning, 131 terminology, 64
grammar, 30 untranslated, 17 other) are listed with the old and new text
and the reason in `ai-review/fixes.jsonl`; 59 doubts left unchanged for a
qualified reviewer are in `ai-review/queries.jsonl`. Every batch still
passes `lexicon.py check`. No qualified human reviewer has signed off on
the Spanish or Portuguese.

What came up most:
- Glosses that rendered a sense from the definition (or a traditional
  word) instead of the English gloss given: "ring" → moldura, "scroll" →
  libro/livro, "late fig" → figo temporão (early), "propitiation" →
  propiciatorio, "unique" → unigénito, "arrow" → dardo.
- Glosses in the wrong part of speech, degree or voice (a noun made a verb,
  "strictest" as a comparative, "to be left" as "dejar").
- False friends in pt: emissão (issue = offspring), sorte (sort), aprisco
  (fold = doubling), conhecimento (acquaintance = a person), dificilmente
  (hardly = with difficulty), chifrar (escornar).
- Number and gender: H0607/H0608 singular/plural swapped, feminine
  pronouns given masculine forms, "el ἀγορά".
- STEPBible garbles rendered word for word: "of person(s) pron." (now
  pron. personal / pron. pessoal; ἐγώ's "I." is yo / eu), "3rd of
  person(s)", "dupl. accusative" (doble acusativo), "I. con" / "ll con"
  (l. con, ll. con), "genitive cubic." (subj.), "gen. pun." (de pena).
- Abbreviations: es "f."/"ff." left in English (s./ss.), "hith." (hit.),
  "hithpo." (hitpo.), pt "prov." for "prob.", "Áq." for Aq.
- es "Paroh" (Faraón), "Bet-súa" (Bat-súa), "Junias" (Junia), "Noé" for
  Noa (H5270).

Conventions left as they are, for the owner or a qualified reviewer:
- Second person plural: the Hebrew pronoun glosses use vosotros / vós
  (H0608, H0859D/E); the Greek ὑμεῖς forms, G2075 and the Hebrew suffixes
  H9031–H9037 use ustedes / vocês (te / você for the singular suffix).
- English renderings quoted from the AV/RV/EV: es keeps «English» plus the
  Spanish, as INSTRUCTIONS asks; pt sometimes keeps only the English and
  sometimes only the Portuguese.
- LSJ author labels: es translates them ("Heródoto el Historiador"), pt
  keeps the Latin ("Herodotus Historicus").
- pt writes some Abbott-Smith short references in Portuguese forms (2Sm,
  1Rs, Pv, At), with notes; pt mixes "in l." and "em l."; es mixes
  "Esq./Sóf." with "Æsch./Soph.".
- pt (and sometimes es) gives one name where Strong's has "X or Y" and the
  two would be spelled the same in the Bible used.

## The AI review's queries, answered (20 November 2026; AI, not qualified sign-off)
Each of the 59 queries in `ai-review/queries.jsonl` now has a `resolution`
and a `resolution_note`: 19 fixed where the English is clear (for example
H0328A murmurador, H1785 obra de asedio, H6513 Fara as the RV1909's
"Phara", H8279 estilete, G3567 and G3639 where STEPBible's gloss is a slip,
G1188's RV margin «on», the two source fixes above), 5 already fixed by
the review and only their notes brought up to date, 11 kept with a reason
(names checked against the RV1909 and Bíblia Livre: Corasán, Kelaía, Sión),
and 24 left open. The open ones are conventions or policies (one rule for
the corpus) and doubts that need a Hebraist or Hellenist: the gloss-vs-sense
choice where STEPBible's gloss differs from the article (H0801, H7070G,
G2461, G2555, G2660, G3555, G4266), LSJ author labels, pt short references
and AV/RV quotations, "X or Y" names, soalho/assoalho, measures (G5518),
and H2448, G1418, G2450, G2496 (Jehoram), G3985I.
