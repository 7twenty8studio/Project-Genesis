"use client";

import { useId, useState } from "react";
import type { DraftRow } from "@/lib/draft";
import type { Translate } from "@/lib/i18n";
import { CoverUnreadable, prepareCover } from "@/lib/coverImage";
import { Button, Field, inputClass, Notice } from "./ui";

type Props = { t: Translate; row: DraftRow; onChange: (update: Partial<DraftRow>) => void; onCover: (jpeg: Blob) => Promise<boolean> };

/** Prepare: the sermon's details, who can read it, and its cover. */
export function DetailsForm({ t, row, onChange, onCover }: Props) {
  const id = useId();
  const [coverState, setCoverState] = useState<"idle" | "working" | "failed" | "unreadable">("idle");
  const text = (key: "title" | "speaker" | "location", max: number) => ({
    id: `${id}-${key}`,
    className: inputClass,
    value: row[key],
    maxLength: max,
    onChange: (e: React.ChangeEvent<HTMLInputElement>) => onChange({ [key]: e.target.value }),
  });

  async function chooseCover(file: File) {
    setCoverState("working");
    try {
      const jpeg = await prepareCover(file);
      setCoverState((await onCover(jpeg)) ? "idle" : "failed");
    } catch (error) {
      setCoverState(error instanceof CoverUnreadable ? "unreadable" : "failed");
    }
  }

  return (
    <div>
      <Field id={`${id}-title`} label={t("Title")} hint={t("Needed to publish.")}>
        <input {...text("title", 200)} data-fix="title" aria-describedby={`${id}-title-hint`} required aria-required="true" aria-invalid={row.title.trim() === "" ? true : undefined} />
      </Field>
      <Field id={`${id}-speaker`} label={t("Speaker")}>
        <input {...text("speaker", 120)} autoComplete="name" />
      </Field>
      <div className="grid gap-x-4 sm:grid-cols-2">
        <Field id={`${id}-date`} label={t("Date")}>
          <input id={`${id}-date`} type="date" className={inputClass} value={row.preached_on ?? ""} onChange={(e) => onChange({ preached_on: e.target.value || null })} />
        </Field>
        <Field id={`${id}-series`} label={t("Series (optional)")} hint={t("Sermons in one series link to each other.")} hintBelow>
          <input id={`${id}-series`} aria-describedby={`${id}-series-hint`} className={inputClass} maxLength={120} value={row.series ?? ""} onChange={(e) => onChange({ series: e.target.value || null })} />
        </Field>
      </div>
      <Field id={`${id}-location`} label={t("Place (optional)")} hint={t("For example the campus or service. Shown to readers.")}>
        <input {...text("location", 200)} aria-describedby={`${id}-location-hint`} />
      </Field>
      <Field id={`${id}-language`} label={t("Language of the outline")} hint={t("Passages open in a free Bible in this language.")}>
        <select id={`${id}-language`} aria-describedby={`${id}-language-hint`} className={inputClass} value={row.language} onChange={(e) => onChange({ language: e.target.value as DraftRow["language"] })}>
          <option value="en">English</option>
          <option value="es">Español</option>
          <option value="pt">Português</option>
          <option value="other">{t("Another language")}</option>
        </select>
      </Field>

      <fieldset className="mt-6">
        <legend className="font-medium">{t("Who can read it")}</legend>
        <label className="mt-2 flex items-start gap-3 rounded-2xl border border-border p-3">
          <input type="radio" className="mt-1 size-5" name={`${id}-audience`} checked={row.audience === "link"} onChange={() => onChange({ audience: "link" })} />
          <span>
            <span className="block font-medium">{t("Anyone with the link")}</span>
            <span className="block text-sm text-muted">{t("Visitors can read it without an account.")}</span>
          </span>
        </label>
        <label className="mt-2 flex items-start gap-3 rounded-2xl border border-border p-3">
          <input type="radio" className="mt-1 size-5" name={`${id}-audience`} checked={row.audience === "members"} onChange={() => onChange({ audience: "members" })} />
          <span>
            <span className="block font-medium">{t("Church members only")}</span>
            <span className="block text-sm text-muted">{t("Members sign in to read it. Others see only that it's for members.")}</span>
          </span>
        </label>
        {row.status === "published" ? <p className="mt-2 text-sm text-muted">{t("A change here applies when you publish again. To close a published sermon to members at once, use Share.")}</p> : null}
      </fieldset>

      <section aria-labelledby={`${id}-cover`} className="mt-8 rounded-3xl border border-border bg-surface p-5">
        <h2 id={`${id}-cover`} className="text-lg font-semibold">
          {t("Cover picture (optional)")}
        </h2>
        {row.cover_id ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={`/studio/${row.id}/cover?id=${row.cover_id}`} alt={t("The current cover")} className="mt-4 aspect-[16/9] w-full rounded-2xl object-cover" />
        ) : null}
        <p className="mt-2 text-sm text-muted">{t("JPEG, PNG or HEIC. It's resized here, and its location and camera details are removed before upload.")}</p>
        <div className="mt-3 flex flex-wrap gap-2">
          <label className="inline-flex min-h-11 cursor-pointer items-center rounded-full border border-border px-5 font-medium hover:bg-surface-2 focus-within:outline focus-within:outline-3">
            {coverState === "working" ? t("Preparing…") : row.cover_id ? t("Replace the picture") : t("Choose a picture")}
            <input
              type="file"
              accept="image/*"
              className="sr-only"
              disabled={coverState === "working"}
              onChange={(e) => {
                const file = e.target.files?.[0];
                e.target.value = "";
                if (file) void chooseCover(file);
              }}
            />
          </label>
          {row.cover_id ? <Button onClick={() => onChange({ cover_id: null })}>{t("Remove the picture")}</Button> : null}
        </div>
        {coverState === "unreadable" ? <Notice>{t("That picture couldn't be read. Try a JPEG or PNG.")}</Notice> : null}
        {coverState === "failed" ? <Notice>{t("The picture couldn't be uploaded. Try again.")}</Notice> : null}
        {row.cover_id ? (
          <>
            <Field id={`${id}-alt`} label={t("Describe the picture")} hint={t("Read aloud to people who can't see it. For example: “Sunrise over a field of wheat.”")}>
              <textarea
                id={`${id}-alt`}
                data-fix="cover-alt"
                aria-describedby={`${id}-alt-hint`}
                className={inputClass}
                rows={2}
                maxLength={300}
                disabled={row.cover_decorative}
                value={row.cover_alt}
                onChange={(e) => onChange({ cover_alt: e.target.value })}
              />
            </Field>
            <label className="mt-3 flex items-center gap-2">
              <input type="checkbox" className="size-5" checked={row.cover_decorative} onChange={(e) => onChange({ cover_decorative: e.target.checked })} />
              {t("It's only decorative (nothing to describe)")}
            </label>
          </>
        ) : null}
      </section>
    </div>
  );
}
