import type { Metadata } from "next";
import { BrandBar } from "@/components/Brand";
import { HostBoard } from "@/components/launch/HostBoard";
import { SignInButtons, SignOutButton } from "@/components/SignIn";
import { config } from "@/config";
import { currentSession } from "@/lib/auth";
import { hostProblem, type Board } from "@/lib/giveaway";
import { translator } from "@/lib/i18n";
import { requestLang } from "@/lib/prefs.server";
import { RpcError, rpc } from "@/lib/supabase";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Giveaway host", robots: { index: false, follow: false } };

<<<<<<< HEAD
type Props = { searchParams: Promise<{ signin?: string; scene?: string }> };
const SCENES = ["volunteer", "raffle", "timer"] as const;

/**
 * The projector page: the live draw and the game timer. Only Versely's ops admins (the database checks).
 * ?scene=volunteer|raffle|timer shows one part only, without the controls, for a browser source in the
 * show's OBS scenes (the keys still work from OBS's Interact window; the timer's background is clear).
 */
export default async function LaunchHost({ searchParams }: Props) {
  const lang = await requestLang();
  const t = translator(lang);
  const { signin, scene } = await searchParams;
  const fixed = SCENES.find((value) => value === scene);
=======
type Props = { searchParams: Promise<{ signin?: string }> };

/** The projector page: the live draw and the game timer. Only Versely's ops admins (the database checks). */
export default async function LaunchHost({ searchParams }: Props) {
  const lang = await requestLang();
  const t = translator(lang);
  const { signin } = await searchParams;
>>>>>>> origin/claude/project-thread-sl5502
  const session = await currentSession();

  let board: Board | null = null;
  let problem: string | null = null;
  if (session) {
    try {
      board = await rpc<Board>("giveaway_board", { p_event: config.giveawayEvent }, session.accessToken);
    } catch (error) {
      problem = t(hostProblem(error instanceof RpcError ? (error.status === 401 ? "not_signed_in" : error.code) : "network"));
    }
  }

<<<<<<< HEAD
  if (board) return <HostBoard lang={lang} initial={board} entryLink={`${config.siteUrl}/launch`} scene={fixed} />;
=======
  if (board) return <HostBoard lang={lang} initial={board} entryLink={`${config.siteUrl}/launch`} />;
>>>>>>> origin/claude/project-thread-sl5502

  return (
    <div className="min-h-screen bg-gradient-to-b from-hero to-background">
      <BrandBar width="max-w-xl">{session ? <SignOutButton next="/launch/host" t={t} /> : null}</BrandBar>
      <main className="mx-auto max-w-xl px-4 pb-20 pt-10 sm:px-6">
        <p className="text-sm font-semibold uppercase tracking-wider text-accent">{t("Versely launch day")}</p>
        <h1 className="mt-2 text-3xl font-semibold tracking-tight">{t("Giveaway host")}</h1>
        {problem ? (
          <p role="alert" className="mt-6 rounded-2xl border border-border bg-surface-2 p-4">
            {problem}
          </p>
        ) : null}
        {session ? null : (
          <div className="mt-8 max-w-sm">
            <SignInButtons next="/launch/host" t={t} status={signin} />
          </div>
        )}
      </main>
    </div>
  );
}
