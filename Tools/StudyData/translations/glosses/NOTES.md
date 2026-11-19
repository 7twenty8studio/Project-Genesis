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
- Choices a reviewer may want to revisit: nephesh "self" as "ser" ("mi
  ser"), H2617 "covenant loyalty" as "lealtad del pacto" / "lealdade da
  aliança", split numbers ("fif- | teen" as "cinco- | diez").
