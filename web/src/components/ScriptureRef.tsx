"use client";

import { useId, useState } from "react";
import { translator, type Lang, type Translate } from "@/lib/i18n";
import type { PublishedRef } from "@/lib/outline";
import { config } from "@/config";
import { isFreeBible, loadPassage, loadYouVersionPassage, noteLetter, ownRange, startingBible, WEB_BIBLES, withMarkers, type Passage, type YouVersionBible } from "@/lib/scripture";
import { bookWithNumber, localName } from "@/lib/shared/references";
import { recordSermonEvent } from "./SermonEvents";

interface Props {
  reference: PublishedRef;
  /** The verified reference named in the outline's language ("Juan 3:16"). */
  named: string | null;
  outlineLanguage: string;
  lang: Lang;
  supabaseUrl: string;
  eventEndpoint: string;
  slug: string;
  /** YouVersion Bibles this page may offer (none in Studio's preview). */
  youversion?: YouVersionBible[];
}

/**
 * A Scripture reference in the outline. A verified one opens a preview of the
 * passage, verbatim from one of Versely's free Bibles (the one quoted, else
 * the outline language's), without leaving the outline; the reader can
 * switch Bible or open it in their own Bible in Versely. Others stay as the
 * pastor wrote them.
 */
export function ScriptureRef({ reference, named, outlineLanguage, lang, supabaseUrl, eventEndpoint, slug, youversion = [] }: Props) {
  const t = translator(lang);
  const panel = useId();
  const [open, setOpen] = useState(false);
  const [bible, setBible] = useState<string>(startingBible(reference.translation, reference.label, outlineLanguage, youversion));
  const [passage, setPassage] = useState<Passage | null>(null);
  const [state, setState] = useState<"idle" | "loading" | "failed">("idle");

  const verified = reference.status === "verified" && reference.start !== null;
  const label = reference.label ? ` · ${reference.label}` : "";

  if (!verified) {
    return (
      <p className="my-4 font-medium text-foreground">
        {reference.raw}
        {reference.label ? <span className="text-muted">{label}</span> : null}
      </p>
    );
  }

  async function load(code: string) {
    setState("loading");
    try {
      const start = reference.start!;
      const end = reference.end ?? start;
      setPassage(isFreeBible(code) ? await loadPassage(supabaseUrl, code, start, end) : await loadYouVersionPassage(supabaseUrl, config.supabaseAnonKey, code, start, end));
      setState("idle");
    } catch {
      setState("failed");
    }
  }

  function toggle() {
    const next = !open;
    setOpen(next);
    if (next && (!passage || passage.translation !== bible)) {
      void load(bible);
      recordSermonEvent(eventEndpoint, slug, "passage");
    }
  }

  function choose(code: string) {
    setBible(code);
    void load(code);
  }

  return (
    <div className="my-4 rounded-2xl border border-border bg-surface">
      <button
        type="button"
        onClick={toggle}
        aria-expanded={open}
        aria-controls={panel}
        className="flex min-h-12 w-full items-center justify-between gap-3 rounded-2xl px-4 py-3 text-left"
      >
        <span>
          <span className="font-semibold text-accent-strong">{reference.raw}</span>
          {reference.label ? <span className="text-muted">{label}</span> : null}
          {named && named !== reference.raw ? <span className="block text-sm text-muted">{named}</span> : null}
        </span>
        <svg aria-hidden="true" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className={`shrink-0 text-muted transition-transform duration-200 ${open ? "rotate-180" : ""}`}>
          <path d="m6 9 6 6 6-6" />
        </svg>
        <span className="sr-only">{open ? t("Hide passage") : t("Show passage")}</span>
      </button>
      {open ? (
        <div id={panel} className="border-t border-border px-4 pb-4 pt-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <label className="flex items-center gap-2 text-sm text-muted">
              {t("Bible")}
              <select
                value={bible}
                onChange={(e) => choose(e.target.value)}
                className="min-h-10 max-w-[16rem] rounded-lg border border-border bg-surface px-2 text-foreground"
              >
                {youversion.length ? (
                  <>
                    <optgroup label={t("Free Bibles")}>
                      {WEB_BIBLES.map((b) => (
                        <option key={b.code} value={b.code}>
                          {b.name}
                        </option>
                      ))}
                    </optgroup>
                    <optgroup label={t("From YouVersion")}>
                      {youversion.map((b) => (
                        <option key={b.id} value={b.id}>
                          {b.name}
                        </option>
                      ))}
                    </optgroup>
                  </>
                ) : (
                  WEB_BIBLES.map((b) => (
                    <option key={b.code} value={b.code}>
                      {b.name}
                    </option>
                  ))
                )}
              </select>
            </label>
          </div>
          <div aria-live="polite">
            {state === "loading" ? <p className="mt-3 text-sm text-muted">{t("Loading the passage…")}</p> : null}
            {state === "failed" ? (
              <p className="mt-3 text-sm text-muted">
                {t("The passage couldn't load.")}{" "}
                <button type="button" className="font-medium text-accent underline" onClick={() => load(bible)}>
                  {t("Try again")}
                </button>
              </p>
            ) : null}
          </div>
          {passage && state !== "loading" ? <PassageText passage={passage} reference={reference} panel={panel} t={t} /> : null}
          <a href={`versely://read/${reference.start}`} className="mt-3 inline-block text-sm font-medium text-accent underline-offset-4 hover:underline">
            {t("Read in your Bible in Versely")}
          </a>
        </div>
      ) : null}
    </div>
  );
}

/** The passage verbatim, with every footnote (YouVersion Bibles) and the Bible's notice. */
function PassageText({ passage, reference, panel, t }: { passage: Passage; reference: PublishedRef; panel: string; t: Translate }) {
  // Letters in reading order across the passage.
  const notes: { id: string; letter: string; text: string }[] = [];
  const verses = passage.verses.map((verse) => ({
    verse,
    parts: withMarkers(verse).map((part) => {
      if (typeof part === "string") return part;
      const note = { id: `${panel}-n${notes.length}`, letter: noteLetter(notes.length), text: verse.n![part].t };
      notes.push(note);
      return note;
    }),
  }));
  const language = WEB_BIBLES.find((b) => b.code === passage.translation)?.language ?? passage.language;
  return (
    <figure className="mt-3">
      <blockquote lang={language} dir="ltr" className="font-serif text-[1.125rem] leading-relaxed text-scripture">
        {verses.length === 0 ? (
          <p className="text-sm text-muted">{t("This Bible has no text for these verses.")}</p>
        ) : (
          verses.map(({ verse, parts }) => (
            <span key={`${verse.c}:${verse.v}`} className={verse.p ? "block whitespace-pre-line" : ""}>
              <sup className="mr-0.5 font-sans text-[0.7em] font-semibold text-muted">{verse.v}</sup>
              {parts.map((part, i) =>
                typeof part === "string" ? (
                  <span key={i}>{part}</span>
                ) : (
                  <sup key={i} className="font-sans text-[0.7em]">
                    <a href={`#${part.id}`} className="px-0.5 font-semibold text-accent underline-offset-2 hover:underline" aria-label={t("Footnote {letter}", { letter: part.letter })}>
                      {part.letter}
                    </a>
                  </sup>
                ),
              )}{" "}
            </span>
          ))
        )}
      </blockquote>
      {notes.length ? (
        <ol aria-label={t("Footnotes")} className="mt-3 space-y-1 border-t border-border pt-2 text-sm text-muted">
          {notes.map((note) => (
            <li key={note.id} id={note.id} lang={language} className="flex gap-2">
              <span className="font-semibold text-accent">{note.letter}</span>
              <span>{note.text}</span>
            </li>
          ))}
        </ol>
      ) : null}
      <figcaption className="mt-3 whitespace-pre-line text-xs leading-relaxed text-muted">
        {localName(bookWithNumber(Math.floor(reference.start! / 1_000_000)), passage.language).name} {ownRange(passage.verses)} · {passage.name}. {passage.license}
        {passage.publisherUrl ? (
          <>
            {" "}
            <a href={passage.publisherUrl} target="_blank" rel="noopener" className="font-medium text-accent underline underline-offset-2">
              {new URL(passage.publisherUrl).hostname.replace(/^www\./, "")}
            </a>
          </>
        ) : null}
      </figcaption>
    </figure>
  );
}
