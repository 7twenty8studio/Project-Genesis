"use client";

import {
  useRef,
  useState,
  type PointerEvent as ReactPointerEvent,
} from "react";
import {
  draftProblems,
  newBlockID,
  quoteTranslation,
  type DraftBlock,
  type DraftRow,
} from "@/lib/draft";
import type { Lang, Translate } from "@/lib/i18n";
import { describe, resolve } from "@/lib/shared/references";
import { appendReview } from "@/lib/import/review";
import type { Review } from "./Editor";
import { ImportPanel } from "./ImportPanel";
import { PassagePicker } from "./PassagePicker";
import { ReviewList } from "./ReviewList";
import { Button, inputClass } from "./ui";

type Kind = DraftBlock["kind"];
const KINDS: Kind[] = ["heading", "paragraph", "scripture", "list", "quote"];

type Props = {
  lang: Lang;
  t: Translate;
  sermonId: string;
  language: DraftRow["language"];
  blocks: DraftBlock[];
  onChange: (blocks: DraftBlock[]) => void;
  review: Review | null;
  onReview: (review: Review | null) => void;
};

/** The outline: import, the review list, then each item in order. */
export function OutlineEditor({
  lang,
  t,
  sermonId,
  language,
  blocks,
  onChange,
  review,
  onReview,
}: Props) {
  const [importing, setImporting] = useState(blocks.length === 0);
  const problems = draftProblems(blocks);
  const kindName = (k: Kind) =>
    k === "heading"
      ? t("Heading")
      : k === "paragraph"
        ? t("Paragraph")
        : k === "scripture"
          ? t("Scripture reference")
          : k === "list"
            ? t("List")
            : t("Quotation");

  const update = (id: string, next: DraftBlock) =>
    onChange(blocks.map((b) => (b.id === id ? next : b)));
  const move = (i: number, by: -1 | 1) => {
    const j = i + by;
    if (j < 0 || j >= blocks.length) return;
    const next = [...blocks];
    [next[i], next[j]] = [next[j], next[i]];
    onChange(next);
    requestAnimationFrame(() =>
      document
        .getElementById(`move-${by < 0 ? "up" : "down"}-${next[j].id}`)
        ?.focus(),
    );
  };
  // Drag and drop by the grip (mouse, pen or touch). `over` is where the card would land: before card `over`, or at the end.
  const listRef = useRef<HTMLOListElement>(null);
  const [drag, setDrag] = useState<{ from: number; over: number } | null>(null);
  const landing = (y: number) => {
    const cards = Array.from(listRef.current?.children ?? []) as HTMLElement[];
    const at = cards.findIndex((card) => {
      const r = card.getBoundingClientRect();
      return y < r.top + r.height / 2;
    });
    return at === -1 ? cards.length : at;
  };
  const startDrag = (i: number, e: ReactPointerEvent<HTMLButtonElement>) => {
    if (e.button !== 0) return;
    e.preventDefault();
    e.currentTarget.setPointerCapture(e.pointerId);
    setDrag({ from: i, over: i });
  };
  const dragTo = (e: ReactPointerEvent<HTMLButtonElement>) => {
    if (!drag) return;
    // Near the window's edge the page scrolls, so a card can go anywhere in a long outline.
    if (e.clientY < 80) window.scrollBy(0, -14);
    else if (e.clientY > window.innerHeight - 80) window.scrollBy(0, 14);
    const over = landing(e.clientY);
    if (over !== drag.over) setDrag({ ...drag, over });
  };
  const drop = () => {
    if (!drag) return;
    const { from, over } = drag;
    setDrag(null);
    const to = over > from ? over - 1 : over;
    if (to === from) return;
    const next = [...blocks];
    const [card] = next.splice(from, 1);
    next.splice(to, 0, card);
    onChange(next);
  };
  const lands = (at: number) =>
    drag !== null &&
    at !== drag.from &&
    at !== drag.from + 1 &&
    drag.over === at;

  const insert = (at: number, kind: Kind) => {
    const block = emptyBlock(kind);
    onChange([...blocks.slice(0, at), block, ...blocks.slice(at)]);
    requestAnimationFrame(() =>
      document.getElementById(`field-${block.id}`)?.focus(),
    );
  };

  return (
    <div>
      {importing ? (
        <ImportPanel
          t={t}
          language={language}
          hasOutline={blocks.length > 0}
          onImported={(imported, items, mode) => {
            onChange(mode === "replace" ? imported : [...blocks, ...imported]);
            // Replacing starts a new check; adding keeps every earlier item (answered or not) beside the new ones.
            onReview(
              mode === "replace"
                ? items.length
                  ? { items, decisions: {} }
                  : null
                : appendReview(review, items, `i${Date.now().toString(36)}`),
            );
            setImporting(false);
          }}
          onCancel={blocks.length ? () => setImporting(false) : undefined}
        />
      ) : (
        <Button onClick={() => setImporting(true)}>
          {t("Paste or import an outline")}
        </Button>
      )}

      {review ? (
        <ReviewList
          t={t}
          review={review}
          blocks={blocks}
          language={language}
          onBlocks={onChange}
          onReview={onReview}
        />
      ) : null}

      <ol
        ref={listRef}
        className={`mt-6 space-y-4 ${drag ? "select-none" : ""}`}
        aria-label={t("Outline")}
      >
        {blocks.map((block, i) => {
          const blockProblems = problems.filter((p) => p.blockId === block.id);
          return (
            <li
              key={block.id}
              data-block={block.id}
              className={`relative rounded-3xl border bg-surface p-4 transition-opacity duration-150 ${blockProblems.length ? "border-[#9b2c1f] dark:border-[#ffb4a6]" : "border-border"} ${drag?.from === i ? "opacity-50" : ""}`}
            >
              {lands(i) ? <DropLine edge="top" /> : null}
              {i === blocks.length - 1 && lands(blocks.length) ? (
                <DropLine edge="bottom" />
              ) : null}
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div className="flex items-center gap-1">
                  <button
                    type="button"
                    data-drag-handle={block.id}
                    aria-label={t("Drag to reorder item {n}", { n: i + 1 })}
                    title={t("Drag to reorder")}
                    className={`inline-flex size-10 touch-none items-center justify-center rounded-full text-muted hover:bg-surface-2 hover:text-foreground ${drag?.from === i ? "cursor-grabbing" : "cursor-grab"}`}
                    onPointerDown={(e) => startDrag(i, e)}
                    onPointerMove={dragTo}
                    onPointerUp={drop}
                    onPointerCancel={() => setDrag(null)}
                    onKeyDown={(e) => {
                      if (e.key === "ArrowUp" && i > 0) {
                        e.preventDefault();
                        move(i, -1);
                      } else if (
                        e.key === "ArrowDown" &&
                        i < blocks.length - 1
                      ) {
                        e.preventDefault();
                        move(i, 1);
                      }
                    }}
                  >
                    <svg
                      aria-hidden="true"
                      width="18"
                      height="18"
                      viewBox="0 0 24 24"
                      fill="currentColor"
                    >
                      <circle cx="9" cy="6" r="1.6" />
                      <circle cx="15" cy="6" r="1.6" />
                      <circle cx="9" cy="12" r="1.6" />
                      <circle cx="15" cy="12" r="1.6" />
                      <circle cx="9" cy="18" r="1.6" />
                      <circle cx="15" cy="18" r="1.6" />
                    </svg>
                  </button>
                  <label className="text-sm">
                    <span className="sr-only">
                      {t("Kind of item {n}", { n: i + 1 })}
                    </span>
                    <select
                      className="rounded-lg border border-border bg-surface-2 px-2 py-1.5 font-medium"
                      value={block.kind}
                      onChange={(e) =>
                        update(
                          block.id,
                          convert(block, e.target.value as Kind, language),
                        )
                      }
                    >
                      {KINDS.map((k) => (
                        <option key={k} value={k}>
                          {kindName(k)}
                        </option>
                      ))}
                    </select>
                  </label>
                </div>
                <div className="flex gap-1">
                  <IconButton
                    id={`move-up-${block.id}`}
                    label={t("Move up")}
                    disabled={i === 0}
                    onClick={() => move(i, -1)}
                    path="M12 19V5M5 12l7-7 7 7"
                  />
                  <IconButton
                    id={`move-down-${block.id}`}
                    label={t("Move down")}
                    disabled={i === blocks.length - 1}
                    onClick={() => move(i, 1)}
                    path="M12 5v14M5 12l7 7 7-7"
                  />
                  <IconButton
                    label={t("Remove")}
                    onClick={() =>
                      onChange(blocks.filter((b) => b.id !== block.id))
                    }
                    path="M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14"
                  />
                </div>
              </div>
              <BlockFields
                t={t}
                block={block}
                lang={lang}
                language={language}
                onChange={(next) => update(block.id, next)}
              />
              {blockProblems.map((p) => (
                <p
                  key={p.problem}
                  className="mt-2 text-sm font-medium text-[#9b2c1f] dark:text-[#ffb4a6]"
                >
                  {t(problemText(p.problem))}
                </p>
              ))}
              <AddMenu
                t={t}
                kinds={KINDS}
                kindName={kindName}
                onAdd={(k) => insert(i + 1, k)}
                label={t("Add below")}
              />
            </li>
          );
        })}
      </ol>
      {blocks.length === 0 && !importing ? (
        <p className="mt-6 text-muted">{t("The outline is empty.")}</p>
      ) : null}
      <div className="mt-6">
        <AddMenu
          t={t}
          kinds={KINDS}
          kindName={kindName}
          onAdd={(k) => insert(blocks.length, k)}
          label={t("Add to the end")}
        />
      </div>
      {problems.some((p) => !p.blockId) ? (
        <p className="mt-4 font-medium text-[#9b2c1f] dark:text-[#ffb4a6]">
          {t(
            "The outline is longer than Versely can publish (400 items, 200,000 characters).",
          )}
        </p>
      ) : null}
      {/* sermonId keeps the review per sermon */}
      <span hidden data-sermon={sermonId} />
    </div>
  );
}

function BlockFields({
  t,
  block,
  lang,
  language,
  onChange,
}: {
  t: Translate;
  block: DraftBlock;
  lang: Lang;
  language: DraftRow["language"];
  onChange: (b: DraftBlock) => void;
}) {
  const id = `field-${block.id}`;
  switch (block.kind) {
    case "heading":
      return (
        <div className="mt-3 flex flex-col gap-2 sm:flex-row">
          <input
            id={id}
            aria-label={t("Heading")}
            className={`${inputClass} text-lg font-semibold`}
            value={block.text}
            onChange={(e) => onChange({ ...block, text: e.target.value })}
          />
          <label className="text-sm">
            <span className="sr-only">{t("Heading size")}</span>
            <select
              className={`${inputClass} sm:w-48`}
              value={block.level}
              onChange={(e) =>
                onChange({
                  ...block,
                  level: Number(e.target.value) as 1 | 2 | 3,
                })
              }
            >
              <option value={1}>{t("Main heading")}</option>
              <option value={2}>{t("Heading")}</option>
              <option value={3}>{t("Subheading")}</option>
            </select>
          </label>
        </div>
      );
    case "paragraph":
    case "quote":
      return (
        <textarea
          id={id}
          aria-label={block.kind === "quote" ? t("Quotation") : t("Paragraph")}
          className={`${inputClass} mt-3 ${block.kind === "quote" ? "italic" : ""}`}
          rows={Math.min(
            14,
            Math.max(
              3,
              Math.ceil(block.text.length / 70) +
                block.text.split("\n").length -
                1,
            ),
          )}
          value={block.text}
          onChange={(e) => onChange({ ...block, text: e.target.value })}
        />
      );
    case "list":
      return (
        <div className="mt-3">
          <textarea
            id={id}
            aria-label={t("List items, one per line")}
            aria-describedby={`${id}-hint`}
            className={inputClass}
            rows={Math.max(3, block.items.length + 1)}
            value={block.items.join("\n")}
            onChange={(e) =>
              onChange({ ...block, items: e.target.value.split("\n") })
            }
            onBlur={() =>
              onChange({
                ...block,
                items: block.items.filter((x) => x.trim() !== ""),
              })
            }
          />
          <p id={`${id}-hint`} className="mt-1 text-sm text-muted">
            {t("One item per line.")}
          </p>
          <label className="mt-2 flex items-center gap-2">
            <input
              type="checkbox"
              className="size-5"
              checked={block.ordered}
              onChange={(e) =>
                onChange({ ...block, ordered: e.target.checked })
              }
            />
            {t("Numbered")}
          </label>
        </div>
      );
    case "scripture":
      return (
        <ScriptureFields
          t={t}
          block={block}
          lang={lang}
          language={language}
          onChange={onChange}
          id={id}
        />
      );
  }
}

function ScriptureFields({
  t,
  block,
  lang,
  language,
  onChange,
  id,
}: {
  t: Translate;
  block: Extract<DraftBlock, { kind: "scripture" }>;
  lang: Lang;
  language: DraftRow["language"];
  onChange: (b: DraftBlock) => void;
  id: string;
}) {
  const [picking, setPicking] = useState(false);
  const ref = block.ref;
  const shown = quoteTranslation(ref.label);
  const named =
    ref.status === "verified" && ref.start !== null
      ? describe(ref.start, ref.end ?? ref.start, lang)
      : null;
  const setRaw = (raw: string) => {
    const resolved = resolve(raw, { portugueseFirst: language === "pt" });
    onChange({
      ...block,
      ref: {
        ...ref,
        raw,
        start: resolved.start,
        end: resolved.end,
        status: resolved.status,
      },
    });
  };
  return (
    <div className="mt-3">
      <input
        id={id}
        aria-label={t("Reference as you'd write it")}
        aria-describedby={`${id}-status`}
        className={`${inputClass} font-medium`}
        value={ref.raw}
        onChange={(e) => setRaw(e.target.value)}
      />
      <p id={`${id}-status`} className="mt-1 text-sm" aria-live="polite">
        {named ? (
          <span className="text-muted">
            {t("Opens {passage}", { passage: named })}
          </span>
        ) : ref.status === "ambiguous" ? (
          <span className="font-medium text-[#8a4b00] dark:text-[#ffd59e]">
            {t(
              "Versely can't tell which verses this is. Check it, or link the passage yourself.",
            )}
          </span>
        ) : (
          <span className="text-muted">
            {t("Shown as written; it won't open a passage.")}
          </span>
        )}
        <button
          type="button"
          className="ml-2 font-medium text-accent underline underline-offset-4"
          onClick={() => setPicking(!picking)}
          aria-expanded={picking}
        >
          {t("Link a passage")}
        </button>
      </p>
      {picking ? (
        <PassagePicker
          t={t}
          lang={lang}
          start={ref.start}
          end={ref.end}
          onPick={(start, end) => {
            onChange({
              ...block,
              ref: { ...ref, start, end, status: "verified" },
            });
            setPicking(false);
          }}
          onCancel={() => setPicking(false)}
        />
      ) : null}
      <div className="mt-3 grid gap-3 sm:grid-cols-[12rem_1fr]">
        <label className="block text-sm">
          <span className="font-medium">{t("Translation")}</span>
          <input
            className={`${inputClass} mt-1`}
            placeholder={t("e.g. NIV")}
            value={ref.label ?? ""}
            onChange={(e) =>
              onChange({
                ...block,
                ref: { ...ref, label: e.target.value || null },
              })
            }
          />
        </label>
        <label className="block text-sm">
          <span className="font-medium">{t("Quoted words (optional)")}</span>
          <textarea
            className={`${inputClass} mt-1`}
            rows={2}
            value={ref.quote ?? ""}
            onChange={(e) =>
              onChange({
                ...block,
                ref: { ...ref, quote: e.target.value || null },
              })
            }
          />
        </label>
      </div>
      {ref.quote ? (
        <p className="mt-2 text-sm text-muted">
          {shown && ref.status === "verified"
            ? t(
                "Readers see this passage from Versely's own copy of the {name}, word for word.",
                { name: shown },
              )
            : t(
                "Quoted words aren't published: readers see the reference and open it in a Bible.",
              )}
        </p>
      ) : null}
    </div>
  );
}

function AddMenu({
  t,
  kinds,
  kindName,
  onAdd,
  label,
}: {
  t: Translate;
  kinds: Kind[];
  kindName: (k: Kind) => string;
  onAdd: (k: Kind) => void;
  label: string;
}) {
  const [open, setOpen] = useState(false);
  return (
    <div className="mt-3">
      <button
        type="button"
        aria-expanded={open}
        onClick={() => setOpen(!open)}
        className="inline-flex min-h-10 items-center gap-1 text-sm font-medium text-accent"
      >
        <span aria-hidden="true">＋</span> {label}
      </button>
      {open ? (
        <div
          className="mt-2 flex flex-wrap gap-2"
          role="group"
          aria-label={label}
        >
          {kinds.map((k) => (
            <button
              key={k}
              type="button"
              className="min-h-10 rounded-full border border-border px-3 text-sm hover:bg-surface-2"
              onClick={() => {
                setOpen(false);
                onAdd(k);
              }}
            >
              {kindName(k)}
            </button>
          ))}
          <span className="sr-only">{t("Choose what to add")}</span>
        </div>
      ) : null}
    </div>
  );
}

/** Where a dragged card will land: a line in the gap above or below this card. */
function DropLine({ edge }: { edge: "top" | "bottom" }) {
  return (
    <span
      aria-hidden="true"
      className={`pointer-events-none absolute inset-x-4 h-1 rounded-full bg-accent-strong ${edge === "top" ? "-top-2.5" : "-bottom-2.5"}`}
    />
  );
}

function IconButton({
  id,
  label,
  onClick,
  disabled,
  path,
}: {
  id?: string;
  label: string;
  onClick: () => void;
  disabled?: boolean;
  path: string;
}) {
  return (
    <button
      id={id}
      type="button"
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={onClick}
      className="inline-flex size-10 items-center justify-center rounded-full text-muted hover:bg-surface-2 hover:text-foreground disabled:opacity-30"
    >
      <svg
        aria-hidden="true"
        width="18"
        height="18"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <path d={path} />
      </svg>
    </button>
  );
}

export function emptyBlock(kind: Kind): DraftBlock {
  const id = newBlockID();
  switch (kind) {
    case "heading":
      return { id, kind, text: "", level: 2 };
    case "list":
      return { id, kind, items: [""], ordered: false };
    case "scripture":
      return {
        id,
        kind,
        ref: {
          raw: "",
          start: null,
          end: null,
          status: "unlinked",
          label: null,
          quote: null,
        },
      };
    default:
      return { id, kind, text: "" };
  }
}

/** Changes an item's kind without losing a word. */
export function convert(
  block: DraftBlock,
  kind: Kind,
  language: DraftRow["language"],
): DraftBlock {
  if (block.kind === kind) return block;
  const text =
    block.kind === "list"
      ? block.items.join("\n")
      : block.kind === "scripture"
        ? [block.ref.raw, block.ref.label, block.ref.quote]
            .filter(Boolean)
            .join("\n")
        : block.text;
  switch (kind) {
    case "heading":
      return { id: block.id, kind, text, level: 2 };
    case "list":
      return {
        id: block.id,
        kind,
        items: text.split("\n").filter((x) => x.trim() !== ""),
        ordered: false,
      };
    case "scripture": {
      const [first, ...rest] = text.split("\n");
      const resolved = resolve(first ?? "", {
        portugueseFirst: language === "pt",
      });
      return {
        id: block.id,
        kind,
        ref: {
          raw: first ?? "",
          start: resolved.start,
          end: resolved.end,
          status: resolved.status,
          label: null,
          quote: rest.join("\n") || null,
        },
      };
    }
    default:
      return { id: block.id, kind, text };
  }
}

// translatable returns
function problemText(problem: string): string {
  switch (problem) {
    case "heading_too_long":
      return "Headings can be up to 300 characters.";
    case "text_too_long":
      return "This is longer than 5,000 characters. Split it into two paragraphs.";
    case "list_too_long":
      return "Lists can have up to 100 items of 2,000 characters each.";
    case "reference_length":
      return "Write a reference of up to 120 characters.";
    case "label_too_long":
      return "The translation name can be up to 60 characters.";
    case "quote_too_long":
      return "Quoted words can be up to 5,000 characters.";
    default:
      return "This item can't be saved as it is.";
  }
}
