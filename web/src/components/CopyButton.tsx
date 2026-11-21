"use client";

import { useState } from "react";

/** Copies a section's words exactly as published. */
export function CopyButton({ text, label, done, sectionName }: { text: string; label: string; done: string; sectionName: string }) {
  const [copied, setCopied] = useState(false);
  async function copy() {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  }
  return (
    <button
      type="button"
      onClick={copy}
      aria-label={`${label}: ${sectionName}`}
      className="inline-flex min-h-10 items-center gap-1.5 rounded-full border border-border px-3 text-sm font-medium text-muted hover:bg-surface-2 hover:text-foreground"
    >
      <svg aria-hidden="true" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <rect x="9" y="9" width="13" height="13" rx="2" />
        <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
      </svg>
      <span aria-live="polite">{copied ? done : label}</span>
    </button>
  );
}
