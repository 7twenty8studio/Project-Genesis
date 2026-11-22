"use client";

import { useState, useTransition } from "react";
import { changeSermonOwner } from "@/app/studio/actions";
import type { Translate } from "@/lib/i18n";
import { refusalMessage } from "@/lib/studio";
import type { ChurchPerson } from "@/lib/studio.server";
import { roleName } from "./ChurchPeople";
import { Button, inputClass, Notice } from "./ui";

/**
 * Owner and admins: hand the sermon to another preacher or admin of the
 * church (for when a preacher is away or leaves). The database checks it.
 */
export function SermonOwner({ t, sermon, createdBy, writers }: { t: Translate; sermon: string; createdBy: string | null; writers: ChurchPerson[] }) {
  const [owner, setOwner] = useState(createdBy ?? "");
  const [chosen, setChosen] = useState(createdBy ?? "");
  const [pending, start] = useTransition();
  const [message, setMessage] = useState<{
    text: string;
    tone: "alert" | "status";
  } | null>(null);
  const current = writers.find((w) => w.user_id === owner);

  const hand = () =>
    start(async () => {
      setMessage(null);
      const result = await changeSermonOwner(sermon, chosen);
      if (result.ok) {
        setOwner(chosen);
        const name = writers.find((w) => w.user_id === chosen)?.name ?? "";
        setMessage({
          text: t("{name} looks after this sermon now.", { name }),
          tone: "status",
        });
      } else setMessage({ text: t(refusalMessage(result.code)), tone: "alert" });
    });

  return (
    <section aria-labelledby="owner-title" className="mt-6 rounded-3xl border border-border bg-surface p-5" data-testid="sermon-owner">
      <h2 id="owner-title" className="text-lg font-semibold">
        {t("Who looks after it")}
      </h2>
      <p className="mt-1 text-sm text-muted">
        {current
          ? t("{name} started this sermon and can edit and publish it. Admins can too.", { name: current.name })
          : t("Choose the preacher or admin who looks after this sermon.")}
      </p>
      <div className="mt-3 flex flex-wrap items-center gap-2">
        <label htmlFor="sermon-owner" className="sr-only">
          {t("Hand this sermon to")}
        </label>
        <select id="sermon-owner" className={`${inputClass} w-auto min-w-48`} value={chosen} disabled={pending} onChange={(e) => setChosen(e.target.value)}>
          {owner ? null : <option value="">{t("Choose someone")}</option>}
          {writers.map((w) => (
            <option key={w.user_id} value={w.user_id}>
              {w.name} · {roleName(w.role, t)}
            </option>
          ))}
        </select>
        <Button disabled={pending || !chosen || chosen === owner} onClick={hand}>
          {t("Hand it over")}
        </Button>
      </div>
      {message ? <Notice tone={message.tone}>{message.text}</Notice> : null}
    </section>
  );
}
