import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import { config } from "@/config";
import { BrandBar } from "@/components/Brand";
import { MembersOnly } from "@/components/MembersOnly";
import { SermonView } from "@/components/SermonView";
import { currentSession } from "@/lib/auth";
import { isLang, langFromHeader, translator } from "@/lib/i18n";
import { lookUpSermon } from "@/lib/sermons.server";

// Rendered for each request, never stored: what a visitor may read can change at any moment.
export const dynamic = "force-dynamic";

type Params = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { slug } = await params;
  const sermon = await lookUpSermon(slug);
  const other: Record<string, string> = {};
  if (config.appStoreId) other["apple-itunes-app"] = `app-id=${config.appStoreId}, app-argument=${config.siteUrl}/s/${slug}`;
  // Shared by link, never listed by search engines; a members-only sermon names nothing.
  const robots = { index: false, follow: false };
  if (sermon.status !== "ok") return { title: "Versely", robots, other };
  const title = sermon.title || "Sermon";
  return {
    title,
    robots,
    other,
    openGraph: sermon.audience === "link" ? { title, description: sermon.church, siteName: "Versely" } : undefined,
  };
}

export default async function SermonPage({ params }: Params) {
  const { slug } = await params;
  const sermon = await lookUpSermon(slug);
  const visitor = langFromHeader((await headers()).get("accept-language"));
  if (sermon.status === "not_found") notFound();
  if (sermon.status === "members_only") {
    const session = await currentSession();
    return <MembersOnly slug={slug} lang={visitor} signedIn={session !== null} />;
  }
  // The page's own words follow the sermon's language when it's one of ours.
  const lang = isLang(sermon.language) ? sermon.language : visitor;
  const session = sermon.audience === "members" ? await currentSession() : null;
  return (
    <>
      <BrandBar />
      <SermonView sermon={sermon} lang={lang} t={translator(lang)} signedIn={session !== null} />
    </>
  );
}
