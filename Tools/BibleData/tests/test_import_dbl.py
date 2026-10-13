"""Tests for import_dbl.py: python3 -m unittest discover Tools/BibleData/tests"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from import_dbl import Report, parse_metadata, parse_usx  # noqa: E402

USX3 = """<?xml version="1.0" encoding="utf-8"?>
<usx version="3.0">
  <book code="PSA" style="id">Sample</book>
  <para style="h">Psalms</para>
  <para style="mt1">Psalms</para>
  <chapter number="23" style="c" sid="PSA 23"/>
  <para style="d">A psalm of David.</para>
  <para style="q1"><verse number="1" style="v" sid="PSA 23:1"/>The <char style="nd">Lord</char> is my shepherd,<note caller="+" style="f"><char style="ft">Or keeper</char></note></para>
  <para style="q2">I lack nothing.<verse eid="PSA 23:1"/></para>
  <para style="q1"><verse number="2" style="v" sid="PSA 23:2"/>He makes me lie down<char style="va">3</char> in green pastures,<verse eid="PSA 23:2"/></para>
  <para style="b"/>
  <para style="s1">Comfort</para>
  <para style="q1"><verse number="3-4" style="v" sid="PSA 23:3-4"/>he refreshes my soul. Even though I walk<verse eid="PSA 23:3-4"/></para>
  <chapter eid="PSA 23"/>
</usx>"""

USX2 = """<usx version="2.5">
  <book code="JHN" style="id"/>
  <chapter number="3" style="c"/>
  <para style="s1">Jesus and Nicodemus</para>
  <para style="p"><verse number="16" style="v"/>For God so loved the world <char style="wj">that he gave</char> his one and only Son.<verse number="17" style="v"/>For God did not send his Son,</para>
  <para style="m">but to save the world.<note style="x" caller="-">Ref</note></para>
</usx>"""


class ParseTests(unittest.TestCase):
    def test_usx3_poetry_headings_bridges(self):
        report = Report()
        number, verses, headings, spans = parse_usx(USX3, report)
        self.assertEqual(number, 19)
        texts = {v.verse: v.text for v in verses}
        self.assertEqual(texts[1], "The LORD is my shepherd,\nI lack nothing.")
        self.assertEqual(texts[2], "He makes me lie down in green pastures,")
        self.assertEqual(texts[3], "he refreshes my soul. Even though I walk")
        self.assertTrue(all(v.poetry for v in verses))
        self.assertIn((19, 23, 1, "A psalm of David."), headings)
        self.assertIn((19, 23, 3, "Comfort"), headings)
        self.assertEqual(spans, [(19023003, 19023004)])
        self.assertTrue(verses[0].paragraph)
        self.assertFalse(verses[1].paragraph)
        self.assertTrue(verses[2].paragraph)  # after a stanza break
        self.assertEqual(report.warnings, [])

    def test_usx2_prose_and_notes(self):
        report = Report()
        _, verses, headings, spans = parse_usx(USX2, report)
        texts = {v.verse: v.text for v in verses}
        self.assertEqual(texts[16], "For God so loved the world that he gave his one and only Son.")
        self.assertEqual(texts[17], "For God did not send his Son, but to save the world.")
        self.assertEqual(headings, [(43, 3, 16, "Jesus and Nicodemus")])
        self.assertEqual(spans, [])
        self.assertTrue(verses[0].paragraph)
        self.assertFalse(verses[1].paragraph)

    def test_deuterocanon_is_left_out(self):
        report = Report()
        self.assertIsNone(parse_usx('<usx><book code="TOB" style="id"/></usx>', report))
        self.assertEqual(report.skipped_books, ["TOB"])

    def test_metadata(self):
        meta = parse_metadata("""<DBLMetadata id="abc123" revision="4" version="2.2">
          <identification><name>New International Version</name><nameLocal>New International Version</nameLocal>
            <abbreviation>NIV</abbreviation><abbreviationLocal>NIV</abbreviationLocal></identification>
          <language><iso>eng</iso></language>
          <copyright><fullStatement><statementContent type="xhtml"><p>Holy Bible, New International Version®, NIV® Copyright ©1973, 1978, 1984, 2011 by Biblica, Inc.®</p><p>Used by permission. All rights reserved worldwide.</p></statementContent></fullStatement></copyright>
        </DBLMetadata>""")
        self.assertEqual(meta["abbreviation"], "NIV")
        self.assertEqual(meta["language"], "en")
        self.assertTrue(meta["copyright"].startswith("Holy Bible, New International Version®"))
        self.assertTrue(meta["copyright"].endswith("All rights reserved worldwide."))
        self.assertEqual(meta["dbl_id"], "abc123")


if __name__ == "__main__":
    unittest.main()
