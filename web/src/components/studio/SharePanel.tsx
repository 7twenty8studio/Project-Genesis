"use client";

import QRCode from "qrcode";
import { useEffect, useState, type ReactNode } from "react";
import { config } from "@/config";
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
  goTo: (tab: "outline" | "details") => void;
  /** Owner and admins: who looks after the sermon. */
  ownerSection?: ReactNode;
};

/** Publish, the link and its QR code, and the closing actions (each takes effect at once). */
export function SharePanel({ t, row, blockers, changedSincePublish, onPublish, onClose, onDuplicate, onDelete, goTo, ownerSection }: Props) {
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

  const blockerText = (b: Blocker) =>
    b === "needs_title"
      ? { text: t("Give the sermon a title."), tab: "details" as const }
      : b === "empty_outline"
        ? { text: t("Add something to the outline."), tab: "outline" as const }
        : b === "needs_cover_alt"
          ? { text: t("Describe the cover picture, or mark it as decorative."), tab: "details" as const }
          : b === "review_open"
            ? { text: t("Finish checking the import."), tab: "outline" as const }
            : { text: t("Fix the outline items marked in red."), tab: "outline" as const };

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
          <div className="mt-4">
            <p className="font-medium">{t("Before publishing:")}</p>
            <ul className="mt-2 space-y-1">
              {blocking.map((b) => {
                const { text, tab } = blockerText(b);
                return (
                  <li key={b}>
                    <button type="button" className="text-left text-accent underline underline-offset-4" onClick={() => goTo(tab)}>
                      {text}
                    </button>
                  </li>
                );
              })}
            </ul>
          </div>
        ) : null}
        <div className="mt-4">
          <Button
            primary
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
