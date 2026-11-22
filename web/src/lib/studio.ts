// Church Studio's rules that don't need a browser (VRS-18), so they're tested
// in Node: what readers will get from a draft (the same as
// genesis_publishable_blocks), why Publish is off, and the words for each
// database refusal.
import { draftProblems, quoteTranslation, type DraftBlock, type DraftRow } from "./draft.ts";
import type { Block, PublishedSermon } from "./outline.ts";
import { reviewDone, stillOpen, type Decision, type ReviewItem } from "./import/review.ts";

/** What readers get from these blocks: quoted words never, only a translation code to show from Versely's own copy. */
export function publishableBlocks(blocks: DraftBlock[]): Block[] {
  return blocks.map((b): Block => {
    if (b.kind !== "scripture") return b;
    const { quote, ...ref } = b.ref;
    const translation = ref.status === "verified" ? quoteTranslation(ref.label) : null;
    return { ...b, ref: { ...ref, translation, quote_withheld: quote !== null && quote !== "" && translation === null } };
  });
}

/** The draft as its published page will look (Studio's preview). */
export function previewSermon(row: DraftRow, church: string): PublishedSermon {
  return {
    status: "ok",
    id: row.id,
    slug: row.slug,
    group_id: row.group_id,
    church,
    title: row.title,
    speaker: row.speaker,
    series: row.series,
    preached_on: row.preached_on,
    time_zone: row.time_zone,
    location: row.location,
    language: row.language,
    audience: row.audience,
    revision: 0,
    published_at: row.published_at ?? "",
    cover: row.cover_id ? { id: row.cover_id, path: "", alt: row.cover_decorative ? "" : row.cover_alt, decorative: row.cover_decorative } : null,
    blocks: publishableBlocks(row.draft_blocks),
    previous: null,
    next: null,
    is_member: true,
  };
}

export type Blocker = "needs_title" | "empty_outline" | "needs_cover_alt" | "review_open" | "invalid_blocks" | "saving";

/** Everything that keeps Publish off, in the order Studio lists them. */
export function publishBlockers(
  row: Pick<DraftRow, "title" | "cover_id" | "cover_alt" | "cover_decorative" | "draft_blocks">,
  review: { items: ReviewItem[]; decisions: Record<string, Decision | undefined> } | null,
  saving = false,
): Blocker[] {
  const out: Blocker[] = [];
  if (row.title.trim() === "") out.push("needs_title");
  if (row.draft_blocks.length === 0) out.push("empty_outline");
  if (row.cover_id && !row.cover_decorative && row.cover_alt.trim() === "") out.push("needs_cover_alt");
  if (review && !reviewDone(stillOpen(review.items, row.draft_blocks), review.decisions)) out.push("review_open");
  if (draftProblems(row.draft_blocks).length) out.push("invalid_blocks");
  if (saving) out.push("saving");
  return out;
}

/**
 * After Unpublish or Members only: the editor may take the new version (and
 * save any pending edit on it) only if the draft it moved on from is the one
 * this editor has. Otherwise another window or leader changed the draft, and
 * saving this editor's older copy on top would overwrite their work.
 */
export function afterClose(previous: number, known: number, conflicted: boolean): "adopt" | "conflict" {
  return !conflicted && previous === known ? "adopt" : "conflict";
}

// translatable returns
/** The English message for a database refusal (translated by the caller). */
export function refusalMessage(code: string): string {
  switch (code) {
    case "draft_changed":
      return "This sermon was changed in another window or by another leader. Reload to see the latest version.";
    case "needs_title":
      return "Give the sermon a title before publishing.";
    case "needs_cover_alt":
      return "Describe the cover picture, or mark it as decorative.";
    case "cover_missing":
      return "The cover picture is missing. Choose it again.";
    case "empty_outline":
      return "Add something to the outline before publishing.";
    case "review_open":
      return "Finish checking the import before publishing.";
    case "invalid_blocks":
      return "Part of the outline can't be saved. Check the items marked in red.";
    case "invalid_locations":
      return "Give each place a name and each one-time gathering a date. Check that nothing is too long, with at most 10 places and 20 times each.";
    case "invalid_details":
      return "One of the details is too long or not valid.";
    case "not_allowed":
      return "You can't do that here. A church's owner and admins look after every sermon and setting, and a preacher looks after the sermons they started.";
    case "not_found":
      return "This sermon no longer exists.";
    case "invalid_group":
      return "Give it a name of up to 60 characters.";
    case "name_required":
      return "Add your name, as people will see it.";
    case "objectionable_content":
      return "Some words aren't allowed. Please choose another name.";
    case "too_many_churches":
      return "You've started three churches or ministries today. Try again tomorrow.";
    case "too_many_groups":
      return "You've reached the limit of 20 groups. Delete one in Versely to start another.";
    case "leaders_only":
      return "Only the church's owner and admins can make a new code.";
    case "invalid_role":
      return "That role isn't one Church Studio knows. Choose Admin, Preacher or Member.";
    case "owner_role_fixed":
      return "The owner's role can't change. To step back, hand the church to someone else in the Versely app first.";
    case "not_a_writer":
      return "Hand sermons only to the church's preachers and admins.";
    case "not_signed_in":
      return "Your sign-in has ended. Sign in again.";
    default:
      return "Something went wrong. Try again in a moment.";
  }
}

/** Finds where words left out by an import belong: after the block that holds the words before them. */
export function placeFor(blocks: DraftBlock[], before: string[], wordsOf: (b: DraftBlock) => string[]): number {
  if (before.length === 0) return 0;
  for (let i = blocks.length - 1; i >= 0; i--) {
    const w = wordsOf(blocks[i]);
    const tail = w.slice(-before.length);
    if (tail.length === before.length && tail.every((x, k) => x === before[k])) return i + 1;
  }
  for (let i = blocks.length - 1; i >= 0; i--) if (wordsOf(blocks[i]).includes(before[before.length - 1])) return i + 1;
  return blocks.length;
}
