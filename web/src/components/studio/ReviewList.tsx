"use client";

import { newBlockID, type DraftBlock, type DraftRow } from "@/lib/draft";
import type { Translate } from "@/lib/i18n";
import { outlineWords } from "@/lib/import/completeness";
import { reviewDone, stillOpen, type Decision, type ReviewItem } from "@/lib/import/review";
import { placeFor } from "@/lib/studio";
import type { Review } from "./Editor";
import { scriptureLine } from "@/lib/import/lines";
import { convert } from "./OutlineEditor";
import { Button } from "./ui";

type Props = { t: Translate; review: Review; blocks: DraftBlock[]; language: DraftRow["language"]; onBlocks: (b: DraftBlock[]) => void; onReview: (r: Review | null) => void };

/** What the import didn't carry over, and what it left out on purpose. Publish waits for an answer to each. */
export function ReviewList({ t, review, blocks, language, onBlocks, onReview }: Props) {
  const items = stillOpen(review.items, blocks);
  const decide = (key: string, decision: Decision) => onReview({ ...review, decisions: { ...review.decisions, [key]: decision } });
  const done = reviewDone(items, review.decisions);
  const open = items.filter((i) => !(i.kind === "note" && i.note.count === 0) && !review.decisions[i.key]);

  return (
    <section aria-labelledby="review-title" className="mt-6 rounded-3xl border-2 border-accent bg-surface p-5">
      <h2 id="review-title" className="text-lg font-semibold">
        {t("Check the import")}
      </h2>
      <p className="mt-1 text-sm text-muted" aria-live="polite">
        {done ? t("Everything is checked. You can publish when you're ready.") : open.length === 1 ? t("One thing to check before publishing.") : t("{count} things to check before publishing.", { count: open.length })}
      </p>
      <ul className="mt-4 space-y-3">
        {items.map((item) => (
          <ReviewRow
            key={item.key}
            t={t}
            item={item}
            decision={review.decisions[item.key]}
            onDecide={(d) => decide(item.key, d)}
            onAddBack={(words) => {
              const at = placeFor(blocks, item.kind === "missing" ? item.before : [], (b) => outlineWords([b]));
              const block: DraftBlock = { id: newBlockID(), kind: "paragraph", text: words.join(" ") };
              onBlocks([...blocks.slice(0, at), block, ...blocks.slice(at)]);
              decide(item.key, "kept");
            }}
            onMakeScripture={(blockId) => onBlocks(blocks.map((b) => (b.id === blockId ? asScripture(b, language) : b)))}
          />
        ))}
      </ul>
      {done ? (
        <div className="mt-4">
          <Button onClick={() => onReview(null)}>{t("Close the check")}</Button>
        </div>
      ) : null}
    </section>
  );
}

function ReviewRow({ t, item, decision, onDecide, onAddBack, onMakeScripture }: { t: Translate; item: ReviewItem; decision?: Decision; onDecide: (d: Decision) => void; onAddBack: (words: string[]) => void; onMakeScripture: (blockId: string) => void }) {
  const answered = decision ? <span className="text-sm font-medium text-muted">{decision === "kept" ? t("Kept") : decision === "fixed" ? t("Fixed") : t("Left out")}</span> : null;
  if (item.kind === "missing") {
    return (
      <li className="rounded-2xl bg-surface-2 p-4">
        <p className="font-medium">{t("Not in the outline:")}</p>
        <p className="mt-1 font-serif">
          <span className="text-muted">…{item.before.join(" ")} </span>
          <mark className="rounded bg-[#f3d9b8] px-1 text-[#2d1d10]">{item.words.join(" ")}</mark>
          <span className="text-muted"> {item.after.join(" ")}…</span>
        </p>
        <div className="mt-3 flex flex-wrap items-center gap-2">
          {decision ? (
            answered
          ) : (
            <>
              <Button onClick={() => onAddBack(item.words)}>{t("Add it back")}</Button>
              <Button onClick={() => onDecide("fixed")}>{t("I fixed it")}</Button>
              <Button onClick={() => onDecide("dismissed")}>{t("Leave it out")}</Button>
            </>
          )}
        </div>
      </li>
    );
  }
  if (item.kind === "quotation") {
    return (
      <li className="rounded-2xl bg-surface-2 p-4">
        <p className="font-medium">{t("This may quote Scripture:")}</p>
        <p className="mt-1 font-serif">{item.text}</p>
        <p className="mt-2 text-sm text-muted">
          {t("Make it a Scripture reference so it opens in a Bible and only approved translations' words are shown. Keep it as written only if these are your own words.")}
        </p>
        <div className="mt-3 flex flex-wrap items-center gap-2">
          {decision ? (
            answered
          ) : (
            <>
              <Button onClick={() => onMakeScripture(item.blockId)}>{t("Make it a Scripture reference")}</Button>
              <Button onClick={() => onDecide("kept")}>{t("Keep as written")}</Button>
            </>
          )}
        </div>
      </li>
    );
  }
  if (item.kind === "reference") {
    return (
      <li className="rounded-2xl bg-surface-2 p-4">
        <p>{t("“{reference}” doesn't name verses Versely can open. Fix it in the outline, or keep it as written.", { reference: item.raw })}</p>
        <div className="mt-3 flex flex-wrap gap-2">{decision ? answered : <Button onClick={() => onDecide("kept")}>{t("Keep as written")}</Button>}</div>
      </li>
    );
  }
  const { kind, count } = item.note;
  const text =
    kind === "tables"
      ? t("Tables ({count}) became plain paragraphs, cell by cell.", { count })
      : kind === "images"
        ? t("Pictures ({count}) were left out. Add a cover in Details if you'd like one.", { count })
        : kind === "footnotes"
          ? t("Footnotes ({count}) were moved to the end of the outline.", { count })
          : kind === "hidden"
            ? t("Hidden text ({count}) was left out.", { count })
            : count
              ? t("Comments ({count}) were left out. They're never published.", { count })
              : t("Comments and speaker notes are never imported.");
  return (
    <li className="rounded-2xl bg-surface-2 p-4">
      <p>{text}</p>
      {count ? <div className="mt-3 flex flex-wrap gap-2">{decision ? answered : <Button onClick={() => onDecide("kept")}>{t("OK")}</Button>}</div> : null}
    </li>
  );
}

/** A possible quotation as a Scripture item: read as a verse where it can be, otherwise its first line becomes the reference to fix. */
function asScripture(block: DraftBlock, language: DraftRow["language"]): DraftBlock {
  const text = block.kind === "list" ? block.items.join("\n") : block.kind === "scripture" ? "" : block.text;
  const ref = text ? scriptureLine(text, { language }, true) : null;
  return ref ? { id: block.id, kind: "scripture", ref } : convert(block, "scripture", language);
}
