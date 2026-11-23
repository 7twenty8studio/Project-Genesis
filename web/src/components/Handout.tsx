"use client";

// A fill-in-the-blank handout on the guest page (owner's plan, 22 November
// 2026). Members type in the blanks as they listen. Their answers stay in
// this browser only (nothing is sent), saved per sermon and revision, so a
// later edit by the church never changes work already done. Check Answers
// and Show Answers come together, once the church has revealed the key for
// this revision (published_sermon gives it no sooner). Practice Again starts
// a fresh try without touching the saved answers.

import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { isCorrect, pieces, type AnswersState, type PublishedBlank } from "@/lib/blanks";

export interface HandoutLabels {
  /** "Blank {n}" */
  blank: string;
  /** "Your own words" */
  ownWords: string;
  correct: string;
  notYet: string;
  answerIs: string;
  savedHidden: string;
  savedRevealed: string;
  savedNever: string;
  practicing: string;
  check: string;
  showAnswers: string;
  hideAnswers: string;
  practice: string;
  backToMine: string;
  title: string;
}

interface Handout {
  blanks: Map<number, PublishedBlank>;
  value: (n: number) => string;
  set: (n: number, v: string) => void;
  checked: boolean;
  showing: boolean;
  revealed: boolean;
  labels: HandoutLabels;
}

const Ctx = createContext<Handout | null>(null);

function storageKey(slug: string, revision: number) {
  return `versely.handout.${slug}.${revision}`;
}

function load(key: string): Record<string, string> {
  try {
    const raw = window.localStorage.getItem(key);
    const parsed = raw ? (JSON.parse(raw) as { responses?: Record<string, string> }) : null;
    return parsed?.responses && typeof parsed.responses === "object" ? parsed.responses : {};
  } catch {
    return {};
  }
}

function save(key: string, responses: Record<string, string>) {
  try {
    window.localStorage.setItem(key, JSON.stringify({ responses, savedAt: new Date().toISOString() }));
  } catch {
    // Private browsing or storage full: the answers stay on the page until it closes.
  }
}

/** Holds the handout's answers for every blank inside it, and the bar that checks them. */
export function HandoutProvider({
  slug,
  revision,
  blanks,
  answers,
  preview,
  labels,
  children,
}: {
  slug: string;
  revision: number;
  blanks: PublishedBlank[];
  answers: AnswersState;
  /** Studio's preview: nothing saved. */
  preview?: boolean;
  labels: HandoutLabels;
  children: ReactNode;
}) {
  const key = storageKey(slug, revision);
  const [mine, setMine] = useState<Record<string, string>>({});
  const [practice, setPractice] = useState<Record<string, string> | null>(null);
  const [checked, setChecked] = useState(false);
  const [showing, setShowing] = useState(false);
  const map = useMemo(() => new Map(blanks.map((b) => [b.n, b])), [blanks]);
  // The key counts only if it really came with this revision.
  const revealed = answers === "revealed" && blanks.some((b) => !b.open && typeof b.answer === "string");

  useEffect(() => {
    // Read after hydration, so the server's page and the browser's agree.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (!preview) setMine(load(key));
  }, [key, preview]);

  const value = (n: number) => (practice ? practice[n] : mine[n]) ?? "";
  const set = (n: number, v: string) => {
    setChecked(false);
    if (practice) {
      setPractice({ ...practice, [n]: v });
      return;
    }
    const next = { ...mine, [n]: v };
    setMine(next);
    if (!preview) save(key, next);
  };

  if (blanks.length === 0) return <>{children}</>;
  const status = practice ? labels.practicing : answers === "never" ? labels.savedNever : revealed ? labels.savedRevealed : labels.savedHidden;
  return (
    <Ctx.Provider value={{ blanks: map, value, set, checked, showing, revealed, labels }}>
      {children}
      <section aria-label={labels.title} className="mt-10 rounded-2xl border border-border bg-surface p-5" data-testid="handout-bar">
        <p className="leading-relaxed text-muted" aria-live="polite">
          {status}
        </p>
        {revealed ? (
          <div className="mt-3 flex flex-wrap gap-2">
            <BarButton primary onClick={() => setChecked(true)}>
              {labels.check}
            </BarButton>
            <BarButton onClick={() => setShowing(!showing)}>{showing ? labels.hideAnswers : labels.showAnswers}</BarButton>
            {practice ? (
              <BarButton
                onClick={() => {
                  setPractice(null);
                  setChecked(false);
                }}
              >
                {labels.backToMine}
              </BarButton>
            ) : (
              <BarButton
                onClick={() => {
                  setPractice({});
                  setChecked(false);
                  setShowing(false);
                }}
              >
                {labels.practice}
              </BarButton>
            )}
          </div>
        ) : null}
      </section>
    </Ctx.Provider>
  );
}

function BarButton({ primary, onClick, children }: { primary?: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`inline-flex min-h-11 items-center rounded-full px-5 font-medium ${primary ? "bg-accent-strong text-on-accent hover:opacity-90" : "border border-border bg-surface hover:bg-surface-2"}`}
    >
      {children}
    </button>
  );
}

/** The church's words with each "[[n]]" as a box to fill in (plain words outside a handout). */
export function BlankText({ text }: { text: string }) {
  const handout = useContext(Ctx);
  if (!handout) return <>{text}</>;
  return (
    <>
      {pieces(text, (n) => handout.blanks.has(n)).map((p, i) => (p.kind === "text" ? <span key={i}>{p.text}</span> : <BlankBox key={i} n={p.n} handout={handout} />))}
    </>
  );
}

function BlankBox({ n, handout }: { n: number; handout: Handout }) {
  const blank = handout.blanks.get(n)!;
  const { labels } = handout;
  const value = handout.value(n);
  const answer = !blank.open && typeof blank.answer === "string" ? blank.answer : null;
  const graded = handout.checked && handout.revealed && answer !== null ? isCorrect(value, answer) : null;
  const width = blank.open ? 18 : Math.max(8, Math.min(24, (answer?.length ?? 10) + 2));
  const label = labels.blank.replace("{n}", String(n));
  return (
    <span className="inline-flex flex-wrap items-baseline gap-x-1 align-baseline">
      <input
        type="text"
        value={value}
        onChange={(e) => handout.set(n, e.target.value)}
        aria-label={blank.open ? `${label}, ${labels.ownWords}` : label}
        placeholder={blank.hint ?? (blank.open ? labels.ownWords : "")}
        autoComplete="off"
        spellCheck={false}
        data-blank={n}
        style={{ width: `${width}ch` }}
        className={`mx-0.5 max-w-full rounded-none border-0 border-b-2 bg-transparent px-1 py-0 text-center font-semibold not-italic text-accent-strong placeholder:font-normal placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-copper ${
          graded === true ? "border-[#2c5a35] dark:border-[#9fd3a8]" : graded === false ? "border-[#9b2c1f] dark:border-[#ffb4a6]" : "border-copper"
        }`}
      />
      {graded !== null ? (
        <span className={`text-sm font-medium ${graded ? "text-[#2c5a35] dark:text-[#9fd3a8]" : "text-[#9b2c1f] dark:text-[#ffb4a6]"}`}>
          {graded ? `✓ ${labels.correct}` : labels.notYet}
        </span>
      ) : null}
      {handout.showing && answer !== null ? (
        <span className="text-sm text-muted">
          ({labels.answerIs} {answer})
        </span>
      ) : null}
    </span>
  );
}
