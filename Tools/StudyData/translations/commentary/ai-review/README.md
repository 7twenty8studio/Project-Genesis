# AI review of Matthew Henry in Spanish and Portuguese (20 November 2026)

**What this is:** a full AI review. Claude agents read every entry of all
102 batches (4,106 sections and introductions per language) against Henry's
English, fixed what was wrong and wrote one report per batch (`es/NNN.md`,
`pt/NNN.md`). **It is not a qualified human sign-off.** No theologian,
translator or native-speaker editor has reviewed this text yet, and the
items under "For a qualified reviewer" below are the ones that most need one.

## Result

| | Spanish (es) | Portuguese (pt-BR) |
|---|---|---|
| Entries read | 4,106 of 4,106 | 4,106 of 4,106 |
| Fixes in the batch reviews | 173 | 163 |
| Final pass (coordinator) | 10 | 8 |
| `commentary.py check` afterwards | 4,106 pass, 0 fail | 4,106 pass, 0 fail |
| "Christian sabbath" brackets | 5 (sections 9, 518, 1573, 3417, 3988) | the same 5 |

About half the fixes are meaning errors. The rest are grammar, garbled or
unnatural sentences, quotations and terms.

**Meaning errors** included:
- archaic English misread: "conversation" (conduct), "prevent" (go before),
  "secure" (careless), "pretend" (claim), "laid to their charge" (imputed),
  "suitors" (petitioners), "spared" (borne with);
- wrong referents;
- questions turned into statements;
- "by right" given as "by merit".

**Other fixes:**
- **Quotations:** an RV1909 or Bíblia Livre run was replaced or trimmed
  where it added words Henry doesn't have, or replaced his own word
  ("utter" vs "sudden").
- **Terms:** the sabbath rule (the bracket only for "Christian sabbath"),
  and "besta" for the beast.
- **Register:** Spanish usted/vosotros mixed inside one passage.
- **European Portuguese** forms replaced with Brazilian ones.

Nothing of Henry's was softened, cut or added to. The harsh passages are
translated in full and flagged "sensitive" in the batches. The owner paused
editorial notes on 19 November 2026, so none ship.

**Final pass:**
- Names aligned with the app's Study names: Spanish "Bet-lehem" (was
  "Belén" in 7 sections) and "Bat-sheba" (was "Betsabé").
- Portuguese "o Senhor, nossa Justiça" made the same everywhere.
- Section 1403's broken English marked "[…]" in Portuguese, as in Spanish.
- Section 1447 in Portuguese fixed ("não temos menos benefício").
- Section 3807 in Portuguese: "preventing mercies" now reads "que se nos
  antecipam".

## For a qualified reviewer

### 1. Henry's harsh passages

These are kept complete, as Henry wrote them. A reviewer should read them
in both languages: they cover the Jews collectively, Roman Catholic
practice and the papacy as antichrist, Islam ("a poisonous and ruinous
religion"), women's subjection and silence, slavery, and "heathens".

The batch reports list them by section. The heaviest batches are 085, 087,
088, 093 and 101.

Two passages aren't flagged although they're similar to flagged ones:
- 3315 (devotion to Mary);
- 4001 and 4046 (saints and angels).

### 2. Garbled English, translated as it stands and flagged

- 1403
- 3392, 3416
- 3548 (has a repeated sentence)
- 3559: "upheld by the power of the enemy", almost certainly a slip
- 3591, 3664, 3665
- 3697: the Spanish and Portuguese are as incomplete as the English
- 3920, 3952, 4041

### 3. Henry's own slips, kept

- 3186: "the men ran" (Mark 16:8)
- 3413: Pilate spared the legs
- 3530: Agrippa governing Galilee
- 3542: Hebrews among the prison epistles
- 3902: "Babylon" for Jericho
- 3267 and 3268: their titles appear swapped
- 3227 and 3256: each holds the next section's heading
- 1029: Elijah for Elisha, silently corrected

### 4. Choices to settle once, for the whole commentary

- **Spanish address to the reader:** most batches use vosotros. Batches
  066–070 and 077–079 use ustedes. Each batch is consistent within itself.
- **The apostle Paul's earlier name:** "Saulo" in Spanish (as Acts has it),
  while the king is "Saúl".
- **The epistle's author James:** "Santiago" in Spanish (the book's name in
  the RV1909) next to the glossary's "Jacobo".
- **Saint Paul in Portuguese:** "são Paulo" and "São Paulo" both appear.
- **"Pretender":** Portuguese keeps it where it reads as "claim" (an
  accepted sense). A reviewer may prefer "alegar" in more places.
- **3683, "the terror of the Lord":** the Bible's "temor" (fear) is used,
  which is softer than Henry's word.

### 5. Bible data

The bundled Bíblia Livre has a split "d este" at John 6:34. The quotation
in the commentary reads "deste" and is marked translated. The Bible file
itself should be fixed at the source.

### 6. Flags

A few translator flags describe wording that has since been fixed:
- es 3760, 3844, 3856, 3893 and 025 (Betsabé);
- pt 1447.

Flags are review notes, not shown in the app.

## Not done here

The owner's Mac build and Swift tests have not been run on this branch.
