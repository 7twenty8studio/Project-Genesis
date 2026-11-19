#!/bin/sh
# The grammar audits of 19 November 2026 (owner's review of PR #33), in the
# order they ran. Each one reads the batches as they are and only changes
# what it finds, so running them again changes nothing once they're applied.
set -e
cd "$(dirname "$0")"
python3 cand.py        # Greek accusative pronouns, with the hand-checked infinitive cases (review.txt)
python3 manual.py      # the owner's examples and single fixes
python3 fix_pron.py    # accusative pronouns: clitic, stressed after a preposition, subject of an infinitive
python3 fix_pron2.py   # dative and genitive pronouns
python3 agree2.py --apply    # Greek articles, adjectives, demonstratives and possessives with their noun
python3 agree_heb.py --apply # Hebrew adjectives and demonstratives with their noun
python3 review_fixes.py  # the full review's corrections, place by place (review.jsonl)
python3 sweep.py && python3 sweep.py  # the review's patterns across every verse (twice: one fix can reveal another)
rm -f cand.json
cd ../../../../.. && python3 Tools/StudyData/glosses.py check es && python3 Tools/StudyData/glosses.py check pt
