"use client";

import { useEffect, useRef, useState, useTransition } from "react";
import { enterGiveaway } from "@/app/launch/actions";
import { translator, type Lang } from "@/lib/i18n";
import { entryProblem, looksLikeEmail, ticket, tidyName } from "@/lib/giveaway";
import { Button, Field, inputClass } from "@/components/studio/ui";

const KIOSK_RESET_MS = 15_000;

/** The entry form, then the person's number on a golden ticket. On the lobby iPad (kiosk) it clears itself for the next person. */
export function EntryForm({ lang, kiosk }: { lang: Lang; kiosk: boolean }) {
  const t = translator(lang);
  const [pending, start] = useTransition();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [news, setNews] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const [number, setNumber] = useState<number | null>(null);
  const nameRef = useRef<HTMLInputElement>(null);

  const reset = () => {
    setName("");
    setEmail("");
    setNews(false);
    setProblem(null);
    setNumber(null);
    setTimeout(() => nameRef.current?.focus(), 0);
  };

  useEffect(() => {
    if (!kiosk || number === null) return;
    const timer = setTimeout(reset, KIOSK_RESET_MS);
    return () => clearTimeout(timer);
  }, [kiosk, number]);

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    setProblem(null);
    if (!tidyName(name)) return setProblem(t(entryProblem("invalid_name")));
    if (!looksLikeEmail(email)) return setProblem(t(entryProblem("invalid_email")));
    start(async () => {
      const result = await enterGiveaway(name, email, news);
      if (result.ok) setNumber(result.value);
      else setProblem(t(entryProblem(result.code)));
    });
  };

  if (number !== null) {
    return (
      <div className="rise-in">
        <div className="golden-ticket overflow-hidden rounded-3xl px-8 py-10 text-center" role="status" data-testid="entry-number">
          <span className="sheen" aria-hidden="true" />
          <p className="text-sm font-semibold uppercase tracking-[0.25em]">{t("You're in")}</p>
          <p className="mt-2 text-7xl font-semibold tabular-nums tracking-tight sm:text-8xl">{ticket(number)}</p>
          <p className="mt-3 text-base font-medium">{t("Keep this number. It's how we'll call you.")}</p>
        </div>
        {kiosk ? (
          <div className="mt-6 flex justify-center">
            <Button primary className="min-h-14 px-10 text-lg" onClick={reset}>
              {t("Next person")}
            </Button>
          </div>
        ) : (
          <p className="mt-6 text-center text-muted">{t("Take a screenshot so you have it when numbers are called.")}</p>
        )}
      </div>
    );
  }

  return (
    <form onSubmit={submit} noValidate className="rounded-3xl border border-border bg-surface p-6 shadow-sm">
      <Field id="gw-name" label={t("First name")}>
        <input
          ref={nameRef}
          id="gw-name"
          className={`${inputClass} ${kiosk ? "min-h-14 text-xl" : "min-h-12"}`}
          autoComplete="given-name"
          maxLength={40}
          value={name}
          onChange={(e) => setName(e.target.value)}
          autoFocus={kiosk}
          required
        />
      </Field>
      <Field id="gw-email" label={t("Email")} hint={t("Only to reach you if you win.")}>
        <input
          id="gw-email"
          type="email"
          inputMode="email"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          className={`${inputClass} ${kiosk ? "min-h-14 text-xl" : "min-h-12"}`}
          autoComplete={kiosk ? "off" : "email"}
          maxLength={254}
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          aria-describedby="gw-email-hint"
          required
        />
      </Field>
      <label className="mt-5 flex cursor-pointer items-start gap-3">
        <input type="checkbox" className="mt-1 h-5 w-5 accent-[#7a4e2d]" checked={news} onChange={(e) => setNews(e.target.checked)} />
        <span>{t("Also send me Versely news (optional)")}</span>
      </label>
      {problem ? (
        <p role="alert" className="mt-5 rounded-2xl border border-border bg-surface-2 p-4">
          {problem}
        </p>
      ) : null}
      <Button primary type="submit" disabled={pending} className={`mt-6 w-full ${kiosk ? "min-h-14 text-lg" : "min-h-12"}`}>
        {pending ? t("Entering…") : t("Enter the giveaway")}
      </Button>
    </form>
  );
}
