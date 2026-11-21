"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { createSermon, reviewReports, setListed } from "@/app/studio/actions";
import { translator, type Lang } from "@/lib/i18n";
import { refusalMessage } from "@/lib/studio";
import type { StudioChurch, StudioReport, StudioSermon } from "@/lib/studio.server";
import { Button, Notice } from "./ui";
import { StatusBadge } from "./StatusBadge";

type Props = {
  lang: Lang;
  churches: StudioChurch[];
  church: StudioChurch;
  sermons: (StudioSermon & { day: string | null })[];
  reports: StudioReport[];
};

/** A church's sermons: drafts and published ones, newest first, with New Sermon. */
export function ChurchHome({ lang, churches, church, sermons, reports }: Props) {
  const t = translator(lang);
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [listed, setListedState] = useState(church.listed);

  const run = (action: () => Promise<{ ok: boolean; code?: string } | void>) =>
    start(async () => {
      setError(null);
      const result = await action();
      if (result && !result.ok) setError(t(refusalMessage(result.code ?? "")));
      else router.refresh();
    });

  return (
    <main className="mx-auto max-w-3xl px-4 pb-24 pt-8 sm:px-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-sm font-medium uppercase tracking-wider text-accent">{t("Church Studio")}</p>
          {churches.length > 1 ? (
            <label className="mt-1 block">
              <span className="sr-only">{t("Church")}</span>
              <select
                className="mt-1 rounded-xl border border-border bg-surface px-3 py-2 text-2xl font-semibold"
                value={church.id}
                onChange={(e) => router.push(`/studio?church=${e.target.value}`)}
              >
                {churches.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </label>
          ) : (
            <h1 className="mt-1 text-3xl font-semibold tracking-tight">{church.name}</h1>
          )}
          <Link href="/studio?new=1" className="mt-2 inline-block text-sm font-medium text-accent underline-offset-4 hover:underline">
            {t("Start another church or ministry")}
          </Link>
        </div>
        <Button primary disabled={pending} onClick={() => run(() => createSermon(church.id))}>
          {t("New sermon")}
        </Button>
      </div>
      {churches.length > 1 ? <h1 className="sr-only">{church.name}</h1> : null}
      {error ? <Notice>{error}</Notice> : null}

      {reports.length ? (
        <section aria-labelledby="reports" className="mt-8 rounded-3xl border border-border bg-surface p-5">
          <h2 id="reports" className="text-lg font-semibold">
            {t("Reported sermons")}
          </h2>
          <p className="mt-1 text-sm text-muted">{t("Readers reported these. Three reports hide a sermon until you review it.")}</p>
          <ul className="mt-4 space-y-4">
            {reports.map((r) => (
              <li key={r.sermon_id} className="rounded-2xl bg-surface-2 p-4">
                <p className="font-medium">{r.title || t("Untitled sermon")}</p>
                <p className="text-sm text-muted">
                  {r.report_count === 1 ? t("1 report") : t("{count} reports", { count: r.report_count })}
                  {r.hidden ? ` · ${t("Hidden until reviewed")}` : ""}
                </p>
                {r.reasons.length ? (
                  <ul className="mt-2 list-disc pl-5 text-sm">
                    {r.reasons.map((reason, i) => (
                      <li key={i}>{reason}</li>
                    ))}
                  </ul>
                ) : null}
                <div className="mt-3 flex flex-wrap gap-2">
                  <Button disabled={pending} onClick={() => run(() => reviewReports(r.sermon_id, true))}>
                    {t("Keep it published")}
                  </Button>
                  <Button disabled={pending} onClick={() => run(() => reviewReports(r.sermon_id, false))}>
                    {t("Unpublish it")}
                  </Button>
                </div>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      <section aria-labelledby="sermons" className="mt-8">
        <h2 id="sermons" className="text-lg font-semibold">
          {t("Sermons")}
        </h2>
        {sermons.length === 0 ? (
          <p className="mt-3 rounded-3xl border border-dashed border-border p-6 text-muted">
            {t("No sermons yet. Start one, or paste or import an outline you already have.")}
          </p>
        ) : (
          <ul className="mt-3 divide-y divide-border overflow-hidden rounded-3xl border border-border bg-surface">
            {sermons.map((s) => (
              <li key={s.id}>
                <a href={`/studio/${s.id}`} className="flex flex-wrap items-center justify-between gap-3 px-5 py-4 hover:bg-surface-2">
                  <span className="min-w-0">
                    <span className="block truncate font-medium">{s.title || t("Untitled sermon")}</span>
                    <span className="block text-sm text-muted">{[s.speaker, s.day, s.series].filter(Boolean).join(" · ") || t("No details yet")}</span>
                  </span>
                  <StatusBadge sermon={s} t={t} />
                </a>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section aria-labelledby="listing" className="mt-8 rounded-3xl border border-border bg-surface p-5">
        <h2 id="listing" className="text-lg font-semibold">
          {t("Finding your church")}
        </h2>
        <label className="mt-3 flex items-start gap-3">
          <input
            type="checkbox"
            className="mt-1 size-5 accent-[var(--accent-strong)]"
            checked={listed}
            disabled={pending}
            onChange={(e) => {
              const value = e.target.checked;
              setListedState(value);
              run(() => setListed(church.id, value));
            }}
          />
          <span>
            <span className="block font-medium">{t("List this church in Versely's church search")}</span>
            <span className="block text-sm text-muted">{t("People can find it by name and open its latest sermons shared by link. Members-only sermons are never listed.")}</span>
          </span>
        </label>
      </section>
    </main>
  );
}
