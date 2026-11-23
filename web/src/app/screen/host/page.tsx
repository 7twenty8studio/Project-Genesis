import type { Metadata } from "next";
import { BrandBar } from "@/components/Brand";
import { HostPanel } from "@/components/screenshare/HostPanel";
import { config } from "@/config";
import { translator } from "@/lib/i18n";
import { requestLang } from "@/lib/prefs.server";
import { cleanId } from "@/lib/screenshare/protocol";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Screenshare host", robots: { index: false, follow: false } };

type Props = { searchParams: Promise<{ room?: string }> };

/** For the person running OBS: the room's share link, every device in it, and each device's OBS link. */
export default async function ScreenHost({ searchParams }: Props) {
  const lang = await requestLang();
  const t = translator(lang);
  const { room } = await searchParams;
  return (
    <div className="min-h-screen bg-gradient-to-b from-hero to-background">
      <BrandBar wide />
      <main className="mx-auto max-w-3xl px-4 pb-20 pt-8 sm:px-6">
        <h1 className="text-3xl font-semibold tracking-tight">{t("Screenshare host")}</h1>
        <p className="mt-2 text-muted">{t("Each device that opens the share link gets its own ID and its own OBS link.")}</p>
        <div className="mt-6">
          <HostPanel lang={lang} site={config.siteUrl} initialRoom={cleanId(room)} />
        </div>
      </main>
    </div>
  );
}
