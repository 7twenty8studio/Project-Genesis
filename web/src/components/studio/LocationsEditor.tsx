"use client";

import { useState, useTransition } from "react";
import { setLocations } from "@/app/studio/actions";
import { translator, type Lang } from "@/lib/i18n";
import { LIMITS, WEEKDAYS, dayNames, formatTime, localToday, timeOptions, type ChurchLocation, type Gathering, type Weekday } from "@/lib/locations";
import { refusalMessage } from "@/lib/studio";
import { Button, Notice, inputClass } from "./ui";

const TIMES = timeOptions();
const blankGathering = (): Gathering => ({ day: "sun", time: "10:00", note: "" });
const blankPlace = (): ChurchLocation => ({ name: "", street: "", city: "", region: "", postal_code: "", country: "", gatherings: [blankGathering()], address: "", times: "" });

/** A place as the form edits it: an address typed on one line before there were parts starts in Street. */
function editable(place: ChurchLocation): ChurchLocation {
  const parts = [place.street, place.city, place.region, place.postal_code, place.country].some((p) => p?.trim());
  return { ...place, street: parts ? (place.street ?? "") : place.address, gatherings: place.gatherings ?? [] };
}

/** The church's Locations and Times: shown on every sermon page, and changed here without publishing again. */
export function LocationsEditor({ lang, church, initial }: { lang: Lang; church: string; initial: ChurchLocation[] }) {
  const t = translator(lang);
  const names = dayNames(t);
  const [places, setPlaces] = useState<ChurchLocation[]>(() => initial.map(editable));
  const [pending, start] = useTransition();
  const [message, setMessage] = useState<{ text: string; tone: "alert" | "status" } | null>(null);

  const edit = (i: number, change: Partial<ChurchLocation>) => {
    setMessage(null);
    setPlaces((list) => list.map((p, k) => (k === i ? { ...p, ...change } : p)));
  };
  const editGathering = (i: number, j: number, change: Partial<Gathering>) =>
    edit(i, { gatherings: (places[i].gatherings ?? []).map((g, k) => (k === j ? { ...g, ...change } : g)) });

  const save = () =>
    start(async () => {
      setMessage(null);
      const result = await setLocations(church, places);
      if (result.ok) {
        setPlaces(result.locations.map(editable));
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
        {places.map((place, i) => {
          const id = `place-${i}`;
          const field = (key: "street" | "city" | "region" | "postal_code" | "country", label: string, auto: string, narrow = false) => (
            <div className="mt-3">
              <label htmlFor={`${id}-${key}`} className="block text-sm font-medium">
                {label}
              </label>
              <input
                id={`${id}-${key}`}
                className={`${inputClass} mt-1 ${narrow ? "sm:max-w-xs" : ""}`}
                value={place[key] ?? ""}
                maxLength={LIMITS[key]}
                autoComplete={auto}
                onChange={(e) => edit(i, { [key]: e.target.value })}
              />
            </div>
          );
          return (
            <li key={i} className="rounded-2xl bg-surface-2 p-4 sm:p-5">
              <label htmlFor={`${id}-name`} className="block text-sm font-medium">
                {t("Name")}
              </label>
              <input
                id={`${id}-name`}
                className={`${inputClass} mt-1`}
                value={place.name}
                maxLength={LIMITS.name}
                placeholder={t("Main Campus")}
                onChange={(e) => edit(i, { name: e.target.value })}
              />

              <fieldset className="mt-5">
                <legend className="font-semibold">{t("Address")}</legend>
                {field("street", t("Street address"), "address-line1")}
                {field("city", t("City"), "address-level2")}
                {field("region", t("State or province"), "address-level1", true)}
                {field("postal_code", t("ZIP or postal code"), "postal-code", true)}
                {field("country", t("Country"), "country-name", true)}
              </fieldset>

              <fieldset className="mt-6">
                <legend className="font-semibold">{t("When you meet")}</legend>
                {(place.gatherings ?? []).length === 0 ? <p className="mt-2 text-sm text-muted">{t("No times yet.")}</p> : null}
                <ul className="mt-3 space-y-3">
                  {(place.gatherings ?? []).map((g, j) => {
                    const gid = `${id}-time-${j}`;
                    const weekly = !!g.day;
                    return (
                      <li key={j} className="rounded-xl border border-border bg-surface p-3">
                        <div className="grid gap-3 sm:grid-cols-3">
                          <div>
                            <label htmlFor={`${gid}-repeat`} className="block text-sm font-medium">
                              {t("Repeats")}
                            </label>
                            <select
                              id={`${gid}-repeat`}
                              className={`${inputClass} mt-1`}
                              value={weekly ? "weekly" : "once"}
                              onChange={(e) =>
                                editGathering(i, j, e.target.value === "weekly" ? { day: "sun", date: null } : { day: null, date: g.date ?? localToday() })
                              }
                            >
                              <option value="weekly">{t("Every week")}</option>
                              <option value="once">{t("One date")}</option>
                            </select>
                          </div>
                          <div>
                            <label htmlFor={`${gid}-when`} className="block text-sm font-medium">
                              {weekly ? t("Day") : t("Date")}
                            </label>
                            {weekly ? (
                              <select id={`${gid}-when`} className={`${inputClass} mt-1`} value={g.day ?? "sun"} onChange={(e) => editGathering(i, j, { day: e.target.value as Weekday })}>
                                {WEEKDAYS.map((d) => (
                                  <option key={d} value={d}>
                                    {names.single[d]}
                                  </option>
                                ))}
                              </select>
                            ) : (
                              <input
                                id={`${gid}-when`}
                                type="date"
                                className={`${inputClass} mt-1`}
                                value={g.date ?? ""}
                                min={localToday()}
                                required
                                onChange={(e) => editGathering(i, j, { date: e.target.value })}
                              />
                            )}
                          </div>
                          <div>
                            <label htmlFor={`${gid}-time`} className="block text-sm font-medium">
                              {t("Time")}
                            </label>
                            <select id={`${gid}-time`} className={`${inputClass} mt-1`} value={g.time} onChange={(e) => editGathering(i, j, { time: e.target.value })}>
                              {(TIMES.includes(g.time) ? TIMES : [g.time, ...TIMES]).map((time) => (
                                <option key={time} value={time}>
                                  {formatTime(time, lang)}
                                </option>
                              ))}
                            </select>
                          </div>
                        </div>
                        <div className="mt-3 flex flex-wrap items-end gap-3">
                          <div className="min-w-48 flex-1">
                            <label htmlFor={`${gid}-note`} className="block text-sm font-medium">
                              {t("Note (optional)")}
                            </label>
                            <input
                              id={`${gid}-note`}
                              className={`${inputClass} mt-1`}
                              value={g.note ?? ""}
                              maxLength={LIMITS.note}
                              placeholder={t("e.g. Spanish service")}
                              onChange={(e) => editGathering(i, j, { note: e.target.value })}
                            />
                          </div>
                          <Button disabled={pending} onClick={() => edit(i, { gatherings: (place.gatherings ?? []).filter((_, k) => k !== j) })}>
                            {t("Remove this time")}
                          </Button>
                        </div>
                      </li>
                    );
                  })}
                </ul>
                {(place.gatherings ?? []).length < LIMITS.gatherings ? (
                  <Button className="mt-3" disabled={pending} onClick={() => edit(i, { gatherings: [...(place.gatherings ?? []), blankGathering()] })}>
                    {t("Add a time")}
                  </Button>
                ) : null}
                {place.times.trim() ? (
                  <div className="mt-4">
                    <label htmlFor={`${id}-times`} className="block text-sm font-medium">
                      {t("Other times")}
                    </label>
                    <textarea id={`${id}-times`} className={`${inputClass} mt-1 min-h-20`} value={place.times} maxLength={300} onChange={(e) => edit(i, { times: e.target.value })} />
                  </div>
                ) : null}
              </fieldset>

              <div className="mt-5 flex justify-end border-t border-border pt-4">
                <Button disabled={pending} onClick={() => setPlaces((list) => list.filter((_, k) => k !== i))}>
                  {t("Remove {name}", { name: place.name.trim() || t("this place") })}
                </Button>
              </div>
            </li>
          );
        })}
      </ol>
      {message ? <Notice tone={message.tone}>{message.text}</Notice> : null}
      <div className="mt-4 flex flex-wrap gap-3">
        {places.length < LIMITS.places ? (
          <Button disabled={pending} onClick={() => setPlaces((list) => [...list, blankPlace()])}>
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
