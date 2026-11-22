import type { Metadata } from "next";
import { BrandBar } from "@/components/Brand";
import { EntryForm } from "@/components/launch/EntryForm";
import { config } from "@/config";
import { translator } from "@/lib/i18n";
import { requestLang } from "@/lib/prefs.server";
import { rpc } from "@/lib/supabase";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Launch day giveaway", robots: { index: false, follow: false } };

type Props = { searchParams: Promise<{ kiosk?: string }> };

/** Launch day: enter the giveaway from a phone (QR) or the lobby iPad (?kiosk=1). */
export default async function LaunchEntry({ searchParams }: Props) {
  const lang = await requestLang();
  const t = translator(lang);
  const { kiosk } = await searchParams;
  const status = await rpc<{ name: string; open: boolean } | null>("giveaway_status", { p_event: config.giveawayEvent }).catch(() => null);
  const open = status?.open ?? false;

  return (
    <div className="min-h-screen bg-gradient-to-b from-hero to-background">
      <BrandBar width="max-w-xl" />
      <main className="mx-auto max-w-xl px-4 pb-20 pt-8 sm:px-6">
        <p className="text-sm font-semibold uppercase tracking-wider text-accent">{t("Versely launch day")}</p>
        <h1 className={`mt-2 font-semibold leading-tight tracking-tight ${kiosk ? "text-5xl" : "text-4xl"}`}>{t("Win a free year of Versely Premium")}</h1>
        <p className="mt-4 text-lg leading-relaxed text-muted">
          {t("Enter for the final golden ticket, drawn live at the end. Your number may also be called to play a game on stage.")}
        </p>
        <div className="mt-8">
          {status === null ? (
            <p role="alert" className="rounded-2xl border border-border bg-surface-2 p-4">
              {t("That didn't go through. Check your connection and try again.")}
            </p>
          ) : open ? (
            <EntryForm lang={lang} kiosk={kiosk === "1"} />
          ) : (
            <p role="status" className="rounded-2xl border border-border bg-surface-2 p-4 text-lg">
              {t("Entries are closed.")}
            </p>
          )}
        </div>
        <p className="mt-10 text-sm leading-relaxed text-muted">
          {t("Free to enter, one entry per person. No purchase or download needed. You must be in the room when your number is drawn.")}
        </p>
      </main>
    </div>
  );
}
