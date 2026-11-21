import type { Metadata } from "next";
import { headers } from "next/headers";
import { BrandBar, SiteFooter } from "@/components/Brand";
import { SignInButtons, SignOutButton } from "@/components/SignIn";
import { ChurchHome } from "@/components/studio/ChurchHome";
import { StartChurch } from "@/components/studio/StartChurch";
import { currentSession } from "@/lib/auth";
import { formatDay, langFromHeader, translator } from "@/lib/i18n";
import { RpcError } from "@/lib/supabase";
import { churchReports, churchSermons, myChurches, myDisplayName, myGroupsForSermons, type StudioChurch } from "@/lib/studio.server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Church Studio · Versely", robots: { index: false, follow: false } };

type Props = { searchParams: Promise<{ church?: string; signin?: string; new?: string }> };

export default async function StudioHome({ searchParams }: Props) {
  const lang = langFromHeader((await headers()).get("accept-language"));
  const t = translator(lang);
  const { church: wanted, signin, new: startNew } = await searchParams;
  const session = await currentSession();

  if (!session) {
    return (
      <div className="min-h-screen bg-gradient-to-b from-[#fdf7ee] to-background dark:from-[#241a12] dark:to-background">
        <BrandBar width="max-w-5xl" />
        <main className="mx-auto grid max-w-5xl grid-cols-1 items-center gap-10 px-4 py-12 sm:px-6 md:grid-cols-2 md:py-20">
          <div>
            <p className="text-sm font-semibold uppercase tracking-wider text-accent">{t("Church Studio")}</p>
            <h1 className="mt-2 text-4xl font-semibold leading-tight tracking-tight">{t("Share Sunday's outline with your church.")}</h1>
            <p className="mt-4 text-lg leading-relaxed text-muted">
              {t("Sign in to start your church, or to keep working on your sermons. It's free, and it's the same account you use in the Versely app.")}
            </p>
            {signin === "failed" ? (
              <p role="alert" className="mt-6 rounded-2xl border border-border bg-surface-2 p-4">
                {t("Sign-in didn't finish. Try again.")}
              </p>
            ) : null}
            <div className="mt-8 max-w-sm">
              <SignInButtons next="/studio" t={t} />
              <p className="mt-4 text-sm text-muted">{t("New to Versely? Signing in creates your account.")}</p>
            </div>
          </div>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/art/together.webp" alt="" width={720} height={558} className="mx-auto hidden w-full max-w-md md:block" />
        </main>
      </div>
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

  if (!church || startNew === "1") {
    const [yourName, groups] = await Promise.all([myDisplayName(session), myGroupsForSermons(session).catch(() => [])]);
    const first = !church;
    return (
      <>
        {header}
        <main className="mx-auto max-w-2xl px-4 pb-24 pt-10 sm:px-6">
          <p className="text-sm font-semibold uppercase tracking-wider text-accent">{t("Church Studio")}</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight">
            {first ? (session.name ? t("Welcome, {name}", { name: session.name.split(" ")[0] }) : t("Welcome")) : t("Start another church")}
          </h1>
          {first ? <p className="mt-3 text-lg leading-relaxed text-muted">{t("Name your church to get started. You can write your first sermon outline right after.")}</p> : null}
          <div className="mt-8">
            <StartChurch lang={lang} yourName={yourName} suggestedName={session.name ?? ""} groups={groups} first={first} />
          </div>
        </main>
        <SiteFooter t={t} />
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
