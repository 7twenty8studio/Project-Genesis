"use client";

import { useRouter } from "next/navigation";
import { useState, useTransition } from "react";
import { setChurchRole } from "@/app/studio/actions";
import { translator, type Lang, type Translate } from "@/lib/i18n";
import { refusalMessage } from "@/lib/studio";
import type { ChurchPerson, ChurchRole } from "@/lib/studio.server";
import { inputClass, Notice } from "./ui";

type Settable = "admin" | "preacher" | "member";

export const roleName = (role: ChurchPerson["role"], t: Translate) =>
  role === "owner" ? t("Owner") : role === "admin" ? t("Admin") : role === "preacher" ? t("Preacher") : t("Member");

/**
 * The church's people and their roles (owner and admins). The owner sets
 * anyone's role but their own; an admin makes members preachers and
 * preachers members, and never changes another admin. The database checks
 * all of it again.
 */
export function ChurchPeople({ lang, church, you, people }: { lang: Lang; church: string; you: ChurchRole; people: ChurchPerson[] }) {
  const t = translator(lang);
  const router = useRouter();
  const [pending, start] = useTransition();
  const [message, setMessage] = useState<{
    text: string;
    tone: "alert" | "status";
  } | null>(null);

  const choices = (p: ChurchPerson): Settable[] | null => {
    if (p.role === "owner" || p.me) return null;
    if (you === "owner") return ["admin", "preacher", "member"];
    if (p.role === "admin") return null;
    return ["preacher", "member"];
  };
  const change = (p: ChurchPerson, role: Settable) =>
    start(async () => {
      setMessage(null);
      const result = await setChurchRole(church, p.user_id, role);
      if (result.ok) {
        setMessage({
          text: t("{name} is now {role}.", {
            name: p.name,
            role: roleName(role, t),
          }),
          tone: "status",
        });
        router.refresh();
      } else setMessage({ text: t(refusalMessage(result.code)), tone: "alert" });
    });

  return (
    <section aria-labelledby="people" className="mt-8 rounded-3xl border border-border bg-surface p-5" data-testid="church-people">
      <h2 id="people" className="text-lg font-semibold">
        {t("People")}
      </h2>
      <p className="mt-1 text-sm text-muted">
        {you === "owner"
          ? t("Admins run the church with you: every sermon, settings and people. Preachers write and publish the sermons they start. Only you choose admins.")
          : t("Preachers write and publish the sermons they start. Make someone a preacher once they've joined with the invite code. Only the owner chooses admins.")}
      </p>
      <ul className="mt-4 divide-y divide-border">
        {people.map((p) => {
          const options = choices(p);
          const id = `role-${p.user_id}`;
          return (
            <li key={p.user_id} className="flex flex-wrap items-center justify-between gap-3 py-3">
              <span className="min-w-0">
                <span className="block truncate font-medium">
                  {p.name}
                  {p.me ? <span className="text-muted"> ({t("you")})</span> : null}
                </span>
                <span className="block text-sm text-muted">
                  {p.sermons === 0 ? t("No sermons started") : p.sermons === 1 ? t("1 sermon started") : t("{count} sermons started", { count: p.sermons })}
                </span>
              </span>
              {options ? (
                <span>
                  <label htmlFor={id} className="sr-only">
                    {t("Role for {name}", { name: p.name })}
                  </label>
                  <select id={id} className={`${inputClass} w-auto min-w-36`} value={p.role} disabled={pending} onChange={(e) => change(p, e.target.value as Settable)}>
                    {options.map((r) => (
                      <option key={r} value={r}>
                        {roleName(r, t)}
                      </option>
                    ))}
                  </select>
                </span>
              ) : (
                <span className="rounded-full bg-surface-2 px-3 py-1 text-sm font-medium">{roleName(p.role, t)}</span>
              )}
            </li>
          );
        })}
      </ul>
      {message ? <Notice tone={message.tone}>{message.text}</Notice> : null}
    </section>
  );
}
