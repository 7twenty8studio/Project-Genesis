"use client";

import { useRouter } from "next/navigation";
import { useEffect, useId, useRef, useState } from "react";
import { translator, type Lang } from "@/lib/i18n";
import { applyLang, applyTheme, type Theme } from "@/lib/prefs";

const LANGUAGES: { code: Lang; name: string; html: string }[] = [
  { code: "en", name: "English", html: "en" },
  { code: "es", name: "Español", html: "es" },
  { code: "pt", name: "Português", html: "pt-BR" },
];

/**
 * Appearance and Language, in the header on every page, before sign-in too.
 * A choice applies at once and is remembered (cookies, a year). The language
 * is Versely's own words only: never a sermon's language or a Bible.
 */
export function PrefsMenu({ lang, theme }: { lang: Lang; theme: Theme }) {
  const t = translator(lang);
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [look, setLook] = useState<Theme>(theme);
  const [language, setLanguage] = useState<Lang>(lang);
  const panel = useId();
  const root = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    const away = (e: MouseEvent) => !root.current?.contains(e.target as Node) && setOpen(false);
    const escape = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setOpen(false);
        button.current?.focus();
      }
    };
    document.addEventListener("mousedown", away);
    document.addEventListener("keydown", escape);
    return () => {
      document.removeEventListener("mousedown", away);
      document.removeEventListener("keydown", escape);
    };
  }, [open]);

  const chooseLook = (value: Theme) => {
    setLook(value);
    applyTheme(value);
  };
  const chooseLang = (value: Lang) => {
    setLanguage(value);
    applyLang(value, LANGUAGES.find((l) => l.code === value)?.html ?? value);
    router.refresh();
  };

  const looks: { value: Theme; label: string; swatch: string }[] = [
    { value: "cream", label: t("Versely Cream"), swatch: "#f9ebd7" },
    { value: "daylight", label: t("Daylight"), swatch: "#ffffff" },
    { value: "dark", label: t("Warm Dark"), swatch: "#30251f" },
    { value: "system", label: t("Match device"), swatch: "linear-gradient(135deg, #ffffff 50%, #30251f 50%)" },
  ];

  return (
    <div ref={root} className="relative">
      <button
        ref={button}
        type="button"
        aria-expanded={open}
        aria-controls={panel}
        onClick={() => setOpen((o) => !o)}
        className="inline-flex min-h-11 items-center gap-2 rounded-full border border-border bg-surface/70 px-3 text-sm font-medium text-foreground transition-colors hover:bg-surface"
      >
        <svg aria-hidden="true" viewBox="0 0 20 20" className="h-4 w-4 text-accent" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
          <circle cx="10" cy="10" r="7.5" />
          <path d="M2.5 10h15M10 2.5c2.2 2.4 2.2 12.6 0 15M10 2.5c-2.2 2.4-2.2 12.6 0 15" />
        </svg>
        <span>{LANGUAGES.find((l) => l.code === lang)?.code.toUpperCase()}</span>
        <span className="sr-only">{t("Appearance and language")}</span>
      </button>
      {open ? (
        <div
          id={panel}
          className="absolute right-0 z-50 mt-2 w-72 max-w-[calc(100vw-2rem)] origin-top-right rounded-2xl border border-border bg-surface p-4 shadow-xl motion-safe:animate-[menu-in_140ms_cubic-bezier(0.23,1,0.32,1)]"
        >
          <fieldset>
            <legend className="text-xs font-semibold uppercase tracking-wider text-muted">{t("Appearance")}</legend>
            <div className="mt-2 grid gap-1">
              {looks.map((option) => (
                <label key={option.value} className="flex min-h-11 cursor-pointer items-center gap-3 rounded-xl px-2 hover:bg-surface-2">
                  <input type="radio" name="vs-look" value={option.value} checked={look === option.value} onChange={() => chooseLook(option.value)} className="accent-[var(--accent-strong)]" />
                  <span aria-hidden="true" className="h-5 w-5 rounded-full border border-border" style={{ background: option.swatch }} />
                  <span>{option.label}</span>
                </label>
              ))}
            </div>
          </fieldset>
          <fieldset className="mt-4 border-t border-border pt-3">
            <legend className="sr-only">{t("Language")}</legend>
            <p aria-hidden="true" className="text-xs font-semibold uppercase tracking-wider text-muted">
              {t("Language")}
            </p>
            <div className="mt-2 grid gap-1">
              {LANGUAGES.map((option) => (
                <label key={option.code} lang={option.html} className="flex min-h-11 cursor-pointer items-center gap-3 rounded-xl px-2 hover:bg-surface-2">
                  <input type="radio" name="vs-lang" value={option.code} checked={language === option.code} onChange={() => chooseLang(option.code)} className="accent-[var(--accent-strong)]" />
                  <span>{option.name}</span>
                </label>
              ))}
            </div>
            <p className="mt-2 text-xs leading-relaxed text-muted">{t("Sermons keep their own language, and passages open in the Bible you choose.")}</p>
          </fieldset>
        </div>
      ) : null}
    </div>
  );
}
