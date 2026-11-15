// The screenshot-retention run, shared by dv-retention (nightly, pg_cron) and
// dv-admin's runCleanup action. Storage first, database after (contract rule 5):
// files are deleted through the Storage API, then mark_screenshots_deleted is
// called with only the paths confirmed gone; anything else stays listed and is
// retried next run. Then purge_expired removes reports older than a year (once
// their screenshots are gone) and idle rate-limit rows.
import { confirmedDeleted, groupDue, type DueScreenshot } from "../_shared/dailyVerse.ts";
import { asService, storage } from "../_shared/dailyVerseIO.ts";

export interface CleanupResult { deleted: number; failed: number; reportsPurged: number; rateLimitsPurged: number }

/** Paths of `requested` that still exist in the bucket. */
async function stillPresent(requested: string[]): Promise<string[] | null> {
  const folders = [...new Set(requested.map((p) => p.slice(0, p.lastIndexOf("/"))))];
  const present: string[] = [];
  for (const folder of folders) {
    const { data, error } = await storage.list(folder, { limit: 10 });
    if (error) return null;
    for (const item of data ?? []) present.push(`${folder}/${item.name}`);
  }
  return present;
}

export async function runCleanup(limit = 500): Promise<CleanupResult> {
  const due = await asService(async (tx) =>
    (await tx`select report_id::text as report_id, path from daily_verse.screenshots_due_for_deletion(${limit})`) as unknown as DueScreenshot[]
  );
  let deleted = 0;
  let failed = 0;
  for (const [reportId, paths] of groupDue(due)) {
    const { data, error } = await storage.remove(paths);
    const removed = (data ?? []).map((o: { name: string }) => o.name);
    const present = error ? paths : await stillPresent(paths.filter((p) => !removed.includes(p)));
    const gone = confirmedDeleted(paths, !error && present !== null, removed, present ?? paths);
    if (gone.length > 0) {
      await asService((tx) => tx`select daily_verse.mark_screenshots_deleted(${reportId}::uuid, ${gone}::text[])`);
    }
    deleted += gone.length;
    failed += paths.length - gone.length;
    if (error) console.error("dv-retention: Storage delete failed; paths stay listed", error.message);
  }
  const purged = await asService(async (tx) => (await tx`select daily_verse.purge_expired() as result`)[0].result) as
    { reports: number; rate_limits: number };
  return { deleted, failed, reportsPurged: purged.reports, rateLimitsPurged: purged.rate_limits };
}
