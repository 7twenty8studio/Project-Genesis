# Notes to review (Matthew Henry's Concise Commentary)

Translation in progress: see `commentary.py status`. Every section's own
quotes, flags and notes are in `<lang>/review/NNN.md`; these are the
decisions across batches.

## Editorial notes: paused (owner, 19 November 2026)
The owner paused every passage-specific editorial note, the ones approved
earlier included (Genesis 9 too): Henry's commentary ships complete and
faithful in English, Spanish and Portuguese, with the translation labels
and source credits, and the general About This Commentary sheet explains
that it reflects his historical context and theological views. The review
(EDITORIAL_REVIEW.md) and the proposed notes (`editorial-proposed.json`,
65 notes) are kept for a later decision; nothing reads them now. To ship
them later, rename the file back to `editorial.json`: the builder only
loads that name, and the app shows whatever `editorial_notes` holds.

The record below is how the proposals were made.

### Proposed notes (Versely's, not Henry's)
`editorial-proposed.json` holds Versely's own notes, in English, Spanish and
Portuguese. `add_commentary_translations.py` puts them in WordStudy.sqlite's
`editorial_notes`, and the app shows each before its paragraph in a
callout of its own (`EditorialNoteView`), set apart from Henry's words.
Henry's text itself is never changed or cut for them.

- Genesis 9:20-29, section 47 (Noah curses Canaan). Henry ties the curse to
  Africa and to "the poor negroes" sold as slaves. He also condemns the
  slave trade ("God has not commanded us to enslave negroes"). Owner's
  decision, 18 November 2026: keep the historical text whole, his
  condemnation included, translated faithfully, and put this note before
  the paragraph in all three languages:
  "Editorial note: This historical commentary contains racist language
  and links African enslavement to Noah's curse on Canaan. Versely rejects
  that interpretation and any use of Scripture to justify slavery or
  racial hierarchy."

## Further notes (owner, 19 November 2026)
The owner approved, on the excerpts in EDITORIAL_REVIEW.md:
- **B, a rule rather than a list**: the note goes before the paragraph
  wherever Henry extends blame to Jewish people collectively, including
  later generations or Jewish people of his own time. References to
  particular people of the biblical story (the Pharisees, the crowd before
  Pilate, Paul's opponents in Acts), ordinary doctrinal disagreement and
  discussion of the biblical text (Israel's sins in the Old Testament
  narrative, Paul's own argument in Romans 9-11) are reviewed in context
  and get no note. Wording (owner's): "Editorial note: Henry interprets
  this passage as assigning collective guilt or divine punishment to the
  Jewish people. Versely rejects collective blame against Jewish people,
  including blame for Christ's death, and any use of this commentary to
  justify antisemitism or discrimination."
- **A, C and D** as proposed, only where the paragraph supports the
  wording. A in American spelling ("skin color"), as the app's English is.
- **Ebed-melech** (section 2617, Jeremiah 38): a note of its own, since
  the A note would misdescribe it.
- Henry's text stays complete, his condemnations of mistreatment included
  (section 47's of the slave trade; 2849 on the contempt shown to Jews).
- A general historical introduction on the commentary's About sheet
  (`CommentaryAboutSheet`).

How B was applied: every sentence of the English naming Jews or the
Jewish nation or church was read (Tools/StudyData scan, about 440
sentences); a note was added where Henry carries guilt or punishment to
the people as a whole, beyond the biblical scene (the fall of Jerusalem
in AD 70 as punishment of "the nation", "the scattered Jews around us",
"the present state of the Jews", "the Jews who murdered the prophets and
crucified Christ"). Reviewed and left without a note: 1544, 2345, 3296,
3316, 3411, 3437, 3450, 3453, 3454, 3482, 3485, 3500, 3509, 3521, 3531,
3548-3551, 3580-3585, 3590, 3591, intro 40, 45, 46 (the text or Paul's
argument followed closely, particular people, or both Jews and Gentiles
named together), and the Old Testament narrative of Israel.

Waiting for the owner: 2799 and 2809 (Daniel 8 and 12) speak of Islam
without the Turks, and 2809 of "the papal usurpation" without Antichrist,
so the approved D and C wording doesn't fit them as it stands; 3050
(Matthew 16, priestly absolution "blasphemous and absurd") fits no
approved note.

### Every note, by section and paragraph (from editorial.json)
| Section | Paragraph | Note | Where | Henry's words |
|---|---|---|---|---|
| 47 | 0 | Genesis 9 | Genesis 9:20-29, Noah curses Canaan | And of the poor negroes, how many every year are sold and bought, like beasts in the market… God has not comma |
| 187 | 0 | B | Judah. | Till Christ's coming, Judah possessed authority, but after his crucifixion this was shortened, and according t |
| 468 | 0 | C | Balaam's prophecies. | Here is a prophecy that looks as far forward as to the Greeks and Romans. |
| 584 | 0 | B | The curses for disobedience. | Many judgments are here stated, which would be the fruits of the curse, and with which God would punish the pe |
| 585 | 0 | B | Their ruin, if disobedient. | Observe what is here said of the wrath of God, which should come and remain upon the Israelites for their sins |
| 589 | 0 | B | Secret things belong unto God. | Moses ends his prophecy of the Jews' rejection, just as St. |
| 602 | 0 | B | Deserved vengeance withheld. | The idolatry and rebellions of Israel deserved, and the justice of God seemed to demand, that they should be r |
| 1306 | 0 | B | Job speaks of the wisdom and power of God. | Let us remark what beautiful illustrations there are in the word of God, confirming his sovereignty, and wisdo |
| 2307 | 0 | A | 22001002 | The spouse was black as the tents of the wandering Arabs, but comely as the magnificent curtains in the palace |
| 2344 | 0 | B | 23005024 | When God designs the ruin of a provoking people, he can find instruments to be employed in it, as he sent for  |
| 2395 | 0 | B | 23027006 | In the days of the gospel, the latter days, the gospel church shall be more firmly fixed than the Jewish churc |
| 2410 | 0 | B | 23032009 | The present state of the Jews shall continue until a more abundant pouring out of the Spirit from on high. |
| 2432 | 0 | B | 23042018 | This fully came to pass in the destruction of the Jewish nation. |
| 2451 | 0 | B | 23049001 | The unbelief and rejection of the Jews. |
| 2456 | 0 | B | 23050001 | The rejection of the Jews. |
| 2499 | 0 | B | 23065001 | The calling of the Gentiles, and the rejection of the Jews. |
| 2547 | 0 | A | 24013018 | We cannot alter the natural colour of the skin; and so is it morally impossible to reclaim and reform these pe |
| 2578 | 1 | B | 24024001 | the Spirit of prophecy may here look forward to the dispersion of the unbelieving Jews, in all the nations of  |
| 2617 | 1 | A2 | 24038001 | Ebed-melech was an Ethiopian; yet he spoke to the king faithfully, These men have done ill in all they have do |
| 2721 | 0 | B | 26021018 | By the Spirit of prophecy Ezekiel foresaw Nebuchadnezzar's march from Babylon, which he would determine by div |
| 2763 | 0 | B | 26039023 | When the Lord shall have mercy on the whole house of Israel, by converting them to Christianity, and when they |
| 2798 | 0 | C | 27007015 | Here is foretold the rage of papal Rome against true Christians. |
| 2803 | 0 | B | 27009020 | It shows that the Jews are guilty of most obstinate unbelief, in expecting another Messiah, so long after the  |
| 2807 | 0 | C | 27011031 | Reference seems to be made to the Roman empire, the fourth monarchy, in its pagan, early Christian, and papal  |
| 2831 | 0 | B | 28009011 | The Divine wrath dries up the root, and withers the fruit of all comforts; and the scattered Jews daily warn u |
| 2920 | 0 | B | Encouragement to look for mercy. | The preaching of the gospel is predicted, when vengeance would be executed on the Jewish nation. |
| 2924 | 0 | B | Greater glory promised to the second temple than to the first. | Encouragement is given the Jews to go on in the work notwithstanding. |
| 2939 | 0 | B | The vision of a woman and an ephah. | This betokened the Jewish nation. |
| 2951 | 0 | B | Destruction to come upon the Jews. | In figurative expressions, that destruction of Jerusalem, and of the Jewish church and nation, is foretold, wh |
| 2952 | 0 | B | The Lord's dealing with the Jews. | Christ came into this world for judgment to the Jewish church and nation, which were wretchedly corrupt and de |
| 2956 | 0 | B | The Fountain for the remission of sins, The conviction of the false prophets. | In the time mentioned at the close of the foregoing chapter, a fountain would be opened to the rulers and peop |
| 2957 | 0 | B | The death of Christ, and the saving of a remnant of the people. | Because of the sin of the Jews in rejecting and crucifying Christ, and in opposing his gospel, the Romans woul |
| 2958 | 0 | B | The sufferings of Jerusalem. | He ascended from thence to heaven, and then desolations and distresses came upon the Jewish nation. |
| 2969 | 0 | B | Regard to be had to the law; John the Baptist promised as the forerunner of Messiah. | The Jewish nation, by wickedness, laid themselves open to the curse. |
| 3025 | 0 | B | The perverseness of the Jews. | Christ knew that the hearts of the Jews were more bitter and hardened against his miracles and doctrines, than |
| 3033 | 0 | B | The scribes and Pharisees reproved for seeking a sign. | The Ninevites would shame the Jews for not repenting; the queen of Sheba, for not believing in Christ. |
| 3072 | 0 | B | 40021018 | This represents the state of the nation and people of the Jews in particular. |
| 3075 | 0 | B | The parable of the wicked husbandmen. | This parable plainly sets forth the sin and ruin of the Jewish nation; and what is spoken to convict them, is  |
| 3076 | 0 | B | The parable of the marriage feast. | The guests first invited were the Jews. |
| 3083 | 0 | B | The guilt of Jerusalem. | The present dispersion and unbelief of the Jews, and their future conversion to Christ, were here foretold. |
| 3085 | 0 | B | The troubles before the destruction of Jerusalem. | The prophecy first respects events near at hand, the destruction of Jerusalem, the end of the Jewish church an |
| 3086 | 0 | B | Christ foretells other signs and miseries, to the end of the world. | The elect of God are scattered abroad; there are some in all places, and all nations; but when that great gath |
| 3102 | 0 | B | Christ before Pilate. | The Jews were so bent upon the death of Christ, that Pilate thought it would be dangerous to refuse. |
| 3160 | 0 | B | 41011012 | It was a figure of the doom upon the Jewish church, to which he came seeking fruit, but found none. |
| 3161 | 0 | B | Prayer in faith. | The disciples could not think why that fig-tree should so soon wither away; but all wither who reject Christ;  |
| 3163 | 0 | B | The parable of the vineyard and husbandmen. | Christ showed in parables, that he would lay aside the Jewish church. |
| 3171 | 0 | B | Christ's prophecy. | The Jews in rebelling against the Romans, and in persecuting the Christians, hastened their own ruin apace. |
| 3181 | 0 | B | Christ before Pilate. | By delivering up the King, they, in effect, delivered up the kingdom of God, which was, therefore, as by their |
| 3184 | 0 | B | The death of Christ. | The Jews were doing their utmost to extinguish the Sun of Righteousness. |
| 3251 | 0 | B | Parable of the barren fig-tree. | This parable in the first place refers to the nation and people of the Jews. |
| 3258 | 0 | B | Parable of the great supper. | This reproves the Jewish nation for their neglect of the offers of Christ's grace. |
| 3263 | 0 | B | The elder brother offended. | The Jews, in general, showed the same spirit towards the converted Gentiles; and numbers in every age object t |
| 3269 | 0 | B | Christ's kingdom. | The kingdom of God was among the Jews, or rather within some of them. |
| 3281 | 0 | B | The parable of the vineyard and husbandmen. | How many resemble the Jews who murdered the prophets and crucified Christ, in their enmity to God, and aversio |
| 3286 | 0 | B | His prophecy. | Having given an idea of the times for about thirty-eight years next to come, Christ shows what all those thing |
| 3287 | 0 | B | Christ exhorts to watchfulness. | He charges them to look upon the ruin of the Jewish nation as near. |
| 3349 | 0 | B | 43008021 | The Jews belonged to this present evil world, but Jesus was of a heavenly and Divine nature, so that his doctr |
| 3519 | 0 | B | Paul's account of his conversion. | Condemned sinners are struck blind by the power of darkness, and it is a lasting blindness, like that of the u |
| 3589 | 0 | B | The rejection of the Jews is not universal. | There was a chosen remnant of believing Jews, who had righteousness and life by faith in Jesus Christ. |
| 3813 | 0 | C | His destruction, and that of those who obey him. | It is supposed to be the power of the Roman empire, which the apostle did not mention more plainly at that tim |
| 3923 | 0 | B | The judgments of God denounced against rich unbelievers. | Above all their other crimes, the Jews had condemned and crucified that Just One who had come among them, even |
| 3939 | 0 | B | And the approaching end of the Jewish state, as a reason for sobriety, watchfulness, and prayer. | The destruction of the Jewish church and nation, foretold by our Saviour, was very near. |
| 4010 | 0 | D | The sixth trumpet is followed by the loosing of four angels bound in the great river Euphrates. | The sixth angel sounded, and here the power of the Turks seems the subject. |
| 4019 | 0 | C | A wild beast rises out of the sea, to whom the dragon gives his power. | The first beast then began to oppress and persecute the righteous for righteousness' sake, but they suffered m |
| 4034 | 0 | C | The lamentations over her. | Nor has this been peculiar to the Roman antichrist, and only her guilt. |

## How the app presents it (owner, 18 November 2026)
Henry's complete commentary, translated faithfully; nothing is left out
(any proposed omission goes to the owner first). Every section's footer
says "Matthew Henry (1662–1714): a historical commentary, one writer's
interpretation, not Scripture.", and a translated one also says
"Translated from Matthew Henry's Concise Commentary. Not Scripture."
The RV1909 / Bíblia Livre words a translated section quotes (each checked
verbatim, `commentary_quotations`) are set in italics, with the credit:
"Scripture in italics: Reina-Valera 1909 (public domain)." or "…: Bíblia
Livre (BLIVRE), © Diego Santos, Mario Sérgio and Marco Teles, February
2018, CC BY 4.0 Brasil." Editorial notes stay apart from Henry's text.
Passages proposed for further notes: EDITORIAL_REVIEW.md; decisions
above.

## Consistency pass (19 November 2026)
All 4,106 entries pass `commentary.py check` in both languages. Names
outside quotations now follow the app's glossary: Spanish "Gath" → Gat, "Monte Sion" → monte Sión; Portuguese
"Monte Sion" → monte Sião. Micás (Judges 17) and Miqueas (the prophet)
are different people and stay apart. Section 2991 quotes 1 Co 15:50
("flesh and blood shall not inherit"), not 1 Co 6:9 as listed: both
languages now use that verse's words.

The full AI review (20 November 2026, ai-review/README.md) put Spanish
"Bet-lehem" and "Bat-sheba" back where "Belén" and "Betsabé" had crept in:
they are the names the app's Study data uses.

### Reference correction: section 2991 (Matthew 5:38-42)
Henry writes "flesh and blood shall not inherit the kingdom of God". The
quote finder listed it against 1 Corinthians 6:9 ("the unrighteous shall
not inherit the kingdom of God"), but his words are 1 Corinthians 15:50.
The Spanish already used the RV1909's 15:50 ("la carne y la sangre no
pueden heredar el reino de Dios"); the Portuguese had taken 6:9's "não
herdarão o Reino de Deus" and now has the Bíblia Livre's 15:50, "não
podem herdar o Reino de Deus". Both quotes are marked "translated" with
the reason, since the listed verse is the wrong one; nothing in Henry's
English changed. "The Lord our Righteousness" is
the RV1909 / Bíblia Livre wording where Henry quotes Jer 23:6, and his
own phrase elsewhere. The Christian sabbath bracket stays at its first
use in each of the five sections, as decided, though in 3988 it follows
Henry's own "Lord's day".

## About This Commentary: which edition (owner, 19 November 2026)
The owner asked that "complete as he wrote it" be checked against the
edition. It isn't accurate: the text is Matthew Henry's Concise Commentary
on the Whole Bible (CrossWire SWORD module MHCC), a later abridgment of
his Exposition of the Old and New Testaments, which other ministers
completed from his notes after his death in 1714 (Romans to Revelation).
The sheet now names the Concise Commentary, calls it a later abridgment,
and says Versely shows this edition complete, with nothing left out. The
build drops only reference links and markup and adds section headings
from Henry's chapter outlines (LICENSE.txt); no words are cut.

## Terms (owner, 18 November 2026)
- "sabbath": sábado (both languages, as the Bibles have it).
- "Christian sabbath": sábado cristiano / sábado cristão, explained in
  brackets at its first use in each section (it appears in sections 9,
  518, 1573, 3417 and 3988): "[es decir, el domingo, el día del Señor]" /
  "[isto é, o domingo, o dia do Senhor]".
- "Lord's day", where Henry writes it: día del Señor / dia do Senhor.

## Source problems: fixed from an independent copy (20 November 2026)
The SWORD module MHCC (the build's English) lost lines, printed some lines
twice over the next one, swapped two lines (1427) and has misprints. 129
fixes in 120 sections restore what an independent transcription of the
Concise Commentary has (Internet Archive mhcc_20251130), and nothing else:
`source_fixes.json` (each with a reason), written into WordStudy.sqlite's
English by `commentary.fix_database` (add_commentary_translations.py runs
it). The es/pt translations of those sections were updated to the fixed
English (lost lines translated, translated duplicates removed) and their
source shas renewed; every one passes `commentary.py check`. Tests:
Tools/StudyData/test_commentary_fixes.py, WordStudyTests.commentarySourceFixesShip.

Still garbled because the independent copy has the same slip: 3392, 3416,
3559, 3591, 3664, 3665, 3697, 3920, 3952 and 4041 (ai-review/README.md).
