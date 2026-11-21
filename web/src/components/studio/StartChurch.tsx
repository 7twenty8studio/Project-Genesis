"use client";

import { useState, useTransition } from "react";
import { startChurch, turnOnSermons } from "@/app/studio/actions";
import { translator, type Lang } from "@/lib/i18n";
import { refusalMessage } from "@/lib/studio";
import { Button, Field, Notice, inputClass } from "./ui";

type Props = {
  lang: Lang;
  /** The person's name in Versely; null asks for it (it's how their church sees them). */
  yourName: string | null;
  /** A suggestion for that name, from the sign-in. */
  suggestedName: string;
  /** Groups they already own in the app, with sermons off. */
  groups: { id: string; name: string }[];
  first: boolean;
};

/** Church Studio's first step: name a new church, or turn sermons on for a group made in the app. */
export function StartChurch({ lang, yourName, suggestedName, groups, first }: Props) {
  const t = translator(lang);
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [church, setChurch] = useState("");
  const [name, setName] = useState(suggestedName);

  const run = (action: () => Promise<{ ok: boolean; code?: string } | void>) =>
    start(async () => {
      setError(null);
      const result = await action();
      if (result && !result.ok) setError(t(refusalMessage(result.code ?? "")));
    });

  return (
    <div className="grid gap-6">
      <form
        className="rounded-3xl border border-border bg-surface p-6 shadow-sm sm:p-8"
        onSubmit={(e) => {
          e.preventDefault();
          run(() => startChurch(church, yourName ? null : name));
        }}
      >
        <h2 className="text-2xl font-semibold tracking-tight">{first ? t("Start your church or ministry") : t("Your new church or ministry")}</h2>
        <p className="mt-2 leading-relaxed text-muted">
          {t("It's also a group in the Versely app, so people can join it there with its invite code.")}
        </p>
        <Field id="church-name" label={t("Church or ministry name")} hint={t("Shown under each sermon: a church, a ministry like a youth group, or your own name if you speak on your own.")}>
          <input
            id="church-name"
            className={inputClass}
            value={church}
            onChange={(e) => setChurch(e.target.value)}
            maxLength={60}
            required
            autoComplete="organization"
            placeholder={t("Grace Community Church")}
          />
        </Field>
        {yourName ? null : (
          <Field id="your-name" label={t("Your name")} hint={t("How people see you in Versely. You can change it in the app.")}>
            <input id="your-name" className={inputClass} value={name} onChange={(e) => setName(e.target.value)} maxLength={40} required autoComplete="name" />
          </Field>
        )}
        {error ? <Notice>{error}</Notice> : null}
        <div className="mt-6">
          <Button primary type="submit" disabled={pending || church.trim().length === 0} className="min-h-12 px-7 text-base">
            {pending ? t("Starting…") : t("Create")}
          </Button>
        </div>
      </form>

      {groups.length ? (
        <section aria-labelledby="your-groups" className="rounded-3xl border border-border bg-surface-2/60 p-6 sm:p-8">
          <h2 id="your-groups" className="text-lg font-semibold">
            {t("Or use a group you already lead")}
          </h2>
          <p className="mt-1 text-muted">{t("Turn on sermons for a group you made in the Versely app. Its members can read them right away.")}</p>
          <ul className="mt-4 divide-y divide-border overflow-hidden rounded-2xl border border-border bg-surface">
            {groups.map((g) => (
              <li key={g.id} className="flex flex-wrap items-center justify-between gap-3 px-5 py-3">
                <span className="font-medium">{g.name}</span>
                <Button disabled={pending} onClick={() => run(() => turnOnSermons(g.id))}>
                  {t("Turn on sermons")}
                </Button>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}
