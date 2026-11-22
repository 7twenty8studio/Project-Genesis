"use server";
// Church Studio's writes (VRS-18). Each one reads the person's own session
// and calls the database as them; the database checks they lead the church,
// that both switches are on and that the draft is the version they loaded.
// Nothing here trusts the browser.
import { redirect } from "next/navigation";
import { currentSession } from "@/lib/auth";
import type { DraftBlock, DraftDetails } from "@/lib/draft";
import type { DraftReview } from "@/lib/import/review";
import type { ChurchLocation } from "@/lib/locations";
import { RpcError, rpc, uploadCover } from "@/lib/supabase";
import { UUID } from "@/lib/studio.server";

export type ActionResult<T = object> = ({ ok: true } & T) | { ok: false; code: string; detail?: string };

async function call<T>(fn: string, args: Record<string, unknown>): Promise<ActionResult<{ value: T }>> {
  const session = await currentSession();
  if (!session) return { ok: false, code: "not_signed_in" };
  try {
    return { ok: true, value: await rpc<T>(fn, args, session.accessToken) };
  } catch (error) {
    if (error instanceof RpcError) {
      if (error.status === 401) return { ok: false, code: "not_signed_in" };
      return { ok: false, code: error.code, detail: error.detail };
    }
    return { ok: false, code: "network" };
  }
}

const isID = (id: unknown): id is string => typeof id === "string" && UUID.test(id);

export async function createSermon(church: string): Promise<ActionResult> {
  if (!isID(church)) return { ok: false, code: "not_found" };
  const result = await call<{ id: string }>("create_church_sermon", { p_group: church, p_title: "" });
  if (!result.ok) return result;
  redirect(`/studio/${result.value.id}`);
}

/** Starts a church owned by the person, with sermons on, and opens its first draft. */
export async function startChurch(name: string, yourName: string | null): Promise<ActionResult> {
  if (typeof name !== "string" || name.trim().length === 0 || name.length > 60) return { ok: false, code: "invalid_group" };
  const you = typeof yourName === "string" && yourName.trim() ? yourName.trim().slice(0, 40) : null;
  const result = await call<{ id: string }>("create_sermon_church", { p_name: name.trim(), p_your_name: you });
  if (!result.ok) return result;
  const draft = await call<{ id: string }>("create_church_sermon", { p_group: result.value.id, p_title: "" });
  redirect(draft.ok ? `/studio/${draft.value.id}` : `/studio?church=${result.value.id}`);
}

/** Turns sermons on for a group the person owns, and opens it. */
export async function turnOnSermons(group: string): Promise<ActionResult> {
  if (!isID(group)) return { ok: false, code: "not_found" };
  const result = await call<null>("set_church_sermons", { p_group: group, p_on: true });
  if (!result.ok) return result;
  redirect(`/studio?church=${group}`);
}

export async function duplicateSermon(sermon: string): Promise<ActionResult> {
  if (!isID(sermon)) return { ok: false, code: "not_found" };
  const result = await call<{ id: string }>("duplicate_church_sermon", { p_sermon: sermon });
  if (!result.ok) return result;
  redirect(`/studio/${result.value.id}`);
}

export async function saveSermon(
  sermon: string,
  version: number,
  details: Partial<DraftDetails> & { cover?: string | null; review?: DraftReview | null },
  blocks: DraftBlock[] | null,
): Promise<ActionResult<{ version: number }>> {
  if (!isID(sermon) || !Number.isInteger(version)) return { ok: false, code: "not_found" };
  const result = await call<{ draft_version: number }>("save_church_sermon", {
    p_sermon: sermon,
    p_expected_version: version,
    p_details: details,
    p_blocks: blocks,
  });
  return result.ok ? { ok: true, version: result.value.draft_version } : result;
}

export async function publishSermon(sermon: string, version: number): Promise<ActionResult<{ number: number; withheld: number }>> {
  if (!isID(sermon) || !Number.isInteger(version)) return { ok: false, code: "not_found" };
  const result = await call<{ number: number; withheld_quotes: number }>("publish_church_sermon", { p_sermon: sermon, p_expected_version: version });
  return result.ok ? { ok: true, number: result.value.number, withheld: result.value.withheld_quotes } : result;
}

/** Unpublish or members-only: both take effect at once and move the version on (and say which version they moved on from). */
export async function closeSermon(sermon: string, how: "unpublish" | "restrict"): Promise<ActionResult<{ version: number; previous: number }>> {
  if (!isID(sermon)) return { ok: false, code: "not_found" };
  const result = await call<{ draft_version: number; previous_version: number }>(how === "unpublish" ? "unpublish_church_sermon" : "restrict_church_sermon", { p_sermon: sermon });
  return result.ok ? { ok: true, version: result.value.draft_version, previous: result.value.previous_version } : result;
}

export async function deleteSermon(sermon: string): Promise<ActionResult> {
  if (!isID(sermon)) return { ok: false, code: "not_found" };
  const result = await call<null>("delete_church_sermon", { p_sermon: sermon });
  return result.ok ? { ok: true } : result;
}

export async function setListed(church: string, listed: boolean): Promise<ActionResult> {
  if (!isID(church)) return { ok: false, code: "not_found" };
  const result = await call<null>("set_sermons_listed", { p_group: church, p_listed: listed === true });
  return result.ok ? { ok: true } : result;
}

/** Saves the church's Locations and Times (the whole list); the database cleans and checks it. */
export async function setLocations(church: string, locations: ChurchLocation[]): Promise<ActionResult<{ locations: ChurchLocation[] }>> {
  if (!isID(church) || !Array.isArray(locations)) return { ok: false, code: "not_found" };
  const text = (v: unknown) => (typeof v === "string" ? v : "");
  const clean = locations.map((l) => ({
    name: text(l?.name),
    street: text(l?.street),
    city: text(l?.city),
    region: text(l?.region),
    postal_code: text(l?.postal_code),
    country: text(l?.country),
    times: text(l?.times),
    gatherings: (Array.isArray(l?.gatherings) ? l.gatherings : []).map((g) =>
      g?.day ? { day: text(g.day), time: text(g.time), note: text(g.note) } : { date: text(g?.date), time: text(g?.time), note: text(g?.note) },
    ),
  }));
  const result = await call<ChurchLocation[]>("set_church_locations", { p_group: church, p_locations: clean });
  return result.ok ? { ok: true, locations: result.value } : result;
}

export async function reviewReports(sermon: string, keep: boolean): Promise<ActionResult> {
  if (!isID(sermon)) return { ok: false, code: "not_found" };
  const result = await call<null>("review_church_sermon_reports", { p_sermon: sermon, p_keep: keep === true });
  return result.ok ? { ok: true } : result;
}

const MAX_COVER = 1_000_000;

/**
 * Uploads a cover the browser already re-encoded (JPEG, at most 2000 px and
 * 1 MB, no metadata) to a fresh path, then puts it on the draft. The
 * picture is checked again here: JPEG signature and size.
 */
export async function uploadSermonCover(form: FormData): Promise<ActionResult<{ cover: string; version: number }>> {
  const session = await currentSession();
  if (!session) return { ok: false, code: "not_signed_in" };
  const sermon = form.get("sermon");
  const version = Number(form.get("version"));
  const file = form.get("cover");
  if (!isID(sermon) || !Number.isInteger(version) || !(file instanceof Blob)) return { ok: false, code: "invalid_details", detail: "cover" };
  const bytes = new Uint8Array(await file.arrayBuffer());
  if (bytes.length === 0 || bytes.length > MAX_COVER || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[2] !== 0xff) {
    return { ok: false, code: "cover_not_jpeg" };
  }
  const path = await call<{ cover: string; path: string }>("new_church_sermon_cover", { p_sermon: sermon });
  if (!path.ok) return path;
  const uploaded = await uploadCover(path.value.path, bytes.buffer as ArrayBuffer, session.accessToken).catch(() => null);
  if (!uploaded?.ok) return { ok: false, code: "cover_upload_failed" };
  const saved = await saveSermon(sermon, version, { cover: path.value.cover }, null);
  return saved.ok ? { ok: true, cover: path.value.cover, version: saved.version } : saved;
}
