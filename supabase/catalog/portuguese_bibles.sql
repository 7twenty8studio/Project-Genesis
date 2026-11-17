-- Versely: Brazilian Portuguese Bibles (VRS-3). NOT a migration: run it in
-- the SQL Editor when the version with Portuguese screens is released, so
-- people on older versions don't see Portuguese Bibles before the app is
-- ready for them. Safe to run twice.
--
-- Older builds read the same rows (they select enabled rows and send no
-- version), so once this runs they list these Bibles too. Checked on
-- 17 November 2026 that they cope: the language column is free text and
-- "pt-PT" passes its check, rights 'licensed' is a value they know, and with
-- English screens their setup never picks a Portuguese Bible. They show
-- English book names around the Portuguese text, and their Premium tools
-- use the KJV beside a Portuguese YouVersion Bible.
--
-- Owner's choice (17 November 2026): every Portuguese Bible our YouVersion
-- Platform key may use, plus the Bíblia Livre as a catalog download.
--
-- 1. YouVersion Platform Bibles. Ids are the app's (2-8 letters or digits,
--    shown as the abbreviation; the Spanish NVI already has "NVI"). Copyright
--    statements exactly as the Platform's GET /v1/bibles/{id} gave them on
--    17 November 2026 (O Livro's "permissãod" is the Platform's own typo:
--    keep it, the statement is shown as given). Always free (LICENSED_BIBLES.md › 5).
insert into public.youversion_bibles (id, yvp_id, name, year, license, summary, language, approach, reading_level, popularity, enabled, sort, publisher_url)
values
  ('NVIPT', 129, E'Nova Versão Internacional', '2023',
   E'Bíblia Sagrada, Nova Versão Internacional®, NVI®\n© 1993, 2000, 2011, 2023 por Biblica, Inc.\nUsado com permissão. Todos os direitos reservados mundialmente.\nBíblia Sagrada, Nova Versão Internacional®, NVI®\nCopyright © 1993, 2000, 2011, 2023 by Biblica, Inc.\nUsed with permission. All rights reserved worldwide.',
   E'Uma tradução moderna, clara e fiel, das mais lidas no Brasil.',
   'pt', 'balanced', 'everyday', 1, true, 40, 'https://www.biblica.com'),
  ('NVI2011', 4360, E'Nova Versão Internacional 2011', '2011',
   E'Biblia Sagrada, Nova Versão Internacional®, NVI®\nCopyright © 1993, 2000, 2011 by Biblica, Inc.®\nAll rights reserved worldwide.',
   E'A edição de 2011 da NVI, para quem prefere o texto que já conhece.',
   'pt', 'balanced', 'everyday', 2, true, 41, 'https://www.biblica.com'),
  ('NBVP', 1966, E'Nova Bíblia Viva', '2007',
   E'Nova Bíblia Viva\nCopyright © 2007 por Biblica, Inc.®\nUsado com permissão da Biblica, Inc.® Todos os direitos reservados.',
   E'Uma paráfrase em português simples e atual, ótima para começar.',
   'pt', 'thought_for_thought', 'everyday', 4, true, 42, 'https://www.biblica.com'),
  ('BLT', 3254, E'Bíblia Livre Para Todos', '2018',
   E'Dr. Jonathan Gallagher. Lançado sob licença Creative Commons Atribuição-CompartilhaIgual 4.0 Não Adaptada. Para correções envie email para jonathangallagherfbv@gmail.com\nDr. Jonathan Gallagher. Released under Creative Commons Attribution-ShareAlike 4.0 Unported License. For corrections send email to jonathangallagherfbv@gmail.com',
   E'Uma tradução em linguagem simples, feita para todos entenderem.',
   'pt', 'thought_for_thought', 'everyday', 5, true, 43, null),
  ('OL', 1967, E'O Livro', '2017',
   E'O Livro\nCopyright © 1981, 1999, 2017 via Biblica, Inc.®\nUsado com permissãod da Biblica, Inc.®. Todos os direitos mundiais reservados.\nO Livro\nCopyright © 1981, 1999, 2017 by Biblica, Inc.®\nUsed by permission of Biblica, Inc.® All rights reserved worldwide.',
   E'Uma tradução em português de Portugal, numa linguagem viva e acessível.',
   'pt-PT', 'thought_for_thought', 'everyday', 1, true, 44, 'https://www.biblica.com')
on conflict (id) do nothing;

-- 2. The Bíblia Livre (BLIVRE): the Almeida of 1819 updated (Textus
--    Receptus), CC BY 4.0 Brasil, from ebible.org/Scriptures/porbr2018_usfx.zip.
--    Built by Tools/BibleData/package_translation.py --id BLIVRE (verbatim;
--    footnotes left out, psalm titles kept). Upload BLIVRE-1.sqlite.deflate to
--    the public "bibles" bucket first. Its licence (the credit the translators
--    ask for) is shown under every chapter. Being free and not from YouVersion,
--    it's the Bible a Portuguese iPhone starts in (and downloads in the
--    background if it's missing), and what Premium tools read in place of a
--    Portuguese YouVersion Bible (its licence is verified in the app,
--    OpenLicence.verified).
insert into public.bible_translations (id, name, year, license, summary, language, file_url, file_bytes, database_bytes, sha256, version, enabled, sort,
  approach, reading_level, rights, popularity, updated_at)
values ('BLIVRE', 'Bíblia Livre', '2018', 'Bíblia Livre (BLIVRE), Copyright © Diego Santos, Mario Sérgio, e Marco Teles, http://sites.google.com/site/biblialivre/ - fevereiro de 2018. Licença Creative Commons Atribuição 4.0 Brasil (http://creativecommons.org/licenses/by/4.0/br/). Texto sem as notas de rodapé.', 'A tradução de Almeida de 1819 atualizada para o português do Brasil, livre para ler e compartilhar.', 'pt', 'https://ulbpwygzwchsnvdeeife.supabase.co/storage/v1/object/public/bibles/BLIVRE-1.sqlite.deflate', 6480995, 12189696, '6b38fb73c1f07fc9d27e0022a8300fc628f5f518a7b8b9c90a9845f0ec596aa0', 1, true, 40,
  'word_for_word', 'traditional', 'licensed', 3, now())
on conflict (id) do update set name = excluded.name, year = excluded.year, license = excluded.license, summary = excluded.summary, language = excluded.language,
  file_url = excluded.file_url, file_bytes = excluded.file_bytes, database_bytes = excluded.database_bytes, sha256 = excluded.sha256,
  version = excluded.version, enabled = excluded.enabled, sort = excluded.sort,
  approach = excluded.approach, reading_level = excluded.reading_level, rights = excluded.rights, popularity = excluded.popularity, updated_at = now();
