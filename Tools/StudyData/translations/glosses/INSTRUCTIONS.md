# Translating the Original view's glosses (VRS-6)

The Original (Hebrew & Greek) view shows each Hebrew or Greek word with a
short English gloss under it: STEPBible's English for that word in that
verse (TAHOT, TAGNT; CC BY 4.0). These batches put those glosses into
Spanish (Latin American, neutral) and Brazilian Portuguese.

Each source batch, `source/NNN.json`, lists about 2,000 glosses grouped by
word. A word has its Strong's number, its `lemma` (context only, never
translated) and its `meaning` from the lexicon in English, Spanish and
Portuguese (a guide to the word's sense and to how names are spelled).
Each gloss has an `id`, the `morph` (morphology code), the English `gloss`
and `count` (how often it appears; spend care where it's high).

Write `es/NNN.json` and `pt/NNN.json`:

```json
{"batch": "NNN", "lang": "es",
 "glosses": {"011a94384553160b": "su padre", "84fe9144c0b3ca7c": "[el] padre de"},
 "notes": {"…": "why this one is as it is"},
 "uncertain": {"…": "why the meaning is uncertain"},
 "checked": ["…every id read in its verses…"],
 "occurrences": {"…id…": {"1009018.12": "[es] [el] padre de"}}}
```

Every id of the batch, with its translation. Write the file with a short
Python script (json.dump, ensure_ascii=False, indent=1). Then run
`python3 Tools/StudyData/glosses.py check es NNN` (and `pt`) and fix
everything until it says 0 fail and 0 to do. Notes are optional.

Sources and licences: `SOURCES.md`. Translate only the English `gloss`
given here; don't bring in glosses from other interlinears, lexicons or
Bible translations (Global Bible Tools, TAGNT's Spanish column, printed
interlinears), even ones you remember.

## Read the verse
A gloss here stands for every verse where that Strong's number, morphology
and English gloss meet, and those verses can need different words. So:

- `python3 Tools/StudyData/glosses.py needs-context NNN` lists the ids you
  must read in their verses: supplied verbs and modals (`[was]`, `[is]`,
  `[will]`, `let`…), the question particle `¿`, and everything you flag
  uncertain. Read each with
  `python3 Tools/StudyData/glosses.py context NNN <id> [<id>…]` (`--all`
  for every verse): each verse's English glosses with this word in ⟦ ⟧,
  and the KJV verse. Then list the id in `checked`.
- Also read the verses of any other gloss whose sense could change with
  the verse (spirit/wind, flesh, soul/life, lord/master, word/thing, hand,
  way, house/household, peace, judgment…) and list it in `checked`.
- If the verses need different words, give the usual one in `glosses` and
  the others in `occurrences`, by the verse and position `context` prints
  ("1009018.12"). Never one word for all when the verses disagree.
- The KJV is supporting context only. Settle tense and meaning from the
  Hebrew or Greek and its grammar (the morph, the verse's own words and
  STEPBible's English); a gloss that differs from the KJV isn't wrong for
  that. Where the original stays ambiguous, keep the ambiguity (don't pick
  one reading silently) and flag it `uncertain`.
- Supplied verbs: the tense, mood and verb the verse needs, not a habit.
  `[was]` is `era` only where the Hebrew context is a past description or
  state that "era" fits; it may be `estaba`, `fue`, `había` or `es`
  (Portuguese `era`, `estava`, `foi`, `havia`, `é`). A Hebrew nominal
  clause has no tense of its own: Gen 9:18 "Ham [was] the father of
  Canaan" states a standing fact, so `[es]` fits; the KJV's "is" supports
  that but doesn't decide it. `[will]` before a verb is the future
  (`[comerá]`), never "querer" (the check rejects it without a note)
  unless the verse means wanting.
- Keep STEPBible's mood: a supplied `[is]` stays indicative (`[is]
  cursed` → `[es] maldito` / `[é] maldito`, not "sea", even where the KJV
  has "cursed be"). Change a supplied verb's tense only where the verse
  itself sets another time (Gen 9:18).
- English "do-support" (`[does]`, `[did]` in questions and negatives) is
  never "hacer" / "fazer": use the verb or tense the verse needs (`[did]
  … [belong]` → `[era]`, `[pertenecía]`).
- Keep person, number, gender and tense exactly as the morphology and the
  English give them, and keep every uncertainty visible: if the English is
  unsure (a "?", an alternative "/"), the translation is too.

## Flag what's uncertain
Put a gloss in `uncertain` (id → a short reason) when its meaning in
Spanish/Portuguese is uncertain: a rare or disputed word (hapax, an
obscure plant, animal, instrument or term like "Selah"), an idiom whose
sense is unclear, a word whose English gloss could be read two ways, or a
name whose identification is unsure. Give your best translation anyway;
it's listed for qualified review. Don't flag ordinary words.

## The glosses' marks
- One gloss per Hebrew or Greek word, as here: never merge two words'
  glosses, move meaning from one word to another, or split one.
- `[the]`, `[is]`: words English supplies that the Hebrew/Greek doesn't
  have. Keep the brackets, translate what's inside: `[el]`, `[es]`.
- `<the>`, `<to>`: words the original has that English leaves out. Keep
  the angle brackets, translate inside: `<el>`, `<a>`.
- Brackets stay in the same order as the English. Keep `(`, `)`, digits
  and `?` `!` as they are.
- `¿` is STEPBible's mark for the Hebrew question particle (morph `Ti`),
  not punctuation: translate the particle as a word, `acaso` (Spanish) /
  `porventura` (Portuguese), where the `¿` stands, with no mark:
  `¿ is it willing` → `acaso querrá` / `porventura quererá`; `¿ [the]
  keeper` → `acaso [el] guarda` / `porventura [o] guarda`. The question's
  own mark belongs to the verse, not to one word.
- Question marks: a gloss that is itself a question (`who?`, `where?`,
  or `will we eat` shown by word order) is punctuated in full inside the
  gloss: Spanish `¿quién?`, `¿comeremos?`; Portuguese `quem?`,
  `comeremos?`. Portuguese never uses `¿` or `¡`; Spanish never leaves
  one open.
- First letter: never a capital the English doesn't have (`the fathers`
  → `los padres`). Keep the English's capital (`He put` → `Puso`) except
  where Spanish/Portuguese write lower case or the word order changes:
  gentilics (`Edomite` → `edomita`), `Abel towards` → `hacia Abel` /
  `para Abel`.

## Translate
- The gloss's own sense in this verse; the lexicon meaning is a guide,
  not a replacement. Short, literal, like an interlinear: no notes, no
  explanations, nothing added.
- Natural word order inside one gloss. STEPBible writes a Hebrew suffix
  after its noun: `father his` → `su padre` / `seu pai`; `in wrath your`
  → `en tu ira` / `em tua ira`; `[the] father of` → `[el] padre de` /
  `[o] pai de`.
- Read person, gender and number from `morph`, since English "you" and
  "your" hide them. Second person as the Bibles the app ships have it:
  Spanish as the Reina-Valera (tú, te, ti, tu; vosotros, os, vuestro),
  Portuguese as the Bíblia Livre / Almeida (tu, te, ti, teu/tua; vós,
  vos, vosso/vossa). Hebrew morph: segments split by `/`; `Sp2ms` is a
  pronoun suffix, 2nd person masculine singular (`p` plural, `f`
  feminine, `b` both); verbs `Vqi3ms` (stem, aspect, person, gender,
  number). Greek (Robinson): `P-2AS` (pronoun, 2nd person, accusative,
  singular), `V-AAI-3P` (aorist active indicative, 3rd plural).
- Verbs: the tense the English gives. Leave out a subject pronoun the
  verb's ending already shows (`they drank` → `bebieron` / `beberam`,
  `he covered` → `cubrió` / `cobriu`); keep one the English stresses as
  its own word (`You yourself` → `Tú mismo` / `Tu mesmo`).
- Names of people and places: the Reina-Valera 1909 spelling, modernized
  (Spanish), Almeida / Bíblia Livre (Portuguese), as the lexicon meaning
  spells them. `Yahweh` stays `Yahweh` in both. `God` → `Dios` / `Deus`,
  `Lord` → `Señor` / `Senhor`, `LORD` → `SEÑOR` / `SENHOR`.
- Theological terms: the usual evangelical/Protestant ones, the same in
  every batch (expiación / expiação, santificación / santificação, pacto /
  aliança, justicia / justiça). Non-denominational.
- Settled in batch 001, keep them: a hidden plural `master<s> his` →
  `su amo<s>` / `seu amo<s>`; Portuguese possessives without an article
  (`seu pai`, `em tua ira`) unless the article is bracketed; a supplied
  `[one]` may go (`un cruel`, `el que`), never `[varón]` / `[varão]`; master → amo, lord → señor / senhor,
  `Lord my` → `Señor mío` / `Senhor meu`; STEPBible's lone `!` (paragogic
  nun) and `?` stay as written.
- `<obj.>` (Hebrew's object marker) stays `<obj.>` in both languages.
  A question the English shows only by word order (`will we eat`) gets
  a question mark instead of an added word (no "acaso"): `¿comeremos?` /
  `comeremos?`.
- A bracketed plural ending: `animal[s]` → `animal[es]` / `animal[-ais]`.
- The same English gloss with the same morph gets the same translation
  everywhere in the batch; with another morph, follow the morph.
- A transliteration or a word spelled as in English that stays as it is
  ("eduth", "error"): keep it, add a note.
- A pronoun takes the case it has in the verse (owner's review, 19 November
  2026): an object is a clitic (`I have loved you` ὑμᾶς → `os` / `vos`,
  `him` → `lo` / `o`; a dative → `le`, `les` / `lhe`, `lhes`), the stressed
  form only after a preposition (`a | él`, `de | ti`), the subject form for
  the subject of an infinitive. A supplied pronoun appears once (`echa [lo]`,
  never `échala [la]`). Before `?` or `!` too (`crucifica | Lo!`, `¿Te?`).
  A preposition can sit further back (`hasta | también | vosotros`) or at
  the end of the previous gloss (`van delante | de vosotros`, `junto | a
  él`); a possessive genitive stays possessive (`de él` / `dele`). Follow
  the Spanish or Portuguese verb, not the Greek case: `se burlaban | de Él`,
  `seguir | Lo`, `preguntaron | Le`.
- Articles, adjectives, demonstratives and possessives agree with the
  Spanish or Portuguese noun, not with the Greek or Hebrew one (ἐντολὴ
  καινή → `un mandamiento nuevo`; ἡ πορνεία → `a imoralidade`). Every word
  of the noun phrase agrees, in number too (`<la> grande | <la> esta`,
  `de la | semana`); after the noun Spanish uses the full form (`el año |
  <el> tercero`, `corazón | malo`); `el agua`, `del arca`; fixed phrases
  stay (`de oro`, `de plata`).
- Where STEPBible's English contradicts the morphology or the lexicon
  (φαρμακειῶν "sorcerers"), follow the Hebrew or Greek and add a note.
  `Tools/StudyData/translations/glosses/audits/run.sh` applies the first two
  across every batch.
