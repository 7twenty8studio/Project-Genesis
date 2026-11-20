# Bíblia Livre: words split in the published text

The owner's decision (20 November 2026): keep the publisher's text
verbatim, document the affected verses and report them to eBible.org.
These spacing slips don't block app testing.

## What happens
In eBible.org's USFX (`porbr2018_usfx.xml`, the February 2018 edition,
from ebible.org/Scriptures/porbr2018_usfx.zip) a contraction is cut in two
where an `<add>` (supplied words) mark begins or ends, with a line break in
between, for example:

    Senhor, dá-nos sempre⏎<add>d</add> este pão.      (John 6:34)
    Livrando-te d⏎<add>este</add> povo,                (Acts 26:17)

XML reads the line break as a space, so every reader of the file, eBible's
own pages included, gets "d este" for "deste". Versely's build
(Tools/BibleData/build_bibles.py) copies it as it stands.

## The 22 verses (`split_contractions.json`)

| Verse | Published | Meant | Context |
|---|---|---|---|
| Psalms 17:13 | d as | das | …, derruba-o; livra minha alma d as mãos do perverso co… |
| Psalms 17:14 | n esta | nesta | …são do mundo, cuja parte está n esta vida, cujo ventre e… |
| Psalms 22:10 | d o | do | …ançado sobre ti desde que saí d o útero; desde o vent… |
| Psalms 95:10 | d esta | desta | …ta anos aguentei com desgosto d esta geração, e disse: E… |
| Psalms 102:3 | n um | num | …ossos se têm se queimado como n um forno.… |
| Proverbs 10:17 | d aquele | daquele | …O caminho para a vida é d aquele que guarda a correç… |
| Ecclesiastes 8:8 | d esta | desta | …a morte, nem meios de escapar d esta guerra; nem a perve… |
| Isaiah 5:23 | d os | dos | …Ai d os que inocentam o per… |
| Isaiah 14:32 | d aquela | daquela | …se responderá aos mensageiros d aquela nação? Que o SENHOR… |
| Mark 6:11 | d aquela | daquela | … no dia do juízo, do que a os d aquela cidade.… |
| Luke 21:34 | d esta | desta | …mbriaguez, e das preocupações d esta vida; e vos venha a… |
| John 4:54 | d a | da | …ltou a fazer, quando ele veio d a Judeia a Galileia.… |
| John 6:34 | d este | deste | …e pois: Senhor, dá-nos sempre d este pão.… |
| Acts 1:15 | d aqueles | daqueles | …E em algum d aqueles dias, havendo uma m… |
| Acts 13:14 | n um | num | …ia; e ao entrarem na sinagoga n um dia de sábado, sent… |
| Acts 21:1 | n o | no | …iretamente, e viemos a Cós, e n o dia seguinte a Rode… |
| Acts 21:8 | n o | no | …E n o dia seguinte, Paulo… |
| Acts 21:18 | n o | no | …E n o dia seguinte, Paulo… |
| Acts 23:11 | n a | na | …E n a noite seguinte o Se… |
| Acts 26:17 | d este | deste | …Livrando-te d este povo, e dos gentios… |
| 2 Corinthians 12:5 | D este | Deste | …D este tal eu me orgulhare… |
| Revelation 9:17 | n esta | nesta | …E assim eu vi os cavalos n esta visão; e os que cav… |

Possibly related, for the publisher to judge (left out of the list,
because "a os" is also correct Portuguese, as in Jeremiah 36:25 "recusou a
os ouvir"): "a os" where "aos" seems meant in Joshua 24:15, Ruth 3:2, 1 Chronicles 15:11, 16:42, 17:5, 17:6, 21:2, 21:7,
23:2, 23:6, 25:1, 26:21, 29:25, Psalms 16:3, Isaiah 57:18 and Mark 6:11
(twice).

## Where Versely quotes these verses
- Matthew Henry, section 3334 (John 6:34): the Portuguese quotation is
  written "deste" and marked translated, since the Bible's words read
  "d este".
- Matthew Henry, section 1424 (Psalm 17:14): quoted "cuja parte está …
  esta vida", leaving out the split "n".

## When a corrected source arrives
1. Rebuild BLIVRE (`package_translation.py --id BLIVRE`) and copy the
   .sqlite to Genesis/Resources/Bibles/BLIVRE.sqlite.
2. Update the catalog row (supabase/catalog/portuguese_bibles.sql:
   file_bytes, database_bytes, sha256, a new version and file name).
3. Run `python3 -m unittest discover Tools/BibleData/tests`: the split test
   fails until `split_contractions.json` lists what is left.
4. Re-export the commentary and Easton/Nave's quotes (`commentary.py
   export`, `bios.py export`, `naves.py export`), answer the quotations of
   the verses above again (3334 can then quote the Bible's own words), and
   run their checks.

Draft report for eBible.org: UPSTREAM_REPORT.md (not sent).
