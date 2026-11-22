"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { createSermon, reviewReports, setChurchRole, setListed } from "@/app/studio/actions";
import { translator, type Lang } from "@/lib/i18n";
import { refusalMessage } from "@/lib/studio";
import { runsChurch, type ChurchPerson, type StudioChurch, type StudioReport, type StudioSermon } from "@/lib/studio.server";
import { ChurchPeople, roleName } from "./ChurchPeople";
import { CloseChurch } from "./CloseChurch";
import { InviteMembers } from "./InviteMembers";
import { LocationsEditor } from "./LocationsEditor";
import { Button, Notice } from "./ui";
import { StatusBadge } from "./StatusBadge";

type Props = {
  lang: Lang;
  churches: StudioChurch[];
  church: StudioChurch;
  sermons: (StudioSermon & { day: string | null })[];
  reports: StudioReport[];
  invite: { invite_code: string; requires_approval: boolean } | null;
  /** The church's people (owner and admins only). */
  people: ChurchPerson[] | null;
  /** The signed-in person's account id. */
  userId: string;
};

/**
 * A church's sermons, newest first, with New Sermon. Owner and admins see
 * everything and the church's settings and people; a preacher sees their
 * own sermons, the church's published ones (read-only) and the invite code.
 */
export function ChurchHome({ lang, churches, church, sermons, reports, invite, people, userId }: Props) {
  const t = translator(lang);
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [listed, setListedState] = useState(church.listed);
  const [confirmStepDown, setConfirmStepDown] = useState(false);
  const admin = runsChurch(church);

  const run = (action: () => Promise<{ ok: boolean; code?: string } | void>) =>
    start(async () => {
      setError(null);
      const result = await action();
      if (result && !result.ok) setError(t(refusalMessage(result.code ?? "")));
      else router.refresh();
    });

  /** Who started and last edited a sermon, when it isn't only the person looking. */
  const whoLine = (s: StudioSermon) => {
    if (s.mine && (!s.edited_by || s.edited_by === s.started_by)) return null;
    const parts = [];
    if (s.started_by && !s.mine) parts.push(t("Started by {name}", { name: s.started_by }));
    if (s.edited_by && s.edited_by !== s.started_by) parts.push(t("Last edited by {name}", { name: s.edited_by }));
    return parts.join(" · ") || null;
  };

  return (
    <main className="mx-auto max-w-3xl px-4 pb-24 pt-8 sm:px-6">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-sm font-medium uppercase tracking-wider text-accent">{t("Church Studio")}</p>
          {churches.length > 1 ? (
            <label className="mt-2 block">
              <span className="sr-only">{t("Church")}</span>
              <span className="relative inline-block max-w-full">
                <select
                  className="min-h-12 max-w-full appearance-none truncate rounded-2xl border border-border bg-surface py-2 pl-4 pr-12 text-xl font-semibold hover:bg-surface-2"
                  value={church.id}
                  onChange={(e) => router.push(`/studio?church=${e.target.value}`)}
                >
                  {churches.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name}
                    </option>
                  ))}
                </select>
                <svg
                  aria-hidden="true"
                  viewBox="0 0 20 20"
                  className="pointer-events-none absolute right-4 top-1/2 h-5 w-5 -translate-y-1/2 text-accent-strong"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2.25"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M5 7.5l5 5 5-5" />
                </svg>
              </span>
            </label>
          ) : (
            <h1 className="mt-1 text-3xl font-semibold tracking-tight">{church.name}</h1>
          )}
          <p className="mt-2 text-sm text-muted" data-testid="your-role">
            {t("Your role: {role}", { role: roleName(church.role, t) })}
          </p>
          <Link href="/studio?new=1" className="mt-1 inline-block text-sm font-medium text-accent underline-offset-4 hover:underline">
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
          <p className="mt-1 text-sm text-muted">
            {admin
              ? t("Readers reported these. Three reports hide a sermon until you review it.")
              : t("Readers reported these sermons of yours. Three reports hide a sermon until an admin reviews it.")}
          </p>
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
                {admin ? (
                  <div className="mt-3 flex flex-wrap gap-2">
                    <Button disabled={pending} onClick={() => run(() => reviewReports(r.sermon_id, true))}>
                      {t("Keep it published")}
                    </Button>
                    <Button disabled={pending} onClick={() => run(() => reviewReports(r.sermon_id, false))}>
                      {t("Unpublish it")}
                    </Button>
                  </div>
                ) : null}
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
          <p className="mt-3 rounded-3xl border border-dashed border-border p-6 text-muted">{t("No sermons yet. Start one, or paste or import an outline you already have.")}</p>
        ) : (
          <ul className="mt-3 divide-y divide-border overflow-hidden rounded-3xl border border-border bg-surface">
            {sermons.map((s) => (
              <li key={s.id}>
                <a href={s.can_edit === false ? `/s/${s.slug}` : `/studio/${s.id}`} className="flex flex-wrap items-center justify-between gap-3 px-5 py-4 hover:bg-surface-2">
                  <span className="min-w-0">
                    <span className="block truncate font-medium">{s.title || t("Untitled sermon")}</span>
                    <span className="block text-sm text-muted">{[s.speaker, s.day, s.series].filter(Boolean).join(" · ") || t("No details yet")}</span>
                    {whoLine(s) ? <span className="block text-sm text-muted">{whoLine(s)}</span> : null}
                  </span>
                  {s.can_edit === false ? <span className="rounded-full bg-surface-2 px-3 py-1 text-sm">{t("View only")}</span> : <StatusBadge sermon={s} t={t} />}
                </a>
              </li>
            ))}
          </ul>
        )}
      </section>

      {invite ? (
        <InviteMembers
          key={`invite-${church.id}`}
          lang={lang}
          church={church.id}
          name={church.name}
          code={invite.invite_code}
          requiresApproval={invite.requires_approval}
          canRenew={admin}
        />
      ) : null}

      {admin && people ? <ChurchPeople key={`people-${church.id}`} lang={lang} church={church.id} you={church.role} people={people} /> : null}

      {admin ? <LocationsEditor key={church.id} lang={lang} church={church.id} initial={church.locations ?? []} /> : null}

      {admin ? (
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
      ) : null}

      {church.role === "owner" ? <CloseChurch key={`close-${church.id}`} lang={lang} church={church.id} name={church.name} /> : null}

      {church.role === "preacher" ? (
        <section aria-labelledby="your-role-title" className="mt-8 rounded-3xl border border-border bg-surface p-5">
          <h2 id="your-role-title" className="text-lg font-semibold">
            {t("You're a preacher here")}
          </h2>
          <p className="mt-1 text-sm text-muted">
            {t("You write and publish the sermons you start. The church's owner and admins look after its settings, its people and every sermon.")}
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            {confirmStepDown ? (
              <>
                <Button
                  danger
                  disabled={pending}
                  onClick={() =>
                    run(async () => {
                      const result = await setChurchRole(church.id, userId, "member");
                      if (result.ok) router.push("/studio");
                      return result;
                    })
                  }
                >
                  {t("Stop being a preacher")}
                </Button>
                <Button onClick={() => setConfirmStepDown(false)}>{t("Cancel")}</Button>
              </>
            ) : (
              <Button onClick={() => setConfirmStepDown(true)}>{t("Step down as preacher")}</Button>
            )}
          </div>
          {confirmStepDown ? (
            <p className="mt-2 text-sm text-muted" role="alert">
              {t("Your sermons stay with the church, and its admins can hand them to someone else. You stay a member.")}
            </p>
          ) : null}
        </section>
      ) : null}
    </main>
  );
}
