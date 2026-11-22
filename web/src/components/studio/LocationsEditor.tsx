"use client";

import { useState, useTransition } from "react";
import { setLocations } from "@/app/studio/actions";
import { translator, type Lang } from "@/lib/i18n";
import type { ChurchLocation } from "@/lib/outline";
import { refusalMessage } from "@/lib/studio";
import { Button, Notice, inputClass } from "./ui";

const MAX_PLACES = 10;
const blank = (): ChurchLocation => ({ name: "", address: "", times: "" });

/** The church's Locations and Times: shown on every sermon page, and changed here without publishing again. */
export function LocationsEditor({ lang, church, initial }: { lang: Lang; church: string; initial: ChurchLocation[] }) {
  const t = translator(lang);
  const [places, setPlaces] = useState<ChurchLocation[]>(initial);
  const [pending, start] = useTransition();
  const [message, setMessage] = useState<{ text: string; tone: "alert" | "status" } | null>(null);

  const change = (i: number, field: keyof ChurchLocation, value: string) => {
    setMessage(null);
    setPlaces((list) => list.map((p, k) => (k === i ? { ...p, [field]: value } : p)));
  };
  const save = () =>
    start(async () => {
      setMessage(null);
      const result = await setLocations(church, places);
      if (result.ok) {
        setPlaces(result.locations);
        setMessage({ text: t("Saved. Every sermon page shows it now."), tone: "status" });
      } else setMessage({ text: t(refusalMessage(result.code)), tone: "alert" });
    });

  return (
    <section aria-labelledby="locations" className="mt-8 rounded-3xl border border-border bg-surface p-5">
      <h2 id="locations" className="text-lg font-semibold">
        {t("Locations and Times")}
      </h2>
      <p className="mt-1 text-sm text-muted">{t("Where and when people can join you. It shows on every sermon page, with a link to directions.")}</p>
      {places.length === 0 ? <p className="mt-4 rounded-2xl border border-dashed border-border p-4 text-muted">{t("No places yet.")}</p> : null}
      <ol className="mt-4 space-y-4">
        {places.map((place, i) => (
          <li key={i} className="rounded-2xl bg-surface-2 p-4">
            <fieldset>
              <legend className="sr-only">{t("Place {number}", { number: i + 1 })}</legend>
              <label htmlFor={`place-${i}-name`} className="block text-sm font-medium">
                {t("Name")}
              </label>
              <input
                id={`place-${i}-name`}
                className={`${inputClass} mt-1`}
                value={place.name}
                maxLength={80}
                placeholder={t("Main Campus")}
                onChange={(e) => change(i, "name", e.target.value)}
              />
              <label htmlFor={`place-${i}-address`} className="mt-3 block text-sm font-medium">
                {t("Address")}
              </label>
              <input
                id={`place-${i}-address`}
                className={`${inputClass} mt-1`}
                value={place.address}
                maxLength={200}
                autoComplete="street-address"
                onChange={(e) => change(i, "address", e.target.value)}
              />
              <label htmlFor={`place-${i}-times`} className="mt-3 block text-sm font-medium">
                {t("Times")}
              </label>
              <p id={`place-${i}-times-hint`} className="text-sm text-muted">
                {t("One line for each gathering, like \"Sundays 9:00 and 11:00 AM\".")}
              </p>
              <textarea
                id={`place-${i}-times`}
                aria-describedby={`place-${i}-times-hint`}
                className={`${inputClass} mt-1 min-h-20`}
                value={place.times}
                maxLength={300}
                onChange={(e) => change(i, "times", e.target.value)}
              />
              <div className="mt-3 flex justify-end">
                <Button disabled={pending} onClick={() => setPlaces((list) => list.filter((_, k) => k !== i))}>
                  {t("Remove {name}", { name: place.name.trim() || t("this place") })}
                </Button>
              </div>
            </fieldset>
          </li>
        ))}
      </ol>
      {message ? <Notice tone={message.tone}>{message.text}</Notice> : null}
      <div className="mt-4 flex flex-wrap gap-3">
        {places.length < MAX_PLACES ? (
          <Button disabled={pending} onClick={() => setPlaces((list) => [...list, blank()])}>
            {t("Add a place")}
          </Button>
        ) : null}
        <Button primary disabled={pending} onClick={save}>
          {pending ? t("Saving…") : t("Save locations")}
        </Button>
      </div>
    </section>
  );
}
