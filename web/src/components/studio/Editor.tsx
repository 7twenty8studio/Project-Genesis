"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { closeSermon, deleteSermon, duplicateSermon, publishSermon, saveSermon, uploadSermonCover } from "@/app/studio/actions";
import { draftProblems, type DraftBlock, type DraftDetails, type DraftRow } from "@/lib/draft";
import { translator, type Lang } from "@/lib/i18n";
import type { Decision, ReviewItem } from "@/lib/import/review";
import { publishBlockers, refusalMessage } from "@/lib/studio";
import { DetailsForm } from "./DetailsForm";
import { OutlineEditor } from "./OutlineEditor";
import { Preview } from "./Preview";
import { SharePanel } from "./SharePanel";
import { StatusBadge } from "./StatusBadge";
import { Notice } from "./ui";

export type Review = { items: ReviewItem[]; decisions: Record<string, Decision | undefined> };
type SaveState = "saved" | "unsaved" | "saving" | "error" | "conflict" | "invalid";
const TABS = ["outline", "details", "preview", "share"] as const;
type Tab = (typeof TABS)[number];

const reviewKey = (id: string) => `versely.studio.review.${id}`;
function loadReview(id: string): Review | null {
  try {
    const raw = window.localStorage.getItem(reviewKey(id));
    return raw ? (JSON.parse(raw) as Review) : null;
  } catch {
    return null;
  }
}

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
  const [state, setState] = useState<SaveState>("saved");
  const [error, setError] = useState<string | null>(null);
  const [review, setReviewState] = useState<Review | null>(null);

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

  // Browser-only state (this computer's saved review, its time zone) is read
  // after hydration, so the server's first render and the browser's agree.
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => setReviewState(loadReview(initial.id)), [initial.id]);

  // A new sermon takes this computer's time zone; it's saved with the next change.
  useEffect(() => {
    if (initial.time_zone !== null) return;
    const zone = guessTimeZone();
    if (zone) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setRow((r) => ({ ...r, time_zone: zone }));
      dirty.current = true;
    }
  }, [initial.time_zone]);

  const setReview = useCallback(
    (next: Review | null) => {
      setReviewState(next);
      try {
        if (next) window.localStorage.setItem(reviewKey(initial.id), JSON.stringify(next));
        else window.localStorage.removeItem(reviewKey(initial.id));
      } catch {
        // The review still works for this visit.
      }
    },
    [initial.id],
  );

  const save = useCallback(async (): Promise<boolean> => {
    if (conflict.current) return false;
    if (!dirty.current) return true;
    dirty.current = false;
    const current = latest.current;
    // An outline the database would refuse isn't sent; the details still are.
    const invalid = draftProblems(current.draft_blocks).length > 0;
    setState("saving");
    const result = await saveSermon(current.id, version.current, detailsOf(current), invalid ? null : current.draft_blocks);
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

  async function close(how: "unpublish" | "restrict"): Promise<boolean> {
    const saved = await flush();
    if (!saved) return false;
    const result = await queue(() => closeSermon(row.id, how));
    if (!result.ok) {
      setError(t(refusalMessage(result.code)));
      return false;
    }
    setVersion(result.version, how === "unpublish" ? null : undefined);
    setRow((r) =>
      how === "unpublish"
        ? { ...r, status: r.status === "published" ? "unpublished" : r.status }
        : { ...r, audience: "members", live_audience: r.live_audience ? "members" : null },
    );
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
    setReview(null);
    window.location.assign(`/studio?church=${row.group_id}`);
  }

  const saving = state === "saving" || state === "unsaved";
  const blockers = publishBlockers(row, review, saving);
  const changedSincePublish = row.status === "published" && (shown.published !== shown.current || state !== "saved");

  return (
    <main className="mx-auto max-w-3xl px-4 pb-24 pt-6 sm:px-6">
      <p className="text-sm font-medium uppercase tracking-wider text-accent">{church}</p>
      <div className="mt-1 flex flex-wrap items-center justify-between gap-3">
        <h1 className="min-w-0 text-3xl font-semibold tracking-tight">{row.title || t("Untitled sermon")}</h1>
        <StatusBadge sermon={{ status: row.status, live_audience: row.live_audience, hidden: row.hidden_at !== null, unpublished_changes: changedSincePublish }} t={t} />
      </div>
      <p className="mt-2 text-sm text-muted" role="status" aria-live="polite">
        {state === "saved" ? t("All changes saved") : state === "saving" ? t("Saving…") : state === "unsaved" ? t("Not saved yet") : state === "conflict" ? t("Not saved: changed elsewhere") : state === "invalid" ? t("Outline not saved: fix the items marked in red") : t("Not saved")}
      </p>
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

      <div role="tablist" aria-label={t("Sermon")} className="mt-6 flex gap-1 overflow-x-auto rounded-full bg-surface-2 p-1" onKeyDown={(e) => arrowTabs(e, tab, setTab)}>
        {TABS.map((name) => (
          <button
            key={name}
            role="tab"
            id={`tab-${name}`}
            aria-selected={tab === name}
            aria-controls={`panel-${name}`}
            tabIndex={tab === name ? 0 : -1}
            onClick={() => setTab(name)}
            className={`min-h-11 flex-1 whitespace-nowrap rounded-full px-4 font-medium ${tab === name ? "bg-surface text-foreground shadow-sm" : "text-muted hover:text-foreground"}`}
          >
            {name === "outline" ? t("Outline") : name === "details" ? t("Details") : name === "preview" ? t("Preview") : t("Share")}
          </button>
        ))}
      </div>

      <div role="tabpanel" id={`panel-${tab}`} aria-labelledby={`tab-${tab}`} className="mt-6">
        {tab === "outline" ? <OutlineEditor lang={lang} t={t} sermonId={row.id} language={row.language} blocks={row.draft_blocks} onChange={setBlocks} review={review} onReview={setReview} /> : null}
        {tab === "details" ? <DetailsForm t={t} row={row} onChange={change} onCover={uploadCover} /> : null}
        {tab === "preview" ? <Preview lang={lang} t={t} row={row} church={church} /> : null}
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
    </main>
  );
}

function arrowTabs(e: React.KeyboardEvent, tab: Tab, setTab: (t: Tab) => void) {
  const i = TABS.indexOf(tab);
  let next: number | null = null;
  if (e.key === "ArrowRight") next = (i + 1) % TABS.length;
  if (e.key === "ArrowLeft") next = (i - 1 + TABS.length) % TABS.length;
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
