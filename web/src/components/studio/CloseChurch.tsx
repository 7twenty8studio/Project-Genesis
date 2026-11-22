"use client";

import { useState, useTransition } from "react";
import { closeChurch } from "@/app/studio/actions";
import { translator, type Lang } from "@/lib/i18n";
import { refusalMessage } from "@/lib/studio";
import { Button, inputClass, Notice } from "./ui";

/**
 * Closing the church (owner only): the same as the app's Close Group. The
 * owner types the church's name to confirm; the database checks they own it.
 */
export function CloseChurch({ lang, church, name }: { lang: Lang; church: string; name: string }) {
  const t = translator(lang);
  const [open, setOpen] = useState(false);
  const [typed, setTyped] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const matches = typed.trim().toLocaleLowerCase() === name.trim().toLocaleLowerCase();

  const close = () =>
    start(async () => {
      setError(null);
      const result = await closeChurch(church, typed, name);
      if (result && !result.ok) setError(t(refusalMessage(result.code)));
    });

  return (
    <section aria-labelledby="close-church" className="mt-8 rounded-3xl border border-border bg-surface p-5" data-testid="close-church">
      <h2 id="close-church" className="text-lg font-semibold">
        {t("Close this church")}
      </h2>
      <p className="mt-1 text-sm text-muted">
        {t("Closing it takes the church away for everyone: every sermon page and link stops working, and members lose the group in the Versely app. People keep their own notes. This can't be undone here.")}
      </p>
      {open ? (
        <div className="mt-3">
          <label htmlFor="close-church-name" className="block text-sm font-medium">
            {t("Type {name} to confirm", { name })}
          </label>
          <input id="close-church-name" className={`${inputClass} mt-1`} value={typed} autoComplete="off" onChange={(e) => setTyped(e.target.value)} />
          <div className="mt-3 flex flex-wrap gap-2">
            <Button danger disabled={!matches || pending} onClick={close}>
              {t("Close church")}
            </Button>
            <Button
              disabled={pending}
              onClick={() => {
                setOpen(false);
                setTyped("");
                setError(null);
              }}
            >
              {t("Cancel")}
            </Button>
          </div>
        </div>
      ) : (
        <div className="mt-3">
          <Button danger onClick={() => setOpen(true)}>
            {t("Close this church…")}
          </Button>
        </div>
      )}
      {error ? <Notice tone="alert">{error}</Notice> : null}
    </section>
  );
}
