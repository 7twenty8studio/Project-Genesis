// GET /s/<slug>/cover: the sermon's published cover, for this visitor only.
// Access is checked twice on every request and nothing is stored: the
// sermon must be readable now (published_sermon, as the visitor), and the
// sermon-cover function asks sermon_cover_access as the visitor before it
// reads the file. Nobody can read the bucket directly or sign a link, so an
// unpublished, restricted, hidden or switched-off sermon's cover stops on
// the next request.
import { currentSession } from "@/lib/auth";
import { lookUpSermon } from "@/lib/sermons.server";
import { downloadCover } from "@/lib/supabase";

export const dynamic = "force-dynamic";

const PRIVATE = { "Cache-Control": "private, no-store, max-age=0", "X-Content-Type-Options": "nosniff" };

export async function GET(_request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const sermon = await lookUpSermon(slug);
  if (sermon.status !== "ok" || !sermon.cover) return new Response(null, { status: 404, headers: PRIVATE });
  const session = await currentSession();
  const file = await downloadCover(sermon.cover.path, session?.accessToken);
  if (!file.ok || !file.body) return new Response(null, { status: 404, headers: PRIVATE });
  return new Response(file.body, { status: 200, headers: { ...PRIVATE, "Content-Type": "image/jpeg" } });
}
