import type { Metadata } from "next";
import { headers } from "next/headers";
import { BrandBar } from "@/components/Brand";
import { SignInButtons, SignOutButton } from "@/components/SignIn";
import { ChurchHome } from "@/components/studio/ChurchHome";
import { currentSession } from "@/lib/auth";
import { formatDay, langFromHeader, translator } from "@/lib/i18n";
import { RpcError } from "@/lib/supabase";
import { churchReports, churchSermons, myChurches, type StudioChurch } from "@/lib/studio.server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Church Studio · Versely", robots: { index: false, follow: false } };

type Props = { searchParams: Promise<{ church?: string; signin?: string }> };

export default async function StudioHome({ searchParams }: Props) {
  const lang = langFromHeader((await headers()).get("accept-language"));
  const t = translator(lang);
  const { church: wanted, signin } = await searchParams;
  const session = await currentSession();

  if (!session) {
    return (
      <>
        <BrandBar />
        <main className="mx-auto max-w-2xl px-4 py-12 sm:px-6">
          <h1 className="text-3xl font-semibold tracking-tight">{t("Church Studio")}</h1>
          <p className="mt-3 text-lg leading-relaxed text-muted">
            {t("Prepare your sermon outline, then share it with one link and a QR code. Sign in with the account you use in Versely.")}
          </p>
          {signin === "failed" ? (
            <p role="alert" className="mt-6 rounded-2xl border border-border bg-surface-2 p-4">
              {t("Sign-in didn't finish. Try again.")}
            </p>
          ) : null}
          <div className="mt-8">
            <SignInButtons next="/studio" t={t} />
          </div>
        </main>
      </>
    );
  }

  let churches: StudioChurch[] = [];
  try {
    churches = await myChurches(session);
  } catch (error) {
    if (!(error instanceof RpcError)) throw error;
  }
  const church = churches.find((c) => c.id === wanted) ?? churches[0];
  const header = (
    <BrandBar wide>
      <div className="flex items-center gap-3 text-sm">
        {session.name ? <span className="text-muted">{session.name}</span> : null}
        <SignOutButton next="/studio" t={t} />
      </div>
    </BrandBar>
  );

  if (!church) {
    return (
      <>
        {header}
        <main className="mx-auto max-w-2xl px-4 py-12 sm:px-6">
          <h1 className="text-3xl font-semibold tracking-tight">{t("Church Studio")}</h1>
          <p className="mt-4 text-lg leading-relaxed text-muted">
            {t("You don't lead a church that shares sermons yet. In Versely, the owner of a church group turns on sermons in the group's settings; its owner and moderators can then publish here.")}
          </p>
        </main>
      </>
    );
  }

  const [sermons, reports] = await Promise.all([churchSermons(session, church.id), churchReports(session, church.id).catch(() => [])]);
  return (
    <>
      {header}
      <ChurchHome
        lang={lang}
        churches={churches}
        church={church}
        sermons={sermons.map((s) => ({ ...s, day: s.preached_on ? formatDay(s.preached_on, lang) : null }))}
        reports={reports}
      />
    </>
  );
}
