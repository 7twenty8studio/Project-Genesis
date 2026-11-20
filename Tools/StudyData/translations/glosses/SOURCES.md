# Sources, licences and credits for the translated glosses (VRS-6)

Recorded 19 November 2026, before any batch was translated. Owner's rule
(Gamaliel, 18 Nov 2026, 8:44 PM CT): use only sources whose existing
licences explicitly allow translation and redistribution; calling the result
Versely's translation doesn't replace the source's licence requirements.

## What is translated

Only the English glosses already in WordStudy.sqlite (`forms.gloss`), one
per Hebrew or Greek word in its verse. Each translated gloss stays attached
to the same word: the key is the word's Strong's number, morphology and
English gloss (glosses.py), so the Hebrew/Greek text, word order and
alignment are untouched. Nothing else from these files is translated.

| Data | Source | Licence | Translation and redistribution |
| --- | --- | --- | --- |
| Old Testament glosses | STEPBible-Data TAHOT (Translators Amalgamated Hebrew OT), "English translation" column | CC BY 4.0 (file header and repository README) | Allowed: CC BY 4.0 permits adapting (including translating) and sharing, commercially too, with attribution and a note of changes. The file header also says the data may be sent "to AI servers without requesting permission". |
| New Testament glosses | STEPBible-Data TAGNT (Translators Amalgamated Greek NT), "English translation" column | CC BY 4.0 (file header and README) | Allowed, as above. TAGNT says its English is "Based on Berean Study Bible, with permission, as at 1-July-2019 and adapted for this work"; the Berean Standard Bible text has since been dedicated to the public domain (CC0 1.0, "as of April 30, 2023", berean.bible/terms.htm), so no further permission sits behind it. That page asks that derivative works not use the Berean name: we don't. |
| Guide shown to the translator (not shipped by this step) | The lexicon's gloss in English, Spanish and Portuguese (WordStudy.sqlite lexicon, lexicon_translations; VRS-8) | STEPBible TBESH/TBESG and Open Scriptures HebrewLexicon, CC BY 4.0; Strong (1890) and Abbott-Smith (1922) public domain | Already credited in LICENSE.txt. |

Not used, pending the owner's written confirmation of their terms:
- Global Bible Tools' Spanish and Portuguese glosses (its site states CC0
  for the English glosses only).
- TAGNT's "Spanish translation" column (from OpenGNT / Marvel Bible,
  CC BY-SA 4.0 upstream). The export reads only `forms.gloss` (TAHOT's and
  TAGNT's English), never that column.

## Pinned upstream (reproducible)

The English glosses are WordStudy.sqlite's `forms.gloss`, built on
7 October 2026 by build_wordstudy.py from STEPBible-Data commit
**95927044f33c540073246306cea5b13f5a16eb02** (6 Oct 2026, "6-Oct-2026"),
https://github.com/STEPBible/STEPBible-Data/tree/95927044f33c540073246306cea5b13f5a16eb02.
Checked 19 Nov 2026: build_wordstudy.py's readers on that commit give
exactly the 114,121 (Strong's, morphology, gloss) units in WordStudy.sqlite
(none missing, none extra). The same holds for e95d84df (3 Oct) and
902681f7 (5 Oct); the next commit, 5de0a47f (2 Nov, "Licence summary
clarified"), differs by one TAGNT gloss (G2192 V-PAP-GPM "are"), so the
data is not from it.

SHA-256 of the files at that commit, folder "Translators Amalgamated OT+NT":

| File | SHA-256 |
| --- | --- |
| TAHOT Gen-Deu - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt | e9b8546ee48fe0bfc57c3b70f5f40e98d96580e803526d19026224e31753368b |
| TAHOT Jos-Est - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt | 195fee1dc3653bab33701f170734eb894ed647c10cd08cc61749375fe8b73775 |
| TAHOT Job-Sng - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt | bb508af3af07822fca84cc43a0eba79eb70eecf672aabc0245b8d8cecf329d96 |
| TAHOT Isa-Mal - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt | f3ded203d2a74d6368932c97ae550d1d0754b271af491dc0dedf36fe3ba0bcc5 |
| TAGNT Mat-Jhn - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt | ab8eaaeb68e17a1dcfa34e1e9350358f22f03bc2a97244d848750ad81044bc8e |
| TAGNT Act-Rev - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt | 524e32375361e6d3fa2f7ef00b87605fdc4317a762f395651a05fdc31ad031b7 |

Licence statements, as read at that commit: each file's header ("Data
created by www.STEPBible.org based on work at Tyndale House Cambridge (CC BY
4.0)", allowing use "in software or publications and send it to AI servers
without requesting permission") and README.md ("STEPBible Data Repository
CC BY 4.0"). TAGNT's header: "English Based on Berean Study Bible, with
permission, as at 1-July02019 and adapted for this work."
Berean Standard Bible terms: https://berean.bible/terms.htm, read 19 Nov
2026 (page dated 30 April 2023): "The Berean Bible and Majority Bible texts
are officially dedicated to the public domain (CC0 1.0) as of April 30,
2023."

To reproduce: clone STEPBible-Data, check out the commit, compare the
SHA-256 values above, and run the readers in build_wordstudy.py
(hebrew_words, greek_words) to list the (Strong's, morphology, gloss)
units; glosses.py's ids are the first 16 hex digits of SHA-256 of
"strongs\x1fmorph\x1fgloss".

## Required credits (CC BY 4.0, and STEPBible's own request)

- Attribute the data to Tyndale House and STEPBible.org, with a link to
  STEPBible.github.io/STEPBible-Data (STEPBible: "Credit it to STEP Bible
  linked to www.STEPBible.org").
- Name the licence, CC BY 4.0, with its link.
- Say what was changed: translated into Spanish and Brazilian Portuguese
  with AI assistance by Versely, not reviewed or endorsed by STEPBible or
  Tyndale House.
- Don't imply endorsement; don't post copies of STEPBible's data files
  themselves (we ship a derived database, not their files).

Where the credits appear:
- In the app: `OriginalGlosses.attribution` under translated glosses (the
  Original header's source sheet, the word sheet, Word Study), with
  `OriginalGlosses.translatedNote` ("…Not Scripture.").
- Genesis/Resources/Study/LICENSE.txt (Glosses.sqlite section).
- Glosses.sqlite `meta` table (source, licence, changes).

## Review

Translators flag any gloss whose meaning is uncertain (a rare word, a
disputed sense, an idiom, a name whose identification is unsure) in the
batch's `uncertain` map; glosses.py lists them in `<lang>/review/NNN.md`
as AWAITING QUALIFIED REVIEW. Passing the structural checks never marks
one reviewed: only a qualified reviewer's sign-off in `reviewed.json`
(id → who and when, edited by hand) does. Until then Glosses.sqlite
carries them in `awaiting`, and the app shows the gloss with "(?)" and,
on the word sheet, "This meaning is uncertain and awaits review by a
qualified reviewer." The owner can hold any of them back.

Glosses that need their verse (supplied verbs like "[was]", modals, the
question particle, uncertain meanings, words whose sense moves) are read
in every verse they appear in (`glosses.py context`) and listed in
`checked`; where verses need different words, each gets its own
(`occurrences`, by verse and word position), so one translation never
covers verses that disagree.
