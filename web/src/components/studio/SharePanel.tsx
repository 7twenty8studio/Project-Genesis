"use client";

import QRCode from "qrcode";
import { useEffect, useState, type ReactNode } from "react";
import { config } from "@/config";
import { blankTexts, draftBlanks, type AnswersMode } from "@/lib/blanks";
import type { DraftRow } from "@/lib/draft";
import type { Translate } from "@/lib/i18n";
import type { Blocker } from "@/lib/studio";
import { Button, Notice } from "./ui";

type Props = {
  t: Translate;
  row: DraftRow;
  blockers: Blocker[];
  changedSincePublish: boolean;
  onPublish: () => Promise<{ ok: boolean; withheld?: number }>;
  onClose: (how: "unpublish" | "restrict") => Promise<boolean>;
  onDuplicate: () => Promise<void>;
  onDelete: () => Promise<void>;
  /** Opens the tab and puts the cursor on the field to fix (a `data-fix` name). */
  goTo: (tab: "outline" | "details", fix?: string) => void;
  /** Owner and admins: who looks after the sermon. */
  ownerSection?: ReactNode;
  /** The Answers setting (a draft detail: it applies when published). */
  onAnswers: (mode: AnswersMode) => void;
  /** Reveal Answers (or hide them again) for the revision readers have now. */
  onReveal: (reveal: boolean) => Promise<boolean>;
  /** The Answers setting of the copy readers have, when known. */
  publishedAnswers: AnswersMode | null;
};

/** Publish, the link and its QR code, and the closing actions (each takes effect at once). */
export function SharePanel({ t, row, blockers, changedSincePublish, onPublish, onClose, onDuplicate, onDelete, goTo, ownerSection, onAnswers, onReveal, publishedAnswers }: Props) {
  const link = `${config.siteUrl}/s/${row.slug}`;
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [qr, setQr] = useState<string | null>(null);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const published = row.status === "published";
  const blocking = blockers.filter((b) => b !== "saving");

  useEffect(() => {
    let live = true;
    QRCode.toDataURL(link, { errorCorrectionLevel: "M", margin: 2, width: 720, color: { dark: "#2d1d10", light: "#ffffff" } })
      .then((url) => live && setQr(url))
      .catch(() => live && setQr(null));
    return () => {
      live = false;
    };
  }, [link]);

  async function run(task: () => Promise<unknown>) {
    setBusy(true);
    setDone(null);
    try {
      await task();
    } finally {
      setBusy(false);
    }
  }

  // What to do, where it is, and the field Fix this puts the cursor on.
  const blockerText = (b: Blocker) =>
    b === "needs_title"
      ? { text: t("Give the sermon a title."), where: t("Details › Title"), tab: "details" as const, fix: "title" }
      : b === "empty_outline"
        ? { text: t("Add something to the outline."), where: t("Outline"), tab: "outline" as const, fix: "add" }
        : b === "needs_cover_alt"
          ? { text: t("Describe the cover picture, or mark it as decorative."), where: t("Details › Cover"), tab: "details" as const, fix: "cover-alt" }
          : b === "review_open"
            ? { text: t("Finish checking the import: keep, fix or remove each item it found."), where: t("Outline › Check the import"), tab: "outline" as const, fix: "review" }
            : b === "blanks"
              ? { text: t("Give every blank its answer, or make it an open blank."), where: t("Outline › Blanks"), tab: "outline" as const, fix: "blanks" }
              : { text: t("Fix the outline items marked in red."), where: t("Outline"), tab: "outline" as const, fix: "invalid" };
  const blankCount = row.draft_blocks.flatMap(blankTexts).flatMap(draftBlanks).length;
  const revealed = !!row.published_revision_id && row.answers_revealed_revision_id === row.published_revision_id;
  const manual = (publishedAnswers ?? row.answers) === "reveal";

  return (
    <div>
      <section aria-labelledby="publish-title" className="rounded-3xl border border-border bg-surface p-5">
        <h2 id="publish-title" className="text-lg font-semibold">
          {published ? (changedSincePublish ? t("Publish your changes") : t("Published")) : t("Publish")}
        </h2>
        <p className="mt-1 text-muted">
          {row.audience === "link" ? t("Anyone with the link can read it.") : t("Only church members can read it.")}{" "}
          <button type="button" className="font-medium text-accent underline underline-offset-4" onClick={() => goTo("details")}>
            {t("Change")}
          </button>
        </p>
        {blocking.length ? (
          <div id="publish-blockers" data-testid="publish-blockers" className="mt-4 rounded-2xl border-2 border-copper bg-surface-2 p-4">
            <p className="font-semibold">
              {blocking.length === 1 ? t("Publish is off until you finish this:") : t("Publish is off until you finish these {count} things:", { count: blocking.length })}
            </p>
            <ul className="mt-3 space-y-3">
              {blocking.map((b) => {
                const { text, where, tab, fix } = blockerText(b);
                return (
                  <li key={b} className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2">
                    <span className="min-w-0">
                      <span className="block font-medium">{text}</span>
                      <span className="block text-sm text-muted">{where}</span>
                    </span>
                    <Button onClick={() => goTo(tab, fix)} className="min-h-10 px-4 text-sm">
                      {t("Fix this")}
                    </Button>
                  </li>
                );
              })}
            </ul>
          </div>
        ) : null}
        <div className="mt-4">
          <Button
            primary
            aria-describedby={blocking.length ? "publish-blockers" : undefined}
            disabled={busy || blockers.length > 0 || (published && !changedSincePublish)}
            onClick={() =>
              run(async () => {
                const result = await onPublish();
                if (result.ok)
                  setDone(
                    result.withheld === 1
                      ? t("Published. One quotation from another translation shows as a reference only.")
                      : result.withheld
                      ? t("Published. {count} quotations from other translations show as references only.", { count: result.withheld })
                      : t("Published. The link is ready to share."),
                  );
              })
            }
          >
            {published ? t("Publish changes") : t("Publish")}
          </Button>
          {blockers.includes("saving") && blocking.length === 0 ? <span className="ml-3 text-sm text-muted">{t("Saving…")}</span> : null}
        </div>
        {done ? <Notice tone="status">{done}</Notice> : null}
      </section>

      {blankCount || published ? (
        <section aria-labelledby="answers-title" className="mt-6 rounded-3xl border border-border bg-surface p-5" data-testid="answers-section">
          <h2 id="answers-title" className="text-lg font-semibold">
            {t("Fill-in-the-blank answers")}
          </h2>
          <p className="mt-1 text-muted">
            {blankCount === 1
              ? t("The outline has 1 blank. Members fill it in as they listen, and their answers stay private.")
              : t("The outline has {count} blanks. Members fill them in as they listen, and their answers stay private.", { count: blankCount })}
          </p>
          <fieldset className="mt-3">
            <legend className="font-medium">{t("When can members check their answers?")}</legend>
            {(
              [
                ["reveal", t("After I reveal them"), t("The answers stay hidden until you choose Reveal Answers. Each time you publish changes, they're hidden again.")],
                ["now", t("Right away"), t("Members can check their answers as soon as the sermon is published.")],
                ["never", t("Never"), t("For blanks members fill in with their own words. Nothing is checked.")],
              ] as const
            ).map(([mode, label, hint]) => (
              <label key={mode} className="mt-2 flex items-start gap-3">
                <input type="radio" name="answers-mode" className="mt-1 size-5" checked={row.answers === mode} onChange={() => onAnswers(mode)} />
                <span>
                  <span className="block font-medium">{label}</span>
                  <span className="block text-sm text-muted">{hint}</span>
                </span>
              </label>
            ))}
            {published && publishedAnswers !== null && publishedAnswers !== row.answers ? (
              <p className="mt-2 text-sm text-muted">{t("This applies when you publish your changes.")}</p>
            ) : null}
          </fieldset>
          {published && manual ? (
            <div className="mt-4 flex flex-wrap items-center gap-3">
              <Button
                primary={!revealed}
                disabled={busy}
                onClick={() => run(async () => (await onReveal(!revealed)) && setDone(revealed ? t("The answers are hidden again.") : t("The answers are revealed. Members can check their blanks now.")))}
              >
                {revealed ? t("Hide Answers") : t("Reveal Answers")}
              </Button>
              <span className="text-sm text-muted">{revealed ? t("Members can check their answers now.") : t("The answers are hidden from members.")}</span>
            </div>
          ) : null}
        </section>
      ) : null}

      <section aria-labelledby="link-title" className="mt-6 rounded-3xl border border-border bg-surface p-5">
        <h2 id="link-title" className="text-lg font-semibold">
          {t("Link and QR code")}
        </h2>
        {!published ? <p className="mt-1 text-sm text-muted">{t("The link opens once the sermon is published.")}</p> : null}
        <div className="mt-3 flex flex-wrap items-center gap-2">
          <code className="min-w-0 break-all rounded-xl bg-surface-2 px-3 py-2 text-sm">{link}</code>
          <Button
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(link);
                setCopied(true);
                setTimeout(() => setCopied(false), 2000);
              } catch {
                setCopied(false);
              }
            }}
          >
            <span aria-live="polite">{copied ? t("Copied") : t("Copy link")}</span>
          </Button>
        </div>
        {qr ? (
          <div className="mt-4 flex flex-wrap items-end gap-4">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={qr} alt={t("QR code for {link}", { link })} width={180} height={180} className="rounded-2xl border border-border bg-white" />
            <a href={qr} download={`versely-sermon-${row.slug}.png`} className="inline-flex min-h-11 items-center rounded-full border border-border px-5 font-medium hover:bg-surface-2">
              {t("Download QR code")}
            </a>
          </div>
        ) : null}
      </section>

      {ownerSection}

      <section aria-labelledby="manage-title" className="mt-6 rounded-3xl border border-border bg-surface p-5">
        <h2 id="manage-title" className="text-lg font-semibold">
          {t("Manage")}
        </h2>
        <div className="mt-3 flex flex-wrap gap-2">
          {published && row.live_audience === "link" ? (
            <Button disabled={busy} onClick={() => run(async () => (await onClose("restrict")) && setDone(t("Now only church members can read it.")))}>
              {t("Members only now")}
            </Button>
          ) : null}
          {published ? (
            <Button disabled={busy} onClick={() => run(async () => (await onClose("unpublish")) && setDone(t("Unpublished. The link no longer opens it.")))}>
              {t("Unpublish")}
            </Button>
          ) : null}
          <Button disabled={busy} onClick={() => run(onDuplicate)}>
            {t("Duplicate for next week")}
          </Button>
          {confirmDelete ? (
            <>
              <Button danger disabled={busy} onClick={() => run(onDelete)}>
                {t("Delete for good")}
              </Button>
              <Button onClick={() => setConfirmDelete(false)}>{t("Cancel")}</Button>
            </>
          ) : (
            <Button danger disabled={busy} onClick={() => setConfirmDelete(true)}>
              {t("Delete")}
            </Button>
          )}
        </div>
        {confirmDelete ? <p className="mt-2 text-sm text-muted" role="alert">{t("Deleting removes the sermon and its link at once. This can't be undone.")}</p> : null}
        <p className="mt-3 text-sm text-muted">{t("Unpublishing, members only and deleting take effect at once, even for people who already have the page open: the next time it loads, it's gone.")}</p>
      </section>
    </div>
  );
}
