// A draft's cover for Studio (leaders only): the sermon-cover function asks
// sermon_cover_access with the leader's own session on every request. Never
// stored.
import { currentSession } from "@/lib/auth";
import { downloadCover } from "@/lib/supabase";
import { loadDraft, UUID } from "@/lib/studio.server";

const PRIVATE = { "Cache-Control": "private, no-store, max-age=0", "X-Content-Type-Options": "nosniff" };

export async function GET(request: Request, { params }: { params: Promise<{ sermon: string }> }) {
  const { sermon } = await params;
  const cover = new URL(request.url).searchParams.get("id") ?? "";
  const session = await currentSession();
  if (!session || !UUID.test(cover)) return new Response(null, { status: 404, headers: PRIVATE });
  const draft = await loadDraft(session, sermon).catch(() => null);
  if (!draft) return new Response(null, { status: 404, headers: PRIVATE });
  const file = await downloadCover(`${draft.group_id}/${draft.id}/${cover}.jpg`, session.accessToken).catch(() => null);
  if (!file?.ok || !file.body) return new Response(null, { status: 404, headers: PRIVATE });
  return new Response(file.body, { headers: { ...PRIVATE, "Content-Type": "image/jpeg" } });
}
