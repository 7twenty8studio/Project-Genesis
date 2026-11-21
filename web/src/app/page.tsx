import Link from "next/link";
import { config } from "@/config";
import { BrandBar, SiteFooter } from "@/components/Brand";
import { requestLang } from "@/lib/prefs.server";
import { translator } from "@/lib/i18n";

const primary =
  "inline-flex min-h-12 items-center justify-center rounded-full bg-accent-strong px-7 text-base font-semibold text-on-accent shadow-sm transition-[opacity,transform] duration-150 ease-out hover:opacity-90 active:scale-[0.98]";
const secondary =
  "inline-flex min-h-12 items-center justify-center rounded-full border border-border bg-surface/70 px-7 text-base font-medium text-foreground backdrop-blur transition-colors hover:bg-surface";

export default async function Home() {
  const t = translator(await requestLang());
  const steps = [
    { title: t("Bring the outline you already have"), body: t("Paste it, or import a Word file or PDF. Every word is kept, and every Bible reference is found for you.") },
    { title: t("Check it in a minute"), body: t("Studio shows anything it wasn't sure about. Nothing is published until you say so.") },
    { title: t("Share one link"), body: t("Put the QR code on the screen or in the bulletin. Anyone can open it, no app or account needed.") },
  ];
  return (
    <>
      <div className="bg-hero">
        <BrandBar width="max-w-5xl">
          <Link href="/studio" className="text-sm font-medium text-accent underline-offset-4 hover:underline">
            {t("Sign in")}
          </Link>
        </BrandBar>
      </div>
      <main>
      <div className="relative overflow-hidden bg-gradient-to-b from-hero to-background">
        <section aria-labelledby="hero-title" className="relative z-10 mx-auto grid max-w-5xl grid-cols-1 items-center gap-10 px-4 pb-40 pt-12 sm:px-6 md:grid-cols-[1.15fr_1fr] md:pb-48 md:pt-20">
          <div>
            <p className="inline-flex items-center gap-2 rounded-full border border-border bg-surface/70 px-3 py-1 text-sm font-medium text-accent">
              {t("Free for churches")}
            </p>
            <h1 id="hero-title" className="mt-5 text-4xl font-semibold leading-[1.1] tracking-tight sm:text-5xl">{t("Share your Sunday message")}</h1>
            <p className="mt-5 max-w-xl text-lg leading-relaxed text-muted">
              {t("Prepare your sermon outline, share a link or QR code, and help your church follow along in their own Bible.")}
            </p>
            <div className="mt-8 flex flex-col gap-3 sm:flex-row">
              <Link href="/studio" className={primary}>
                {t("Open Church Studio")}
              </Link>
              {config.sampleSermon ? (
                <Link href={`/s/${config.sampleSermon}`} className={secondary}>
                  {t("View a sample sermon")}
                </Link>
              ) : (
                <a href="#how" className={secondary}>
                  {t("See how it works")}
                </a>
              )}
            </div>
          </div>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/art/read.webp" alt="" width={716} height={720} className="mx-auto w-full max-w-sm drop-shadow-xl md:max-w-md" />
        </section>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/art/hills.webp" alt="" width={1600} height={851} className="pointer-events-none absolute inset-x-0 bottom-0 h-56 w-full object-cover object-top opacity-90 [mask-image:linear-gradient(to_bottom,transparent,black_45%)] dark:opacity-40 md:h-72" />
      </div>

        <section id="how" aria-labelledby="how-title" className="mx-auto max-w-5xl px-4 py-20 sm:px-6">
          <h2 id="how-title" className="text-3xl font-semibold tracking-tight">{t("Ready before the service starts")}</h2>
          <ol className="mt-10 grid gap-5 md:grid-cols-3">
            {steps.map((step, i) => (
              <li key={i} className="rounded-3xl border border-border bg-surface p-6 shadow-sm">
                <span aria-hidden="true" className="inline-flex h-10 w-10 items-center justify-center rounded-full bg-surface-2 text-lg font-semibold text-accent">
                  {i + 1}
                </span>
                <h3 className="mt-4 text-lg font-semibold">{step.title}</h3>
                <p className="mt-2 leading-relaxed text-muted">{step.body}</p>
              </li>
            ))}
          </ol>
        </section>

        <section aria-labelledby="together-title" className="bg-surface-2/60">
          <div className="mx-auto grid max-w-5xl grid-cols-1 items-center gap-10 px-4 py-20 sm:px-6 md:grid-cols-2">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/art/together.webp" alt="" width={720} height={558} className="mx-auto w-full max-w-md" />
            <div>
              <h2 id="together-title" className="text-3xl font-semibold tracking-tight">{t("Everyone on the same page")}</h2>
              <ul className="mt-6 space-y-4 text-lg leading-relaxed">
                <li className="flex gap-3">
                  <Check />
                  {t("Passages open in the reader's own Bible, in English, Spanish or Portuguese.")}
                </li>
                <li className="flex gap-3">
                  <Check />
                  {t("Members can take private notes on the sermon in the Versely app.")}
                </li>
                <li className="flex gap-3">
                  <Check />
                  {t("Keep a sermon for members only, or share it with anyone.")}
                </li>
              </ul>
            </div>
          </div>
        </section>

        <section className="mx-auto max-w-5xl px-4 py-20 sm:px-6">
          <div className="rounded-[2rem] bg-accent-strong px-6 py-12 text-center text-on-accent sm:px-12">
            <h2 className="text-3xl font-semibold tracking-tight">{t("Start your church in a minute")}</h2>
            <p className="mx-auto mt-3 max-w-xl text-lg leading-relaxed opacity-90">{t("Sign in, name your church and write your first outline. It's free.")}</p>
            <Link
              href="/studio"
              className="mt-8 inline-flex min-h-12 items-center justify-center rounded-full bg-on-accent px-7 text-base font-semibold text-accent-strong transition-opacity hover:opacity-90"
            >
              {t("Open Church Studio")}
            </Link>
          </div>
        </section>
      </main>
      <SiteFooter t={t} />
    </>
  );
}

function Check() {
  return (
    <svg aria-hidden="true" viewBox="0 0 20 20" className="mt-1 h-5 w-5 flex-none text-accent" fill="currentColor">
      <path d="M10 0a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm4.7 7.7-5.4 5.4a1 1 0 0 1-1.4 0L5.3 10.5a1 1 0 1 1 1.4-1.4l1.9 1.9 4.7-4.7a1 1 0 1 1 1.4 1.4Z" />
    </svg>
  );
}
