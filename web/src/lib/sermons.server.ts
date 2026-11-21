// The sermon behind a link, asked as the visitor (their session, or a guest).
// Never cached: published_sermon rechecks both switches, the audience,
// membership and bans on every request, so an unpublish, a ban or a
// restriction to members applies to the very next one.
import { cache } from "react";
import { currentSession } from "./auth.ts";
import type { SermonLookup } from "./outline.ts";
import type { YouVersionBible } from "./scripture.ts";
import { rpc } from "./supabase.ts";

export const SLUG = /^[a-z0-9]{10}$/;

/** Once per request (the page and its metadata share the answer), never across requests. */
export const lookUpSermon = cache(async (slug: string): Promise<SermonLookup> => {
  if (!SLUG.test(slug)) return { status: "not_found" };
  const session = await currentSession();
  return rpc<SermonLookup>("published_sermon", { p_slug: slug }, session?.accessToken);
});

/** The YouVersion Bibles a sermon page may offer (none while the switch is off, or if the list can't be read). */
export async function youVersionWebBibles(): Promise<YouVersionBible[]> {
  try {
    const list = await rpc<YouVersionBible[]>("youversion_web_bibles", {});
    return Array.isArray(list) ? list : [];
  } catch {
    return [];
  }
}
