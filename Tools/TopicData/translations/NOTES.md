# Translator notes to review (Nave's topics)

All 24 batches (29,826 items: 5,319 topic names and 24,507 headings) pass
`naves.py check` in Spanish and Brazilian Portuguese. These are the
judgement calls behind the passes; the per-batch quotation reviews are in
`<lang>/review/NNN.md`.

## Source fixes
- Entry 13599 "0f Man for Jesus" (a digit zero in Nave's text) is now
  "Of Man for Jesus" (`SOURCE_FIXES` in build_topics.py, Topics.sqlite).

## Nave's slips the translations correct (both languages agree)
- Amoz, "Father of Imiah": Isaiah ("Padre de Isaías" / "Pai de Isaías").
- "In consummation of the Levites": consecration ("consagración" / "consagração").
- Moab, "Barak commands Balaam to curse Israel": Balak ("Balac" / "Balaque").
- "Jude 1:4,5" under Ramah is probably Judges; kept as written (references are checked whole).

## App names fixed after the translators flagged them
The name aligner (translate_study.py) had given some people and places a
neighbour's name; `manual.json` › `ids` now pins them (also in Explore):
- es: Shavsha Sausa (not Sadoc), Chenaanah Quenaana (not Sedequías),
  Zephaniah Sofonías, Obal, Igal, Jegar-sahaduta, Pirathon Piratón,
  Adoniram, Rock (place) Roca, Hasrah Hasra, Hamath-zobah Hamat de Soba.
- pt: Shavsha Sausa, Obal, Adoniram Adonirão (not Adorão), Rock Rocha,
  Shupham Sufã (not Hupim), Helek Heleque, Hesed Hesede, Hamath-zobah
  Hamate-Zobá, Micah (the prophet) Miqueias, Jehoiachin Joaquim, Irijah Jerias.

## Names kept as the Bible spells them (name_note in the batch)
- es: Dibri (the glossary's "Dribi"), Elpalet, En-rogel, En-tapua, Abia,
  Acaz (Achaz), Ben-hanán, Geba.
- pt: Dara and Darda (two topics), Hadar and Hadarezer (Nave's own forms,
  set against Hadad/Hadadezer), En-Rogel, En-Tapua, Semarias (Shamariah, not
  the city), Sabá, Sete (Sheth) and "Sete (número)", Zizá, Hasra.
- Topics that are common words, not the person or place: pt Rocha, Pecado (Sin).

## Terms made consistent
- es: impío (not malvado), sábado (not día de reposo), Joás, "Véase también",
  principales sacerdotes, Padrenuestro, ofrenda de cereal (meat offering;
  the RV1909's "presente" isn't used), sumergir / inmersión for Nave's
  "immerse" (the Portuguese has imergir throughout).
- pt: trasladação for the translation of Enoch and Elijah (not
  "arrebatamento", which reads as the Rapture); igreja for Nave's
  "congregation" of Christians, congregação for Israel's.

## Left as is, worth a look
- Lot is one topic for the man and for casting lots: es "Lot", pt "Ló"
  ("1. Festa das sortes" under it).
- Micah covers several men: es "Micá", pt "Mica" (the prophet is entry 6).
- "Also called PHENICIA and PHOENICIA": both spellings are Fenicia / Fenícia;
  es repeats it, pt says it once.
- pt "dog" (Deut 23:18) as the Bíblia Livre's "prostituto".
- pt Luke 10:25 quoted with the Bíblia Livre's "para ter para", verbatim.

## AI review (19 Nov 2026)
- Every topic and heading read again in both languages against the English (an AI review, no human sign-off yet): 178 corrections, pt "igreja" for Christian congregations throughout, Efraim / efraimita in the Spanish, name_note and phrase_note where the glossary or a fixed phrase was wrong. Details and open questions: Tools/StudyData/translations/AI_REVIEW_2026-11-19.md.
