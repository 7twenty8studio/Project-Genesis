import { config } from "@/config";
import { formatDay, type Lang, type Translate } from "@/lib/i18n";
import { anchorFor, copyText, sections, type Block, type PublishedSermon, type SermonSummary } from "@/lib/outline";
import { describe } from "@/lib/shared/references";
import { CopyButton } from "./CopyButton";
import { ScriptureRef } from "./ScriptureRef";
import { OpenEvent } from "./SermonEvents";
import { SignOutButton } from "./SignIn";

const EVENTS = `${config.supabaseUrl}/functions/v1/sermon-events`;

/** A published sermon for reading: the outline first, every word as the church published it. */
export function SermonView({
  sermon,
  lang,
  t,
  signedIn,
  preview,
}: {
  sermon: PublishedSermon;
  lang: Lang;
  t: Translate;
  signedIn: boolean;
  /** Studio's preview of the draft: its own cover address, nothing counted, no links away. */
  preview?: { coverSrc: string | null };
}) {
  const events = preview ? "" : EVENTS;
  // Inside Studio the page already has its own main landmark.
  const Main = preview ? "div" : "main";
  const parts = sections(sermon.blocks);
  const headed = parts.filter((s) => s.title);
  const outlineLang = sermon.language === "other" ? undefined : sermon.language === "pt" ? "pt-BR" : sermon.language;
  return (
    <Main className="mx-auto max-w-2xl px-4 pb-24 pt-6 sm:px-6">
      {preview ? null : <OpenEvent endpoint={EVENTS} slug={sermon.slug} />}
      {sermon.cover && (!preview || preview.coverSrc) ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          src={preview?.coverSrc ?? `/s/${sermon.slug}/cover?v=${sermon.cover.id}`}
          alt={sermon.cover.decorative ? "" : sermon.cover.alt}
          className="mb-6 aspect-[16/9] w-full rounded-3xl object-cover"
          width={1600}
          height={900}
        />
      ) : null}
      <p className="text-sm font-medium uppercase tracking-wider text-accent">{sermon.church}</p>
      <h1 lang={outlineLang} className="mt-2 text-3xl font-semibold leading-tight tracking-tight sm:text-4xl">
        {sermon.title || (preview ? t("Untitled sermon") : "")}
      </h1>
      <dl className="mt-3 flex flex-wrap gap-x-4 gap-y-1 text-muted">
        {sermon.speaker ? (
          <div>
            <dt className="sr-only">{t("Speaker")}</dt>
            <dd lang={outlineLang}>{sermon.speaker}</dd>
          </div>
        ) : null}
        {sermon.preached_on ? (
          <div>
            <dt className="sr-only">{t("Date")}</dt>
            <dd>{formatDay(sermon.preached_on, lang)}</dd>
          </div>
        ) : null}
        {sermon.location ? (
          <div>
            <dt className="sr-only">{t("Place")}</dt>
            <dd lang={outlineLang}>{sermon.location}</dd>
          </div>
        ) : null}
        {sermon.series ? (
          <div>
            <dt className="sr-only">{t("Series")}</dt>
            <dd lang={outlineLang}>{t("Series: {name}", { name: sermon.series })}</dd>
          </div>
        ) : null}
      </dl>
      {sermon.audience === "members" ? (
        <div className="mt-3 flex items-center gap-3 text-sm text-muted">
          <span>{t("Shared with church members")}</span>
          {signedIn && !preview ? <SignOutButton next={`/s/${sermon.slug}`} t={t} /> : null}
        </div>
      ) : null}

      {headed.length >= 2 ? (
        <nav aria-label={t("Jump to a section")} className="mt-8 rounded-2xl bg-surface-2 p-4">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-muted">{t("Jump to")}</h2>
          <ol className="mt-2 space-y-1">
            {headed.map((s) => (
              <li key={s.id}>
                <a href={`#${anchorFor(s)}`} lang={outlineLang} className="inline-block py-1 font-medium text-accent-strong underline-offset-4 hover:underline">
                  {s.title}
                </a>
              </li>
            ))}
          </ol>
        </nav>
      ) : null}

      <article lang={outlineLang} className="mt-8">
        {parts.map((section) => (
          <section key={section.id} id={anchorFor(section)} aria-label={section.title ?? undefined} className="mt-8 first:mt-0">
            {section.blocks.map((block) => (
              <BlockView key={block.id} block={block} sermon={sermon} lang={lang} events={events} />
            ))}
            <div className="mt-3 flex justify-end">
              <CopyButton text={copyText(section.blocks)} label={t("Copy")} done={t("Copied")} sectionName={section.title ?? sermon.title} />
            </div>
          </section>
        ))}
      </article>

      {sermon.previous || sermon.next ? (
        <nav aria-label={t("More in this series")} className="mt-12 grid gap-3 sm:grid-cols-2">
          {sermon.previous ? <SeriesLink sermon={sermon.previous} label={t("Previous")} lang={lang} /> : <span />}
          {sermon.next ? <SeriesLink sermon={sermon.next} label={t("Next")} lang={lang} alignEnd /> : null}
        </nav>
      ) : null}

      <footer className="mt-16 rounded-2xl border border-border p-5 text-sm leading-relaxed text-muted">
        <p>{t("Passages open in free Bibles here. In the Versely app they open in your own Bible, and your notes stay private.")}</p>
        <a href={`versely://sermon/${sermon.slug}`} className="mt-2 inline-block font-medium text-accent underline-offset-4 hover:underline">
          {t("Open in Versely")}
        </a>
      </footer>
    </Main>
  );
}

function BlockView({ block, sermon, lang, events }: { block: Block; sermon: PublishedSermon; lang: Lang; events: string }) {
  switch (block.kind) {
    case "heading": {
      const Tag = block.level === 1 ? "h2" : block.level === 2 ? "h2" : "h3";
      return <Tag className={`mt-2 font-semibold tracking-tight ${block.level === 3 ? "text-xl" : "text-2xl"}`}>{block.text}</Tag>;
    }
    case "paragraph":
      return <p className="my-4 whitespace-pre-line text-[1.0625rem] leading-relaxed">{block.text}</p>;
    case "quote":
      return <blockquote className="my-4 whitespace-pre-line border-l-4 border-accent pl-4 text-[1.0625rem] italic leading-relaxed">{block.text}</blockquote>;
    case "list": {
      const List = block.ordered ? "ol" : "ul";
      return (
        <List className={`my-4 space-y-2 pl-6 text-[1.0625rem] leading-relaxed ${block.ordered ? "list-decimal" : "list-disc"}`}>
          {block.items.map((item, i) => (
            <li key={i}>{item}</li>
          ))}
        </List>
      );
    }
    case "scripture": {
      const ref = block.ref;
      const named = ref.status === "verified" && ref.start ? describe(ref.start, ref.end ?? ref.start, sermon.language) : null;
      return (
        <ScriptureRef
          reference={ref}
          named={named}
          outlineLanguage={sermon.language}
          lang={lang}
          supabaseUrl={config.supabaseUrl}
          eventEndpoint={events}
          slug={sermon.slug}
        />
      );
    }
  }
}

function SeriesLink({ sermon, label, lang, alignEnd }: { sermon: SermonSummary; label: string; lang: Lang; alignEnd?: boolean }) {
  return (
    <a href={`/s/${sermon.slug}`} className={`block rounded-2xl border border-border bg-surface p-4 hover:bg-surface-2 ${alignEnd ? "sm:text-right" : ""}`}>
      <span className="text-sm text-muted">{label}</span>
      <span className="mt-1 block font-semibold">{sermon.title}</span>
      {sermon.preached_on ? <span className="block text-sm text-muted">{formatDay(sermon.preached_on, lang)}</span> : null}
    </a>
  );
}
