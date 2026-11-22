"use client";

import { useState, useTransition } from "react";
import { findMyNumber } from "@/app/launch/actions";
import { translator, type Lang } from "@/lib/i18n";
import { looksLikeEmail, ticket } from "@/lib/giveaway";
import { Button, inputClass } from "@/components/studio/ui";

/** "Forgot your number?": the same email shows the number again, even after entries close. */
export function FindNumber({ lang, startOpen = false }: { lang: Lang; startOpen?: boolean }) {
  const t = translator(lang);
  const [open, setOpen] = useState(startOpen);
  const [email, setEmail] = useState("");
  const [pending, start] = useTransition();
  const [found, setFound] = useState<{ number: number; name: string } | null>(null);
  const [problem, setProblem] = useState<string | null>(null);

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    setProblem(null);
    setFound(null);
    if (!looksLikeEmail(email)) return setProblem(t("Check your email address."));
    start(async () => {
      const result = await findMyNumber(email);
      if (!result.ok) setProblem(t("That didn't go through. Check your connection and try again."));
      else if (result.value === null) setProblem(t("We couldn't find that email. Use the one you entered with."));
      else setFound(result.value);
    });
  };

  if (!open) {
    return (
      <button type="button" onClick={() => setOpen(true)} className="text-base font-medium text-accent underline underline-offset-4">
        {t("Forgot your number?")}
      </button>
    );
  }

  return (
    <div className="rounded-3xl border border-border bg-surface p-6">
      <p className="text-lg font-semibold">{t("Forgot your number?")}</p>
      <p className="mt-1 text-muted">{t("Enter the email you used and we'll show it again.")}</p>
      {found ? (
        <div className="golden-ticket rise-in mt-5 overflow-hidden rounded-3xl px-6 py-6 text-center" role="status" data-testid="found-number">
          <span className="sheen" aria-hidden="true" />
          <p className="text-sm font-semibold uppercase tracking-[0.25em]">{found.name}</p>
          <p className="mt-1 text-6xl font-semibold tabular-nums tracking-tight">{ticket(found.number)}</p>
        </div>
      ) : (
        <form onSubmit={submit} noValidate className="mt-4 flex flex-col gap-3 sm:flex-row">
          <label htmlFor="gw-find" className="sr-only">
            {t("Email")}
          </label>
          <input
            id="gw-find"
            type="email"
            inputMode="email"
            autoCapitalize="none"
            autoCorrect="off"
            spellCheck={false}
            autoComplete="email"
            maxLength={254}
            className={`${inputClass} min-h-12`}
            value={email}
            onChange={(e) => setEmail(e.target.value)}
          />
          <Button primary type="submit" disabled={pending} className="min-h-12 px-6">
            {pending ? t("Looking…") : t("Show my number")}
          </Button>
        </form>
      )}
      {problem ? (
        <p role="alert" className="mt-4 rounded-2xl border border-border bg-surface-2 p-4">
          {problem}
        </p>
      ) : null}
    </div>
  );
}
