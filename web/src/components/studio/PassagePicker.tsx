"use client";

import { useId, useState } from "react";
import type { Lang, Translate } from "@/lib/i18n";
import { books, localName, splitVerseID, verseID } from "@/lib/shared/references";
import { Button, inputClass } from "./ui";

/** Links a reference to verses by hand (book, chapter, first and last verse), keeping what the pastor typed. */
export function PassagePicker({ t, lang, start, end, onPick, onCancel }: { t: Translate; lang: Lang; start: number | null; end: number | null; onPick: (s: number, e: number) => void; onCancel: () => void }) {
  const id = useId();
  const first = start ? splitVerseID(start) : { book: 43, chapter: 1, verse: 1 };
  const last = end ? splitVerseID(end) : first;
  const [book, setBook] = useState(first.book);
  const [chapter, setChapter] = useState(first.chapter);
  const [from, setFrom] = useState(first.verse);
  const [to, setTo] = useState(last.book === first.book && last.chapter === first.chapter ? last.verse : first.verse);
  const info = books[book - 1];
  const chapters = info.verses.length;
  const verses = info.verses[Math.min(chapter, chapters) - 1];
  const number = (max: number) => Array.from({ length: max }, (_, i) => i + 1);

  return (
    <fieldset className="mt-3 rounded-2xl border border-border p-4">
      <legend className="px-1 font-medium">{t("Link a passage")}</legend>
      <div className="grid gap-3 sm:grid-cols-4">
        <label className="block text-sm sm:col-span-2" htmlFor={`${id}-book`}>
          {t("Book")}
          <select
            id={`${id}-book`}
            className={`${inputClass} mt-1`}
            value={book}
            onChange={(e) => {
              setBook(Number(e.target.value));
              setChapter(1);
              setFrom(1);
              setTo(1);
            }}
          >
            {books.map((b) => (
              <option key={b.id} value={b.id}>
                {localName(b, lang).name}
              </option>
            ))}
          </select>
        </label>
        <label className="block text-sm" htmlFor={`${id}-chapter`}>
          {t("Chapter")}
          <select
            id={`${id}-chapter`}
            className={`${inputClass} mt-1`}
            value={chapter}
            onChange={(e) => {
              setChapter(Number(e.target.value));
              setFrom(1);
              setTo(1);
            }}
          >
            {number(chapters).map((n) => (
              <option key={n}>{n}</option>
            ))}
          </select>
        </label>
        <div className="grid grid-cols-2 gap-2">
          <label className="block text-sm" htmlFor={`${id}-from`}>
            {t("From verse")}
            <select id={`${id}-from`} className={`${inputClass} mt-1`} value={from} onChange={(e) => { const v = Number(e.target.value); setFrom(v); if (to < v) setTo(v); }}>
              {number(verses).map((n) => (
                <option key={n}>{n}</option>
              ))}
            </select>
          </label>
          <label className="block text-sm" htmlFor={`${id}-to`}>
            {t("To verse")}
            <select id={`${id}-to`} className={`${inputClass} mt-1`} value={to} onChange={(e) => setTo(Number(e.target.value))}>
              {number(verses).filter((n) => n >= from).map((n) => (
                <option key={n}>{n}</option>
              ))}
            </select>
          </label>
        </div>
      </div>
      <p className="mt-2 text-sm text-muted">{t("Verse numbers as in the King James Version.")}</p>
      <div className="mt-3 flex gap-2">
        <Button primary onClick={() => onPick(verseID(book, chapter, from), verseID(book, chapter, Math.max(from, to)))}>
          {t("Link")}
        </Button>
        <Button onClick={onCancel}>{t("Cancel")}</Button>
      </div>
    </fieldset>
  );
}
