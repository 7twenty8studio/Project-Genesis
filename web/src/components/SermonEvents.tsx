"use client";

import { useEffect } from "react";

/**
 * Aggregate counts for the church (VRS-18): one "open" when the page is read.
 * sermon-events keeps no address, account or text, and counts a visitor once
 * a day; a failure here never affects the page.
 */
export function recordSermonEvent(endpoint: string, slug: string, kind: "open" | "passage" | "save") {
  try {
    void fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ slug, kind }),
      keepalive: true,
    }).catch(() => undefined);
  } catch {
    // Counting is best effort.
  }
}

export function OpenEvent({ endpoint, slug }: { endpoint: string; slug: string }) {
  useEffect(() => {
    recordSermonEvent(endpoint, slug, "open");
  }, [endpoint, slug]);
  return null;
}
