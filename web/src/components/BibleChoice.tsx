"use client";

import { createContext, useContext, useState, type ReactNode } from "react";

/**
 * The Bible the reader picked on this page. One choice for the whole sermon:
 * picking a Bible on any passage shows every passage in it. Until the reader
 * picks, each passage opens in the Bible the pastor named (`startingBible`).
 */
const BibleChoiceContext = createContext<{ choice: string | null; choose: (code: string) => void }>({
  choice: null,
  choose: () => {},
});

export function BibleChoiceProvider({ children }: { children: ReactNode }) {
  const [choice, setChoice] = useState<string | null>(null);
  return <BibleChoiceContext.Provider value={{ choice, choose: setChoice }}>{children}</BibleChoiceContext.Provider>;
}

export function useBibleChoice() {
  return useContext(BibleChoiceContext);
}
