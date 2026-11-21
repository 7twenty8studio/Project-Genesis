// Church Studio's reads on the server, always as the signed-in person so the
// database's rules decide (owner or moderator, both switches on, not banned).
import type { DraftRow } from "./draft.ts";
import { rpc, select } from "./supabase.ts";
import type { Session } from "./session.ts";

export interface StudioChurch {
  id: string;
  name: string;
  role: "owner" | "moderator";
  listed: boolean;
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
  draft_version: number;
  unpublished_changes: boolean;
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
export const churchReports = (s: Session, group: string) => rpc<StudioReport[]>("group_sermon_reports", { p_group: group }, s.accessToken);

const DRAFT_COLUMNS =
  "id,group_id,slug,title,speaker,series,preached_on,time_zone,location,language,audience,cover_id,cover_alt,cover_decorative,draft_blocks,draft_version,status,live_audience,hidden_at,published_at,published_revision_id,draft_review";

/** The draft, if the person may edit it ("Leaders read" policy); null otherwise. */
export async function loadDraft(s: Session, id: string): Promise<(DraftRow & { published_draft_version: number | null }) | null> {
  if (!UUID.test(id)) return null;
  const rows = await select<DraftRow[]>(`church_sermons?id=eq.${id}&select=${DRAFT_COLUMNS}`, s.accessToken);
  const row = rows[0];
  if (!row) return null;
  let published: number | null = null;
  if (row.published_revision_id && UUID.test(row.published_revision_id)) {
    const revisions = await select<{ draft_version: number }[]>(`church_sermon_revisions?id=eq.${row.published_revision_id}&select=draft_version`, s.accessToken);
    published = revisions[0]?.draft_version ?? null;
  }
  return { ...row, published_draft_version: published };
}
