import Link from "next/link";
import { headers } from "next/headers";
import { BrandBar } from "@/components/Brand";
import { langFromHeader, translator } from "@/lib/i18n";

export default async function Home() {
  const t = translator(langFromHeader((await headers()).get("accept-language")));
  return (
    <>
      <BrandBar />
      <main className="mx-auto max-w-2xl px-4 py-16 sm:px-6">
        <h1 className="text-4xl font-semibold tracking-tight">{t("Go beyond the verse.")}</h1>
        <p className="mt-4 text-lg leading-relaxed text-muted">
          {t("Versely is a Bible study app for iPhone and iPad. Churches use it to share their sermon outlines, so everyone can follow along and read each passage in their own Bible.")}
        </p>
        <div className="mt-10 rounded-3xl border border-border bg-surface p-6">
          <h2 className="text-xl font-semibold">{t("Church Studio")}</h2>
          <p className="mt-2 leading-relaxed text-muted">{t("For church owners and moderators: prepare a sermon outline and share it with one link and a QR code.")}</p>
          <Link href="/studio" className="mt-5 inline-flex min-h-12 items-center rounded-full bg-accent-strong px-6 font-medium text-on-accent hover:opacity-90">
            {t("Open Church Studio")}
          </Link>
        </div>
      </main>
    </>
  );
}
