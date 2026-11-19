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
- Pronouns that agree with a noun follow the Greek gender ("la" for a
  feminine Greek word) where the Spanish or Portuguese noun differs.
- Choices a reviewer may want to revisit: nephesh "self" as "ser" ("mi
  ser"), H2617 "covenant loyalty" as "lealtad del pacto" / "lealdade da
  aliança", split numbers ("fif- | teen" as "cinco- | diez").
