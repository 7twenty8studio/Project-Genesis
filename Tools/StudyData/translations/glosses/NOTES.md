# Notes on the Spanish and Portuguese glosses (VRS-6)

Written 19 November 2026, when all 58 batches were first complete. Sources,
licences and credits: SOURCES.md. Translator rules: INSTRUCTIONS.md.

## What there is

- 114,121 (Strong's, morphology, English gloss) units, each translated into
  Spanish (neutral Latin American, tú/vosotros as the RV1909) and Brazilian
  Portuguese (tu/vós as the Bíblia Livre).
- 26,526 units read in their verses (`checked`): every gloss with a supplied
  verb ("[was]", "[is]"), a modal ("will", "shall", "may"), the question
  particle, an uncertain meaning, and others whose sense moves with the verse.
- About 5,300 verse-specific translations per language (`occurrences`),
  where one unit needs different words in different verses: ser/estar/haber
  for a supplied verb, the person of a supplied verb, the gender of the Greek
  article (3,674 es and 3,488 pt, scripted from the noun it goes with, then
  spot-checked), Portuguese "uma"/"duas", stressed pronouns after a
  preposition, the mood after "if"/"when".
- 1,358 uncertain meanings per language, listed with reasons in
  `<lang>/review/NNN.md`. They stay AWAITING QUALIFIED REVIEW (the app shows
  "(?)") until a reviewer signs them off in reviewed.json.
- 170 notes per language: words spelled the same as the English, name
  fragments and transliterations, and places where the morphology was
  followed over STEPBible's English (or the English kept where the verse
  reads it so).

## How it was made

Each batch was translated by an AI model (the owner's Claude subscription,
no paid API) in chunks, then checked with `glosses.py check`, then committed.
Batches 003, 006 and 007 had a second look at their uncertain meanings.
Two consistency passes ran over all batches afterwards:

1. No word supplied for STEPBible's "[one]" (the check lets it go: "un
   cruel", "el que"), where earlier batches had "[varón]" or "[ser]";
   Spanish "e" before an i sound.
2. Person and number against the morphology; stressed pronouns after a
   preposition; Portuguese "uma"/"duas" and Spanish "una"; one spelling per
   name; "[masc]"/"[fem]" as the English has them.

Also fixed along the way: no Spanish future subjunctive ("si es", not "si
fuere"); "will"/"shall" never rendered with querer unless the verse means
wanting; the Greek article agreeing with the Spanish and Portuguese noun.

## The owner's review of 19 November 2026 (PR #33)

Four examples were wrong in a way the checks can't see: Matthew 5:29 "échala
[la]" / "lança [-a]" (the pronoun twice, and feminine for the eye),
Revelation 9:21 "hechiceros" / "feiticeiros" for φαρμακειῶν (sorceries) and
Portuguese "o imoralidade", and John 13:34 and 15:12 "vosotros" / "vós" for
ὑμᾶς as an object. Each is fixed, with tests (test_glosses.py
`ReviewedExamples`, OriginalGlossesTests in the app), and the same kinds of
mistake were looked for in every batch by the scripts in `audits/` (run.sh
runs them in order; running it again changes nothing):

- Greek personal pronouns with a bare gloss ("him", "you", "them"):
  accusative ones were mostly the stressed or subject form ("él", "vosotros")
  where they're objects. Now: a clitic for an object (lo, la, los, te, os;
  o, a, os, te, vos), the stressed form after a preposition (including one
  inside the verb's gloss, "iré delante de vosotros"), the subject form for
  the subject of an infinitive (217 places read by hand, `audits/review.txt`),
  "le" / "lhe" with δεῖ. Datives after a verb are indirect clitics (le, les,
  os; lhe, lhes, vos), except after follow, rebuke, worship and help, which
  Spanish and Portuguese take as direct objects; genitive objects (hear,
  touch) are direct clitics; "acuérdate de mí" after verbs of remembering.
  About 2,100 words per language changed.
- Supplied pronouns: no other verb with its pronoun supplied twice; one
  Portuguese "[eles]" as an object, now "[os]".
- Agreement with the Spanish or Portuguese noun (the Greek or Hebrew noun's
  gender often differs: ἐντολή is feminine, "mandamiento" masculine):
  Greek articles, adjectives, demonstratives and possessives, found through
  the Greek noun of the same case, number and gender; Hebrew adjectives and
  demonstratives after their noun. About 810 Greek and 460 Hebrew words in
  Spanish, 750 and 220 in Portuguese. An adjective is only changed to a form
  the translations already use, and names, construct chains and adjectives
  used as nouns ("a child", "of gold") are left alone.
- STEPBible's English against the grammar: abstract nouns glossed as people,
  agent nouns glossed as abstracts, and number. Only φαρμακεία "sorcerers"
  was wrong (now "hechicerías" / "feitiçarias", with a note); STEPBible's
  English for collectives and idioms ("descendants" for σπέρμα, "lots") was
  kept.

A random sample of 180 of the changed words was read in its verses after
the scripts ran; the two kinds of mistake it found (a pronoun read as a noun,
a genitive after "remember") were fixed in the scripts and the whole set run
again. This is still a check by an AI, not a qualified reviewer's.

## The full review of the audits' changes (19 November 2026)

At the owner's request every verse with a word the audits changed (2,231
verses, both languages) was read whole, with the Greek or Hebrew
morphology: 622 findings (483 errors, 139 doubts), almost all in the
audits' own changes or the words next to them. 617 are applied, place by
place, from `audits/review.jsonl` (`review_fixes.py`); five findings in three places were
left as they were (δεῖ with "le conviene" in Luke 17:25 and Acts 9:16,
and "sardónice" in Revelation 21:20). What they found:

- Agreement left half done: the article or adjective changed but the
  demonstrative, second adjective or participle of the same noun not
  ("<la> grande | <el> este"); the wrong noun picked as the head (a
  genitive, a supplied "[persona]"); number ignored ("de las semana");
  the shortened "primer", "tercer", "buen", "mal" after the noun; invented
  forms ("de ora", "de plato", "cevado").
- Pronouns: Spanish "a él?" / "a Mí!" for a plain object where Portuguese
  had the clitic; a preposition further back (ἄχρι καὶ ὑμῶν, μετὰ πάντων
  ὑμῶν) or at the end of the previous gloss ("delante", "junto") not
  seen; possessive genitives ("his hand") made clitics; verbs whose
  Spanish or Portuguese object differs from the Greek case (burlarse de,
  seguir, servir, preguntar, suplicar); the opening ¿ or ¡ dropped.

`audits/sweep.py` then applies the same patterns to every other verse
(about 190 words, each read by hand before it was kept): "a él?" → "lo?",
"delante de ellos", "le preguntó", "el agua" / "del arca", and the
shortened forms after a Greek noun. The pronoun scripts now keep an
opening ¿ and give Spanish the clitic before ? and ! too. `audits/run.sh`
runs everything; on the batches as they are it changes nothing.
842 words changed in 533 verses (537 Spanish, 305 Portuguese).

This is a reading by AI reviewers, not qualified sign-off: it covers the
words the audits changed and their neighbours, not every gloss, and the
1,358 meanings per language awaiting review stay awaiting.

## The verse-by-verse review of every verse (19–20 November 2026)

The owner then asked for everything to be reviewed. Every verse of the
Bible (31,102, in 132 parts) was read whole in Spanish and in Portuguese,
word by word with the Hebrew, Aramaic or Greek morphology, by AI reviewer
agents (Claude, the owner's subscription, no paid API). They found 10,577
places to correct (8,651 errors, 1,926 doubts):

- Agreement with the Spanish or Portuguese noun, by far the most: a
  pronoun, participle, relative or adjective that kept the Hebrew or Greek
  gender ("el reino … de ella", "la casa … lo", the sheep as "los", the
  beast as "de él", "verdadera" with "testimonio", "la desierto", "En la
  día siguiente", Portuguese "muitos águas", "o cabeça" for a head).
- The neuter "esto / isto" before a noun ("copa esto" → "esta copa").
- Verb person, number and mood against the morphology ("[será]" for "I",
  a Greek neuter plural's singular verb with a Spanish plural subject,
  "a menos que" with the indicative or the Portuguese future subjunctive).
- Pronoun case and form ("entre a sí mismos", a clitic as the subject of
  an infinitive), doubled words ("los que | que"), "gran" after its noun,
  "mal" for the adjective, a few meanings ("acerca de" for "about" the
  ninth hour, "preguntaron" for "begged", saber/conocer for a person).

Doubts were read again before they were applied; two kinds were left out:
the Portuguese "d'Ele" for STEPBible's capitalised "Him" stays (the
convention since batch 043), and nothing that would break the structural
checks (58 corrections that add or move a bracket, such as "uva[s]
agria[s]", are listed by `verse_fixes.py` and left as they were). 15
places had changed since the review read them and are left too.

The corrections are `audits/verses.jsonl` (verse, word, language, the
English, the text found, the correction, error or doubt, why), applied
place by place by `audits/verse_fixes.py`. Four patterns the reviewers
were told not to report one by one are applied everywhere by script:

- `kol.py`: Hebrew and Aramaic כָּל "all" agrees with what follows ("toda
  [la] tierra", "todos tus siervos").
- `demonstratives.py`: "<the> this / that" after a Hebrew noun agrees
  with the Spanish or Portuguese noun ("<la> palabra <la> esta").
- `forms.py`: an article written twice keeps one, still marked as
  supplied ("del [el] polvo" → "de[l] polvo", "da [a] boca" → "d[a]
  boca"); Portuguese "em o", "por a", "de estes" contracted ("no",
  "pela", "destes"); "entre yo / tú"; "lo servirás"; "muchas [personas]";
  "compasión<es>"; "estrangeiro" for נֵכָר.
- `pt_perfect.py`: Portuguese "tenho dito" for a finished act becomes the
  simple past ("disse"); the 36 glosses that are an ongoing state keep the
  compound form (`pt_perfect.json` lists the 321 changed).

`audits/run.sh` runs all of it after the earlier audits, with
`verse_fixes.py --final` last so a place the review read whole keeps its
reading over a pattern audit. Run again on the batches as they are, it
changes nothing. Both languages pass `glosses.py check` (114,121 each),
and the 1,358 meanings per language awaiting review stay awaiting.

This is still a reading by AI reviewers, not qualified sign-off: it is
the most thorough pass so far, but a reviewer who reads Hebrew and Greek
should still read the uncertain meanings and sample the rest.

## AI triage of the uncertain meanings (20 November 2026; not qualified review)
Six AI reviewers read each of the 1,358 uncertain meanings per language in its
verses and judged the Spanish and Portuguese against STEPBible's English:
es 1,277 ok, 52 fixed, 29 for a scholar; pt 1,291 ok, 36 fixed, 31 for a
scholar. The fixes (agreement with the es/pt noun, meanings that had followed
another reading than the English, such as "dracmas" for darics, "búfalo" for
wild ox, "piojos" for gnats, "se mutilarán" for Gal 5:12, missing Spanish ¿)
are in the batches; checks and audits/run.sh pass. Every meaning stays
uncertain and awaiting qualified review; reviewed.json is untouched. The
reviewer worksheet, with the "for a scholar" items first (places where
STEPBible's English itself looks doubtful, e.g. Amos 8:8 "like the light",
Judg 5:8 "bread", 1 Kgs 20:40 "them"), is ai-triage/WORKSHEET.md; the full
records are ai-triage/triage.jsonl (test: Tools/StudyData/test_gloss_triage.py).

## Known limits (for the reviewer)

- The structural checks don't judge meaning. Passing them says the marks,
  brackets, numbers, question particle, letters and length are right and
  that the verse was read where the rules ask for it; it says nothing about
  whether a word is the best one.
- STEPBible marks a question per word, so a question that spans several
  glosses shows its "?" on the word STEPBible put it on; Spanish then has no
  opening "¿" on the first word.
- Some STEPBible English glosses are cut off or slipped ("icers",
  "ering up of", "thatr"); they were translated as meant, with a note.
- Interlinear style is kept literal: "a <el> ti" (STEPBible's "<the>"),
  "de [el] Señor" (brackets aren't contracted), participles as participles
  ("amando").
- Portuguese "d'Ele" / "n'Ele" for STEPBible's capitalised Him (from batch
  043); Spanish "de Él".
- A preposition and its pronoun are two words in the interlinear, so
  Greek μετ' ἐμοῦ reads "con | mí" / "com | mim" (one word would be
  "conmigo" / "comigo").
- Pronouns that agree with a noun now follow the Spanish or Portuguese
  noun (the verse-by-verse review); a pronoun whose noun is in another
  verse may still follow the Hebrew or Greek gender.
- Choices a reviewer may want to revisit: nephesh "self" as "ser" ("mi
  ser"), H2617 "covenant loyalty" as "lealtad del pacto" / "lealdade da
  aliança", split numbers ("fif- | teen" as "cinco- | diez").
