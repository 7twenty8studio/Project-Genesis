import type { Metadata } from "next";
import { BrandBar } from "@/components/Brand";
import { SharePanel } from "@/components/screenshare/SharePanel";
import { config } from "@/config";
import { translator } from "@/lib/i18n";
import { requestLang } from "@/lib/prefs.server";
import { cleanId } from "@/lib/screenshare/protocol";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Share to the big screen", robots: { index: false, follow: false } };

type Props = { searchParams: Promise<{ room?: string; device?: string }> };

/** A device opens this (from the host's link or QR) to put its screen or camera on the show's screen through OBS. */
export default async function ScreenShare({ searchParams }: Props) {
  const lang = await requestLang();
  const t = translator(lang);
  const params = await searchParams;
  const room = cleanId(params.room);

  return (
    <div className="min-h-screen bg-gradient-to-b from-hero to-background">
      <BrandBar width="max-w-xl" />
      <main className="mx-auto max-w-xl px-4 pb-20 pt-8 sm:px-6">
        <h1 className="text-3xl font-semibold tracking-tight">{t("Share to the big screen")}</h1>
        <div className="mt-6">
          {room ? (
            <SharePanel lang={lang} room={room} presetDevice={cleanId(params.device)} site={config.siteUrl} />
          ) : (
            <p role="alert" className="rounded-2xl border border-border bg-surface-2 p-4">
              {t("Open the share link from the host to join the room.")}
            </p>
          )}
        </div>
      </main>
    </div>
  );
}
