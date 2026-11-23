// Church Studio's reads on the server, always as the signed-in person so the
// database's rules decide (owner, admin or preacher, both switches on, not
// banned; a preacher only for the sermons they started).
import type { AnswersMode } from "./blanks.ts";
import type { DraftRow } from "./draft.ts";
import type { ChurchLocation } from "./locations.ts";
import { rpc, select } from "./supabase.ts";
import type { Session } from "./session.ts";

export interface StudioChurch {
  id: string;
  name: string;
  role: ChurchRole;
  listed: boolean;
  locations?: ChurchLocation[];
}

/** The caller's role in the church: owner, admin (the group's moderator) or preacher (their own sermons only). */
export type ChurchRole = "owner" | "admin" | "preacher";

/** Owner and admins run the church; a preacher looks after their own sermons. */
export const runsChurch = (church: { role: string }) => church.role !== "preacher";

export interface ChurchPerson {
  user_id: string;
  name: string;
  role: "owner" | "admin" | "preacher" | "member";
  joined_at: string;
  sermons: number;
  me: boolean;
}

export interface StudioSermon {
  id: string;
  slug: string;
  title: string;
  speaker: string;
  series: string | null;
  preached_on: string | null;
  audience: "link" | "members";
  status: "draft" | "published" | "unpublished";
  live_audience: "link" | "members" | null;
  hidden: boolean;
  published_at: string | null;
  draft_version: number | null;
  unpublished_changes: boolean;
  /** Started by the caller. */
  mine?: boolean;
  /** False for another preacher's published sermon (read-only for a preacher). */
  can_edit?: boolean;
  started_by?: string | null;
  edited_by?: string | null;
}

export interface StudioReport {
  sermon_id: string;
  slug: string;
  title: string;
  hidden: boolean;
  report_count: number;
  reasons: string[];
  last_reported_at: string;
}

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export const myChurches = (s: Session) => rpc<StudioChurch[]>("my_sermon_churches", {}, s.accessToken);
export const churchSermons = (s: Session, group: string) => rpc<StudioSermon[]>("group_sermons", { p_group: group }, s.accessToken);
export const myGroupsForSermons = (s: Session) => rpc<{ id: string; name: string }[]>("my_groups_for_sermons", {}, s.accessToken);
/** The person's display name in Versely (groups), or null before they've chosen one. */
export async function myDisplayName(s: Session): Promise<string | null> {
  const rows = await select<{ display_name: string }[]>(`profiles?select=display_name&user_id=eq.${encodeURIComponent(s.userId)}`, s.accessToken).catch(() => []);
  return rows[0]?.display_name ?? null;
}
/** The church's group invite code ("Members read" policy on groups; leaders are members). */
export async function churchInvite(s: Session, group: string): Promise<{ invite_code: string; requires_approval: boolean } | null> {
  if (!UUID.test(group)) return null;
  const rows = await select<{ invite_code: string; requires_approval: boolean }[]>(`groups?id=eq.${group}&select=invite_code,requires_approval`, s.accessToken).catch(() => []);
  return rows[0] ?? null;
}
/** The church's people with their roles (owner and admins only). */
export const churchPeople = (s: Session, group: string) => rpc<ChurchPerson[]>("church_people", { p_group: group }, s.accessToken);
export const churchReports = (s: Session, group: string) => rpc<StudioReport[]>("group_sermon_reports", { p_group: group }, s.accessToken);

const DRAFT_COLUMNS =
  "id,group_id,slug,title,speaker,series,preached_on,time_zone,location,language,audience,cover_id,cover_alt,cover_decorative,draft_blocks,draft_version,status,live_audience,hidden_at,published_at,published_revision_id,draft_review,answers,answers_revealed_revision_id";

/** The draft, if the person may edit it ("Leaders read" and "Preachers read their own" policies); null otherwise. */
export async function loadDraft(s: Session, id: string): Promise<(DraftRow & { published_draft_version: number | null; published_answers: AnswersMode | null; created_by: string | null }) | null> {
  if (!UUID.test(id)) return null;
  const rows = await select<(DraftRow & { created_by: string | null })[]>(`church_sermons?id=eq.${id}&select=${DRAFT_COLUMNS},created_by`, s.accessToken);
  const row = rows[0];
  if (!row) return null;
  let published: number | null = null;
  let answers: AnswersMode | null = null;
  if (row.published_revision_id && UUID.test(row.published_revision_id)) {
    const revisions = await select<{ draft_version: number; answers: AnswersMode }[]>(`church_sermon_revisions?id=eq.${row.published_revision_id}&select=draft_version,answers`, s.accessToken);
    published = revisions[0]?.draft_version ?? null;
    answers = revisions[0]?.answers ?? null;
  }
  return { ...row, published_draft_version: published, published_answers: answers };
}
