import { config } from "@/config";
import { formatDay, type Lang, type Translate } from "@/lib/i18n";
import { addressLines, dayNames, localToday, mapsLink, scheduleLines, type ChurchLocation } from "@/lib/locations";
import { anchorFor, copyText, sections, type Block, type PublishedSermon, type SermonSummary } from "@/lib/outline";
import type { YouVersionBible } from "@/lib/scripture";
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
  youversion = [],
}: {
  sermon: PublishedSermon;
  lang: Lang;
  t: Translate;
  signedIn: boolean;
  /** Studio's preview of the draft: its own cover address, nothing counted, no links away. */
  preview?: { coverSrc: string | null };
  /** YouVersion Bibles passages may open in (youversion_web_bibles). */
  youversion?: YouVersionBible[];
}) {
  const events = preview ? "" : EVENTS;
  // Inside Studio the page already has its own main landmark.
  const Main = preview ? "div" : "main";
  const parts = sections(sermon.blocks);
  const headed = parts.filter((s) => s.title);
  const outlineLang = sermon.language === "other" ? undefined : sermon.language === "pt" ? "pt-BR" : sermon.language;
  const locations = sermon.locations ?? [];
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
      {locations.length ? (
        <a
          href="#locations"
          className="mt-4 inline-flex min-h-10 items-center gap-2 rounded-full border border-border bg-surface px-4 text-sm font-semibold text-accent-strong hover:bg-surface-2"
        >
          <PinIcon />
          {t("Locations and Times")}
        </a>
      ) : null}
      {sermon.audience === "members" ? (
        <div className="mt-3 flex items-center gap-3 text-sm text-muted">
          <span>{t("Shared with church members")}</span>
          {signedIn && !preview ? <SignOutButton next={`/s/${sermon.slug}`} t={t} /> : null}
        </div>
      ) : null}

      {headed.length >= 2 ? (
        <nav aria-label={t("Jump to a section")} className="mt-8 rounded-2xl bg-surface-2 p-4">
          <h2 className="text-xs font-medium uppercase tracking-[0.14em] text-muted">{t("Jump to")}</h2>
          <ol className="mt-2 space-y-1">
            {headed.map((s) => (
              <li key={s.id}>
                <a href={`#${anchorFor(s)}`} lang={outlineLang} className="group inline-flex items-baseline gap-2 py-1 font-semibold text-accent-strong">
                  <span aria-hidden="true" className="text-copper">↓</span>
                  <span className="underline decoration-copper decoration-2 underline-offset-[5px] group-hover:decoration-accent-strong">{s.title}</span>
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
              <BlockView key={block.id} block={block} sermon={sermon} lang={lang} events={events} youversion={youversion} />
            ))}
            <div className="mt-3 flex justify-end">
              <CopyButton text={copyText(section.blocks)} label={t("Copy")} done={t("Copied")} sectionName={section.title ?? sermon.title} />
            </div>
          </section>
        ))}
      </article>

      {sermon.next ? (
        <a
          href={preview ? undefined : `/s/${sermon.next.slug}`}
          className="mt-12 flex items-center justify-between gap-4 rounded-2xl bg-accent-strong p-5 text-on-accent hover:opacity-95"
        >
          <span>
            <span lang={outlineLang} className="block text-lg font-semibold">
              {t("Join us for {title}", { title: sermon.next.title })}
            </span>
            {sermon.next.preached_on ? <span className="mt-0.5 block text-sm opacity-90">{formatDay(sermon.next.preached_on, lang)}</span> : null}
          </span>
          <span aria-hidden="true" className="text-2xl">
            →
          </span>
        </a>
      ) : null}

      {locations.length ? <Locations locations={locations} invite={!sermon.next} lang={lang} outlineLang={outlineLang} t={t} /> : null}

      {sermon.previous ? (
        <nav aria-label={t("More in this series")} className="mt-8">
          <SeriesLink sermon={sermon.previous} label={t("Previous")} lang={lang} />
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

function BlockView({ block, sermon, lang, events, youversion }: { block: Block; sermon: PublishedSermon; lang: Lang; events: string; youversion: YouVersionBible[] }) {
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
          youversion={youversion}
        />
      );
    }
  }
}

/** Where and when the church meets, with directions; `invite` heads it "Join us" when no next sermon does. */
function Locations({ locations, invite, lang, outlineLang, t }: { locations: ChurchLocation[]; invite: boolean; lang: Lang; outlineLang?: string; t: Translate }) {
  const names = dayNames(t);
  const today = localToday();
  return (
    <section id="locations" aria-labelledby="locations-title" className="mt-12 scroll-mt-6 rounded-2xl border border-border bg-surface p-5">
      {invite ? <p className="text-lg font-semibold">{t("Join us")}</p> : null}
      <h2 id="locations-title" className={invite ? "mt-1 text-sm font-medium uppercase tracking-[0.14em] text-muted" : "text-lg font-semibold"}>
        {t("Locations and Times")}
      </h2>
      <ul className="mt-3 divide-y divide-border">
        {locations.map((place, i) => {
          const schedule = scheduleLines(place, lang, names, today);
          const address = addressLines(place);
          const directions = mapsLink(place);
          return (
            <li key={i} className="py-4 first:pt-0 last:pb-0">
              <p lang={outlineLang} className="font-semibold">
                {place.name}
              </p>
              {schedule.length ? (
                <ul className="mt-1 space-y-0.5 leading-relaxed">
                  {schedule.map((line, k) => (
                    <li key={k}>{line}</li>
                  ))}
                </ul>
              ) : null}
              {directions ? (
                <a
                  href={directions}
                  target="_blank"
                  rel="noopener noreferrer"
                  lang={outlineLang}
                  className="mt-2 inline-flex items-start gap-1.5 text-muted hover:text-foreground"
                >
                  <PinIcon />
                  <span className="underline decoration-copper underline-offset-4">
                    {address.map((line, k) => (
                      <span key={k} className="block">
                        {line}
                      </span>
                    ))}
                    <span className="sr-only"> ({t("directions, opens in a new tab")})</span>
                  </span>
                </a>
              ) : null}
            </li>
          );
        })}
      </ul>
    </section>
  );
}

function PinIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" className="mt-0.5 h-4 w-4 flex-none" fill="currentColor">
      <path d="M10 1.5a6 6 0 0 0-6 6c0 4.2 5.2 10.2 5.4 10.5a.8.8 0 0 0 1.2 0c.2-.3 5.4-6.3 5.4-10.5a6 6 0 0 0-6-6Zm0 8.3a2.3 2.3 0 1 1 0-4.6 2.3 2.3 0 0 1 0 4.6Z" />
    </svg>
  );
}

function SeriesLink({ sermon, label, lang }: { sermon: SermonSummary; label: string; lang: Lang }) {
  return (
    <a href={`/s/${sermon.slug}`} className="block rounded-2xl border border-border bg-surface p-4 hover:bg-surface-2">
      <span className="text-sm text-muted">{label}</span>
      <span className="mt-1 block font-semibold">{sermon.title}</span>
      {sermon.preached_on ? <span className="block text-sm text-muted">{formatDay(sermon.preached_on, lang)}</span> : null}
    </a>
  );
}
