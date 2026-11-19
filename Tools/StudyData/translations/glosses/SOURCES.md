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
for qualified review. They still ship, labelled as translated study
notes; the owner can hold any of them back.
