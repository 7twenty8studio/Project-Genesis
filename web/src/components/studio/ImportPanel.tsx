"use client";

import { useId, useState } from "react";
import { importBlanks } from "@/lib/blanks";
import type { DraftBlock, DraftRow } from "@/lib/draft";
import type { Translate } from "@/lib/i18n";
import { importText } from "@/lib/import/paste";
import { ScannedPDF, type ImportResult } from "@/lib/import/result";
import { reviewItems, type ReviewItem } from "@/lib/import/review";
import { Button, inputClass, Notice } from "./ui";

const MAX_FILE = 20 * 1024 * 1024;

type Props = {
  t: Translate;
  language: DraftRow["language"];
  hasOutline: boolean;
  onImported: (blocks: DraftBlock[], items: ReviewItem[], mode: "replace" | "append") => void;
  onCancel?: () => void;
};

/**
 * Paste text, or choose a Word (.docx), PDF or text file. Everything is read
 * here in the browser; the file is never uploaded. After every import the
 * outline is compared with the source word for word.
 */
export function ImportPanel({ t, language, hasOutline, onImported, onCancel }: Props) {
  const pasteId = useId();
  const fileId = useId();
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const [mode, setMode] = useState<"replace" | "append">("replace");
  const options = { language };

  function finish(result: ImportResult) {
    if (result.blocks.length === 0) {
      setProblem(t("Nothing to import was found."));
      return;
    }
    // A printed handout's blank lines become blanks waiting for their answers (never in Scripture or quotations).
    const blocks = importBlanks(result.blocks);
    onImported(blocks, reviewItems(result.source, blocks, result.notes, options), hasOutline ? mode : "replace");
  }

  async function readFile(file: File) {
    setProblem(null);
    if (file.size > MAX_FILE) return setProblem(t("That file is larger than 20 MB."));
    const name = file.name.toLowerCase();
    setBusy(true);
    try {
      if (name.endsWith(".docx")) {
        const { importDocx } = await import("@/lib/import/docx");
        finish(await importDocx(await file.arrayBuffer(), options));
      } else if (name.endsWith(".pdf")) {
        const { importPdf } = await import("@/lib/import/pdf");
        finish(await importPdf(await file.arrayBuffer(), options));
      } else if (name.endsWith(".txt") || name.endsWith(".md")) {
        finish(importText(await file.text(), options));
      } else if (name.endsWith(".doc") || name.endsWith(".pages") || name.endsWith(".odt")) {
        setProblem(t("Save the document as Word (.docx) or PDF first, then choose it here."));
      } else {
        setProblem(t("Choose a Word (.docx), PDF or text file."));
      }
    } catch (error) {
      setProblem(
        error instanceof ScannedPDF
          ? t("This PDF is a scan, so its words can't be read. Paste the text, or send the editable file (Word or Pages) instead.")
          : t("That file couldn't be read. Paste the text instead."),
      );
    } finally {
      setBusy(false);
    }
  }

  return (
    <section aria-labelledby={`${pasteId}-title`} className="rounded-3xl border border-border bg-surface p-5">
      <h2 id={`${pasteId}-title`} className="text-lg font-semibold">
        {t("Paste or import an outline")}
      </h2>
      <p className="mt-1 text-sm text-muted">{t("Your file stays on this computer: Studio reads it here, then checks that every word made it into the outline.")}</p>
      <label htmlFor={pasteId} className="mt-4 block font-medium">
        {t("Paste text")}
      </label>
      <textarea id={pasteId} className={`${inputClass} mt-2 font-serif`} rows={8} value={text} onChange={(e) => setText(e.target.value)} placeholder={t("# Title\n\nJohn 3:16 (NIV)\n\n- First point\n- Second point")} />
      <div className="mt-3 flex flex-wrap items-center gap-3">
        <Button primary disabled={busy || text.trim() === ""} onClick={() => finish(importText(text, options))}>
          {t("Make the outline")}
        </Button>
        <span className="text-muted">{t("or")}</span>
        <label htmlFor={fileId} className="inline-flex min-h-11 cursor-pointer items-center rounded-full border border-border px-5 font-medium hover:bg-surface-2 focus-within:outline focus-within:outline-3">
          {busy ? t("Reading…") : t("Choose a file")}
          <input
            id={fileId}
            type="file"
            className="sr-only"
            accept=".docx,.pdf,.txt,.md,application/vnd.openxmlformats-officedocument.wordprocessingml.document,application/pdf,text/plain"
            disabled={busy}
            onChange={(e) => {
              const file = e.target.files?.[0];
              e.target.value = "";
              if (file) void readFile(file);
            }}
          />
        </label>
        <span className="text-sm text-muted">{t("Word (.docx), PDF or text")}</span>
      </div>
      {hasOutline ? (
        <fieldset className="mt-4">
          <legend className="font-medium">{t("The outline already has items")}</legend>
          <label className="mt-2 flex items-center gap-2">
            <input type="radio" name={`${pasteId}-mode`} checked={mode === "replace"} onChange={() => setMode("replace")} /> {t("Replace them")}
          </label>
          <label className="mt-1 flex items-center gap-2">
            <input type="radio" name={`${pasteId}-mode`} checked={mode === "append"} onChange={() => setMode("append")} /> {t("Add after them")}
          </label>
        </fieldset>
      ) : null}
      {problem ? <Notice>{problem}</Notice> : null}
      {onCancel ? (
        <div className="mt-4">
          <Button onClick={onCancel}>{t("Cancel")}</Button>
        </div>
      ) : null}
    </section>
  );
}
