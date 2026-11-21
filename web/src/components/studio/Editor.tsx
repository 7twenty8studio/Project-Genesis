"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { closeSermon, deleteSermon, duplicateSermon, publishSermon, saveSermon, uploadSermonCover } from "@/app/studio/actions";
import { draftProblems, type DraftBlock, type DraftDetails, type DraftRow } from "@/lib/draft";
import { translator, type Lang } from "@/lib/i18n";
import type { DraftReview } from "@/lib/import/review";
import { afterClose, publishBlockers, refusalMessage } from "@/lib/studio";
import { DetailsForm } from "./DetailsForm";
import { OutlineEditor } from "./OutlineEditor";
import { Preview } from "./Preview";
import { SharePanel } from "./SharePanel";
import { StatusBadge } from "./StatusBadge";
import { Notice } from "./ui";

export type Review = DraftReview;
type SaveState = "saved" | "unsaved" | "saving" | "error" | "conflict" | "invalid";
const TABS = ["outline", "details", "share"] as const;
type Tab = (typeof TABS)[number];

function detailsOf(row: DraftRow): Partial<DraftDetails> & { cover: string | null } {
  return {
    title: row.title,
    speaker: row.speaker,
    series: row.series,
    preached_on: row.preached_on,
    time_zone: row.time_zone,
    location: row.location,
    language: row.language,
    audience: row.audience,
    cover: row.cover_id,
    cover_alt: row.cover_alt,
    cover_decorative: row.cover_decorative,
  };
}

/**
 * One sermon in Church Studio: Outline (import, edit), Details (prepare,
 * cover), Preview (phone width) and Share (publish, link, QR). Changes save
 * by themselves a moment after typing stops, always against the version
 * this page loaded, so two editors never overwrite each other.
 */
export function Editor({ lang, initial, church }: { lang: Lang; initial: DraftRow & { published_draft_version: number | null }; church: string }) {
  const t = translator(lang);
  const [row, setRow] = useState<DraftRow>(initial);
  const [tab, setTab] = useState<Tab>("outline");
  // Phones: Edit or Preview (on a wide screen the preview is always beside the editor).
  const [view, setView] = useState<"edit" | "preview">("edit");
  const [state, setState] = useState<SaveState>("saved");
  const [error, setError] = useState<string | null>(null);
  // The import review lives with the draft: it follows the sermon to any computer and the database enforces it at Publish.
  const [review, setReviewState] = useState<Review | null>(initial.draft_review);
  const reviewDirty = useRef(false);
  const latestReview = useRef<Review | null>(initial.draft_review);

  const latest = useRef(row);
  useEffect(() => {
    latest.current = row;
  }, [row]);
  const version = useRef(initial.draft_version);
  // The same two versions as state, for what the page shows.
  const [shown, setShown] = useState({ current: initial.draft_version, published: initial.status === "published" ? initial.published_draft_version : null });
  const setVersion = useCallback((v: number, published?: number | null) => {
    version.current = v;
    setShown((s) => ({ current: v, published: published === undefined ? s.published : published }));
  }, []);
  const dirty = useRef(false);
  const conflict = useRef(false);
  const chain = useRef<Promise<boolean>>(Promise.resolve(true));
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // A new sermon takes this computer's time zone (read after hydration, so
  // the server's first render and the browser's agree); it's saved with the
  // next change.
  useEffect(() => {
    if (initial.time_zone !== null) return;
    const zone = guessTimeZone();
    if (zone) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setRow((r) => ({ ...r, time_zone: zone }));
      dirty.current = true;
    }
  }, [initial.time_zone]);

  const save = useCallback(async (): Promise<boolean> => {
    if (conflict.current) return false;
    if (!dirty.current) return true;
    dirty.current = false;
    const current = latest.current;
    // An outline the database would refuse isn't sent; the details still are.
    const invalid = draftProblems(current.draft_blocks).length > 0;
    setState("saving");
    const sendReview = reviewDirty.current;
    reviewDirty.current = false;
    const details = sendReview ? { ...detailsOf(current), review: latestReview.current } : detailsOf(current);
    const result = await saveSermon(current.id, version.current, details, invalid ? null : current.draft_blocks);
    if (result.ok) {
      setVersion(result.version);
      if (invalid) {
        dirty.current = true;
        setState("invalid");
        return false;
      }
      setState(dirty.current ? "unsaved" : "saved");
      setError(null);
      return true;
    }
    dirty.current = true;
    if (sendReview) reviewDirty.current = true;
    if (result.code === "draft_changed") conflict.current = true;
    setState(result.code === "draft_changed" ? "conflict" : "error");
    setError(t(refusalMessage(result.code)));
    return false;
  }, [t, setVersion]);

  /** Runs after every save already queued, so versions never cross. */
  const queue = useCallback(<T,>(task: () => Promise<T>): Promise<T> => {
    const next = chain.current.then(task);
    chain.current = next.then(
      () => true,
      () => false,
    );
    return next;
  }, []);

  const flush = useCallback(() => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
    return queue(save);
  }, [queue, save]);

  const change = useCallback(
    (update: Partial<DraftRow>) => {
      setRow((r) => ({ ...r, ...update }));
      dirty.current = true;
      setState((s) => (s === "conflict" ? s : "unsaved"));
      setError((e) => (conflict.current ? e : null));
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => void flush(), 1200);
    },
    [flush],
  );

  // Save before leaving; warn while a save is pending.
  useEffect(() => {
    const warn = (e: BeforeUnloadEvent) => {
      if (dirty.current && !conflict.current) {
        void flush();
        e.preventDefault();
      }
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [flush]);

  const setBlocks = useCallback((blocks: DraftBlock[]) => change({ draft_blocks: blocks }), [change]);

  const setReview = useCallback(
    (next: Review | null) => {
      latestReview.current = next;
      reviewDirty.current = true;
      setReviewState(next);
      change({});
    },
    [change],
  );

  async function uploadCover(jpeg: Blob): Promise<boolean> {
    return queue(async () => {
      await save();
      if (conflict.current) return false;
      const form = new FormData();
      form.set("sermon", row.id);
      form.set("version", String(version.current));
      form.set("cover", jpeg, "cover.jpg");
      const result = await uploadSermonCover(form);
      if (!result.ok) {
        setError(t(refusalMessage(result.code === "cover_not_jpeg" || result.code === "cover_upload_failed" ? "cover_missing" : result.code)));
        if (result.code === "draft_changed") {
          conflict.current = true;
          setState("conflict");
        }
        return false;
      }
      setVersion(result.version);
      setRow((r) => ({ ...r, cover_id: result.cover }));
      return true;
    });
  }

  async function publish(): Promise<{ ok: boolean; withheld?: number }> {
    const saved = await flush();
    if (!saved) return { ok: false };
    const result = await queue(() => publishSermon(row.id, version.current));
    if (!result.ok) {
      if (result.code === "draft_changed") {
        conflict.current = true;
        setState("conflict");
      }
      setError(t(refusalMessage(result.code)));
      return { ok: false };
    }
    setError(null);
    setRow((r) => ({ ...r, status: "published", live_audience: r.audience, published_at: new Date().toISOString(), hidden_at: null, published_revision_id: "published" }));
    setVersion(version.current, version.current);
    return { ok: true, withheld: result.withheld };
  }

  /**
   * Unpublish and Members only never wait on the draft being saved: they
   * change only what readers get, so they run even when a save failed.
   * The editor then takes the version they return and saves any pending
   * edit on it, but only when the version they moved on from is this
   * editor's own; if the draft changed elsewhere it stays in conflict (and
   * asks for a reload) rather than save its older copy on top.
   */
  async function close(how: "unpublish" | "restrict"): Promise<boolean> {
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
    // The version is taken (or the conflict set) inside the queued task, so
    // an autosave queued while the request is in flight runs on the version
    // it returned rather than the one it replaced.
    const outcome = await queue(async () => {
      const result = await closeSermon(row.id, how).catch(() => ({ ok: false as const, code: "network" }));
      if (!result.ok) return { ok: false as const, code: result.code };
      // What readers get changed either way; show it (and a queued save sends it).
      const closed = (r: DraftRow): DraftRow =>
        how === "unpublish"
          ? { ...r, status: r.status === "published" ? "unpublished" : r.status }
          : { ...r, audience: "members", live_audience: r.live_audience ? "members" : null };
      latest.current = closed(latest.current);
      setRow(closed);
      const decision = afterClose(result.previous, version.current, conflict.current);
      if (decision === "conflict") conflict.current = true;
      else setVersion(result.version, how === "unpublish" ? null : undefined);
      return { ok: true as const, decision };
    });
    if (!outcome.ok) {
      setError(t(refusalMessage(outcome.code)));
      return false;
    }
    if (outcome.decision === "conflict") {
      // Someone else saved a newer draft: keep the conflict check, never save this copy over it.
      setState("conflict");
      setError(t(refusalMessage("draft_changed")));
      return true;
    }
    if (dirty.current) {
      setState("unsaved");
      void flush();
    }
    return true;
  }

  async function duplicate() {
    await flush();
    const result = await duplicateSermon(row.id);
    if (result && !result.ok) setError(t(refusalMessage(result.code)));
  }

  async function remove() {
    const result = await deleteSermon(row.id);
    if (!result.ok) return setError(t(refusalMessage(result.code)));
    window.location.assign(`/studio?church=${row.group_id}`);
  }

  const saving = state === "saving" || state === "unsaved";
  const blockers = publishBlockers(row, review, saving);
  const changedSincePublish = row.status === "published" && (shown.published !== shown.current || state !== "saved");

  const status =
    state === "saved" ? t("All changes saved") : state === "saving" ? t("Saving…") : state === "unsaved" ? t("Not saved yet") : state === "conflict" ? t("Not saved: changed elsewhere") : state === "invalid" ? t("Outline not saved: fix the items marked in red") : t("Not saved");
  const label = (name: Tab) => (name === "outline" ? t("Outline") : name === "details" ? t("Details") : t("Publish"));

  return (
    <main className="mx-auto max-w-7xl px-4 pb-24 pt-6 sm:px-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div className="min-w-0">
          <Link href={`/studio?church=${row.group_id}`} className="text-sm font-medium uppercase tracking-wider text-accent underline-offset-4 hover:underline">
            {church}
          </Link>
          <h1 className="mt-1 min-w-0 text-3xl font-semibold tracking-tight">{row.title || t("Untitled sermon")}</h1>
        </div>
        <div className="flex items-center gap-3">
          <span className="inline-flex items-center gap-2 text-sm text-muted" role="status" aria-live="polite">
            <span aria-hidden="true" className={`h-2 w-2 rounded-full ${state === "saved" ? "bg-[#4f7a45]" : state === "saving" || state === "unsaved" ? "bg-copper" : "bg-[#b3412e]"}`} />
            {status}
          </span>
          <StatusBadge sermon={{ status: row.status, live_audience: row.live_audience, hidden: row.hidden_at !== null, unpublished_changes: changedSincePublish }} t={t} />
        </div>
      </div>
      {error ? (
        <Notice>
          {error}
          {state === "conflict" ? (
            <button type="button" onClick={() => window.location.reload()} className="ml-2 font-medium text-accent underline underline-offset-4">
              {t("Reload")}
            </button>
          ) : state === "error" ? (
            <button type="button" onClick={() => void flush()} className="ml-2 font-medium text-accent underline underline-offset-4">
              {t("Try again")}
            </button>
          ) : null}
        </Notice>
      ) : null}

      {/* Phones: one column, Edit or Preview. */}
      <div className="mt-5 grid grid-cols-2 gap-1 rounded-full bg-surface-2 p-1 lg:hidden">
        {(["edit", "preview"] as const).map((v) => (
          <button
            key={v}
            type="button"
            aria-pressed={view === v}
            onClick={() => setView(v)}
            className={`min-h-11 rounded-full px-4 font-medium transition-colors ${view === v ? "bg-surface text-foreground shadow-sm" : "text-muted hover:text-foreground"}`}
          >
            {v === "edit" ? t("Edit") : t("Preview")}
          </button>
        ))}
      </div>

      <div className="mt-6 grid grid-cols-1 gap-6 lg:grid-cols-[11rem_minmax(0,1fr)_380px] lg:items-start">
        <div className={`${view === "edit" ? "" : "hidden"} lg:sticky lg:top-6 lg:block`}>
          <div
            role="tablist"
            aria-label={t("Sermon")}
            className="flex gap-1 overflow-x-auto rounded-full bg-surface-2 p-1 lg:flex-col lg:rounded-2xl lg:bg-transparent lg:p-0"
            onKeyDown={(e) => arrowTabs(e, tab, setTab)}
          >
            {TABS.map((name) => (
              <button
                key={name}
                role="tab"
                id={`tab-${name}`}
                aria-selected={tab === name}
                aria-controls={`panel-${name}`}
                tabIndex={tab === name ? 0 : -1}
                onClick={() => setTab(name)}
                className={`min-h-11 flex-1 whitespace-nowrap rounded-full px-4 text-left font-medium transition-colors lg:flex-none lg:rounded-xl ${tab === name ? "bg-surface text-foreground shadow-sm lg:bg-surface-2 lg:shadow-none" : "text-muted hover:text-foreground lg:hover:bg-surface-2/60"}`}
              >
                {label(name)}
              </button>
            ))}
          </div>
          {tab !== "share" ? (
            <button
              type="button"
              onClick={() => setTab("share")}
              className="mt-4 hidden min-h-11 w-full items-center justify-center rounded-full bg-accent-strong px-4 font-semibold text-on-accent transition-opacity hover:opacity-90 lg:inline-flex"
            >
              {row.status === "published" ? t("Publish changes") : t("Ready to publish")}
            </button>
          ) : null}
        </div>

        <div role="tabpanel" id={`panel-${tab}`} aria-labelledby={`tab-${tab}`} className={`${view === "edit" ? "" : "hidden"} min-w-0 lg:block`}>
          {tab === "outline" ? <OutlineEditor lang={lang} t={t} sermonId={row.id} language={row.language} blocks={row.draft_blocks} onChange={setBlocks} review={review} onReview={setReview} /> : null}
          {tab === "details" ? <DetailsForm t={t} row={row} onChange={change} onCover={uploadCover} /> : null}
          {tab === "share" ? (
            <SharePanel
              t={t}
              row={row}
              blockers={blockers}
              changedSincePublish={changedSincePublish}
              onPublish={publish}
              onClose={close}
              onDuplicate={duplicate}
              onDelete={remove}
              goTo={(name) => setTab(name)}
            />
          ) : null}
        </div>

        <section aria-label={t("Preview")} className={`${view === "preview" ? "" : "hidden"} lg:sticky lg:top-6 lg:block`}>
          <Preview lang={lang} t={t} row={row} church={church} />
        </section>
      </div>
    </main>
  );
}

function arrowTabs(e: React.KeyboardEvent, tab: Tab, setTab: (t: Tab) => void) {
  const i = TABS.indexOf(tab);
  let next: number | null = null;
  if (e.key === "ArrowRight" || e.key === "ArrowDown") next = (i + 1) % TABS.length;
  if (e.key === "ArrowLeft" || e.key === "ArrowUp") next = (i - 1 + TABS.length) % TABS.length;
  if (e.key === "Home") next = 0;
  if (e.key === "End") next = TABS.length - 1;
  if (next === null) return;
  e.preventDefault();
  setTab(TABS[next]);
  document.getElementById(`tab-${TABS[next]}`)?.focus();
}

function guessTimeZone(): string | null {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone ?? null;
  } catch {
    return null;
  }
}
