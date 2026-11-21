import type { Translate } from "@/lib/i18n";

type Status = { status: "draft" | "published" | "unpublished"; live_audience: "link" | "members" | null; hidden: boolean; unpublished_changes?: boolean };

/** Where a sermon stands, in words (never colour alone). */
export function StatusBadge({ sermon, t }: { sermon: Status; t: Translate }) {
  let label = t("Draft");
  if (sermon.status === "unpublished") label = t("Unpublished");
  if (sermon.status === "published") label = sermon.live_audience === "members" ? t("Published for members") : t("Published by link");
  if (sermon.status === "published" && sermon.hidden) label = t("Hidden until reviewed");
  const live = sermon.status === "published" && !sermon.hidden;
  return (
    <span className="flex flex-wrap items-center gap-2 text-sm">
      <span className={`rounded-full px-3 py-1 font-medium ${live ? "bg-accent-strong text-on-accent" : "bg-surface-2 text-foreground"}`}>{label}</span>
      {live && sermon.unpublished_changes ? <span className="text-muted">{t("Changes not published")}</span> : null}
    </span>
  );
}
