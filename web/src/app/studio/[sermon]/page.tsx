import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound, redirect } from "next/navigation";
import { BrandBar } from "@/components/Brand";
import { SignOutButton } from "@/components/SignIn";
import { Editor } from "@/components/studio/Editor";
import { currentSession } from "@/lib/auth";
import { langFromHeader, translator } from "@/lib/i18n";
import { loadDraft, myChurches } from "@/lib/studio.server";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Church Studio · Versely", robots: { index: false, follow: false } };

export default async function EditSermon({ params }: { params: Promise<{ sermon: string }> }) {
  const { sermon: id } = await params;
  const lang = langFromHeader((await headers()).get("accept-language"));
  const t = translator(lang);
  const session = await currentSession();
  if (!session) redirect(`/studio`);
  const [draft, churches] = await Promise.all([loadDraft(session, id), myChurches(session).catch(() => [])]);
  const church = draft ? churches.find((c) => c.id === draft.group_id) : undefined;
  if (!draft || !church) notFound();
  return (
    <>
      <BrandBar wide>
        <div className="flex items-center gap-4 text-sm">
          <a href={`/studio?church=${church.id}`} className="font-medium text-accent underline-offset-4 hover:underline">
            {t("All sermons")}
          </a>
          <SignOutButton next="/studio" t={t} />
        </div>
      </BrandBar>
      <Editor lang={lang} initial={draft} church={church.name} />
    </>
  );
}
