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
  G1623 "sixth" (ἐκτός), G1744 "to sneak" (ἐνδύω), G1749 "hinderance"
  (ἐνέδρα), G2600 "descent", G4821 "to reign with" (to advise),
  G2450/G2452 "Jew", G2491K/G2495G "John" on Jonah's article, G1212
  "Urim" (δῆλος), H4519 "Moses", H8176 "to know", H2256A "Mahalab",
  H6905G "Ible", H7316G "Dumah" on Rumah, H8483 "Kadesh".
- Corrected: G2985 λαμπάς "window" → antorcha / tocha; G3426 μόδιος
  "bucket" → almud / alqueire (its article is μοιχαλίς's, translated as it
  stands); G3479/G3480 "Nazareth" → nazareno; G2858 "Colossae" → colosense (es).
- Entries carrying another word's article (translated as they stand):
  G3772 (βασιλεία), G4076 (περισσῶς), G4571/G4671/G4675/G5209/G5210/G5213
  (αὐτός on σύ forms), G3746/G3755, G4055/G4056/G4069/G4191/G4193 (not
  Abbott-Smith's text), G1605 runs into δειλία.

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
