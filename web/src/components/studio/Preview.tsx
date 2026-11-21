"use client";

import { SermonView } from "@/components/SermonView";
import type { DraftRow } from "@/lib/draft";
import { isLang, translator, type Lang, type Translate } from "@/lib/i18n";
import { previewSermon } from "@/lib/studio";

/** The draft as readers will see it, at phone width. Quoted words are already left out, as they will be. */
export function Preview({ lang, t, row, church }: { lang: Lang; t: Translate; row: DraftRow; church: string }) {
  const sermon = previewSermon(row, church);
  const pageLang = isLang(row.language) ? row.language : lang;
  return (
    <div>
      <p className="text-sm text-muted">{t("This is how the page will look on a phone once you publish. Nothing here is public yet.")}</p>
      <div className="mx-auto mt-4 w-full max-w-[400px] overflow-hidden rounded-[2.5rem] border-8 border-[#2d1d10] bg-background shadow-xl dark:border-[#46352a]">
        <div className="max-h-[760px] overflow-y-auto" tabIndex={0} aria-label={t("Preview")}>
          <SermonView sermon={sermon} lang={pageLang} t={translator(pageLang)} signedIn={false} preview={{ coverSrc: row.cover_id ? `/studio/${row.id}/cover?id=${row.cover_id}` : null }} />
        </div>
      </div>
    </div>
  );
}
