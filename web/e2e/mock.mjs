// A stand-in for the Versely Supabase project, for the browser checks in
// check.cjs only (web/e2e/run.sh). It answers like the database's functions
// for one church (Grace Church), a draft, a link sermon and a members-only
// sermon; the access rules themselves are tested against Postgres in
// supabase/tests/church_sermons. Nothing here talks to the network.
import { createServer } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { numberBlanks } from "../src/lib/blanks.ts";

const BIBLES = process.env.MOCK_BIBLES ?? "build/web-bibles";
const GROUP = "11111111-1111-4111-8111-111111111111";
const DRAFT = "22222222-2222-4222-8222-222222222222";
const LIVE = "33333333-3333-4333-8333-333333333333";
const MEMBERS = "55555555-5555-4555-8555-555555555555";
const HANDOUT = "77777777-7777-4777-8777-777777777777";
const covers = new Map(); // path -> Buffer
const sermons = new Map();
const base = {
  group_id: GROUP, speaker: "Pastor Ana", series: "Rest", preached_on: "2026-11-22", time_zone: "America/Chicago",
  location: "Main campus", language: "en", audience: "link", cover_id: null, cover_alt: "", cover_decorative: false,
  hidden_at: null, published_revision_id: null, published_at: null, live_audience: null, status: "draft", draft_review: null,
  answers: "reveal", answers_revealed_revision_id: null,
};
let failSaves = false;
let slowClose = 0;
sermons.set(DRAFT, { ...base, id: DRAFT, slug: "draftdraft", title: "", draft_blocks: [], draft_version: 0, language: process.env.MOCK_LANG ?? "en" });
const liveBlocks = [
  { id: "a", kind: "paragraph", text: "Jesus invites the weary to come." },
  { id: "h1", kind: "heading", text: "Come to me", level: 2 },
  { id: "s1", kind: "scripture", ref: { raw: "Matthew 11:28-30", start: 40011028, end: 40011030, status: "verified", label: "KJV", quote: "Come unto me" } },
  { id: "l", kind: "list", items: ["All who labor", "All who are heavy laden"], ordered: true },
  { id: "h2", kind: "heading", text: "Learn from me", level: 2 },
  { id: "s2", kind: "scripture", ref: { raw: "Rom 8:28", start: 45008028, end: 45008028, status: "verified", label: "NIV", quote: "And we know" } },
  { id: "q", kind: "quote", text: "Rest is a gift, not a reward." },
  { id: "s3", kind: "scripture", ref: { raw: "Psalm 151", start: null, end: null, status: "ambiguous", label: null, quote: null } },
];
sermons.set(LIVE, { ...base, id: LIVE, slug: "livelivel1", title: "Rest for the Weary", draft_blocks: liveBlocks, draft_version: 3, status: "published", live_audience: "link", published_at: "2026-11-15T15:00:00Z", published_revision_id: "44444444-4444-4444-8444-444444444444", published_version: 3 });
sermons.set(MEMBERS, { ...base, id: MEMBERS, slug: "membmemb01", title: "Members Night Secret", audience: "members", draft_blocks: [{ id: "m", kind: "paragraph", text: "Only for members of Grace Church." }], draft_version: 1, status: "published", live_audience: "members", published_at: "2026-11-14T15:00:00Z", published_revision_id: "66666666-6666-4666-8666-666666666666", published_version: 1 });

// A fill-in-the-blank handout (20261128000000), published, its key not yet revealed.
sermons.set(HANDOUT, { ...base, id: HANDOUT, slug: "handout001", title: "Gratitude That Interrupts", draft_blocks: [
  { id: "h", kind: "heading", text: "1. Gratitude starts with [[Seeing|S]] God the [[Giver]]", level: 2 },
  { id: "l", kind: "list", items: ["Something I'm thankful for: [[...]]"], ordered: false },
  { id: "q", kind: "quote", text: "Give thanks in all circumstances." },
], draft_version: 2, status: "published", live_audience: "link", published_at: "2026-11-22T15:00:00Z", published_revision_id: "88888888-8888-4888-8888-888888888888", published_version: 2 });

function publishable(blocks) {
  const codes = { kjv: "KJV", web: "WEB", asv: "ASV", rv1909: "RV1909", blivre: "BLIVRE" };
  return blocks.map((b) => {
    if (b.kind !== "scripture") return b;
    const { quote, ...ref } = b.ref;
    const translation = ref.status === "verified" ? codes[(ref.label ?? "").toLowerCase().replace(/[^a-z0-9]/g, "")] ?? null : null;
    return { ...b, ref: { ...ref, translation, quote_withheld: !!quote && !translation } };
  });
}
let churchLocations = [];
let inviteCode = "GRACE12345";
function published(s) {
  const numbered = numberBlanks(publishable(s.published_blocks ?? s.draft_blocks));
  const mode = s.published_answers ?? s.answers;
  const revealed = mode === "now" || (mode === "reveal" && !!s.published_revision_id && s.answers_revealed_revision_id === s.published_revision_id);
  return {
    answers: mode === "never" ? "never" : revealed ? "revealed" : "hidden",
    blanks: numbered.blanks.map((b) => ({ n: b.n, open: b.answer === null, hint: b.hint, ...(revealed ? { answer: b.answer } : {}) })),
    status: "ok", id: s.id, slug: s.slug, group_id: GROUP, church: "Grace Church", title: s.title, speaker: s.speaker, series: s.series,
    preached_on: s.preached_on, time_zone: s.time_zone, location: s.location, language: s.language,
    cover: s.cover_id ? { id: s.cover_id, path: `${GROUP}/${s.id}/${s.cover_id}.jpg`, alt: s.cover_alt, decorative: s.cover_decorative } : null,
    audience: s.live_audience, revision: s.revision ?? 1, published_at: s.published_at, blocks: numbered.blocks,
    previous: { slug: "prevprev01", title: "Weary and Worn", speaker: "Pastor Ana", series: "Rest", preached_on: "2026-11-15", audience: "link" }, next: null, locations: churchLocations, is_member: false,
  };
}
const fail = (res, message, status = 400) => send(res, status, { code: "P0001", message, details: null });
function send(res, status, body, type = "application/json") {
  res.writeHead(status, { "Content-Type": type, "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, *" });
  res.end(type === "application/json" ? JSON.stringify(body) : body);
}
const read = (req) => new Promise((done) => { const chunks = []; req.on("data", (c) => chunks.push(c)); req.on("end", () => done(Buffer.concat(chunks))); });
const signedIn = (req) => /leader-token|preacher-token/.test(req.headers.authorization ?? "");
// A preacher (20261126000000): their own sermons, others' published ones read-only, no settings.
const isPreacher = (req) => (req.headers.authorization ?? "").includes("preacher-token");
const who = (req) => (isPreacher(req) ? "u2" : "u1");
let people = [
  { user_id: "00000000-0000-4000-8000-0000000000a1", name: "Ana", role: "owner", joined_at: "2026-11-01T00:00:00Z", sermons: 3, me: true },
  { user_id: "00000000-0000-4000-8000-0000000000a2", name: "Ben", role: "admin", joined_at: "2026-11-02T00:00:00Z", sermons: 0, me: false },
  { user_id: "00000000-0000-4000-8000-0000000000a3", name: "Cara", role: "preacher", joined_at: "2026-11-03T00:00:00Z", sermons: 1, me: false },
  { user_id: "00000000-0000-4000-8000-0000000000a4", name: "Dan", role: "member", joined_at: "2026-11-04T00:00:00Z", sermons: 0, me: false },
];

createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  if (req.method === "OPTIONS") return send(res, 204, "", "text/plain");
  const body = await read(req);
  const json = () => (body.length ? JSON.parse(body.toString()) : {});
  const p = url.pathname;
  // Email and password sign-in: pastor@example.com / right-password is the leader's account.
  if (p === "/auth/v1/token" && url.searchParams.get("grant_type") === "password") {
    const { email, password } = json();
    if (email === "unconfirmed@example.com") return send(res, 400, { code: 400, error_code: "email_not_confirmed", msg: "Email not confirmed" });
    if (email !== "pastor@example.com" || password !== "right-password") return send(res, 400, { code: 400, error_code: "invalid_credentials", msg: "Invalid login credentials" });
    return send(res, 200, { access_token: "leader-token", refresh_token: "r", expires_in: 3600, user: { id: "u1", user_metadata: { full_name: "Ana" } } });
  }
  if (p === "/auth/v1/recover") return send(res, 200, {});
  if (p.startsWith("/storage/v1/object/public/bibles/")) {
    const file = `${BIBLES}/${p.slice("/storage/v1/object/public/bibles/".length)}`;
    return existsSync(file) ? send(res, 200, readFileSync(file), "application/json; charset=utf-8") : send(res, 404, { error: "not found" });
  }
  if (p === "/functions/v1/sermon-events") return send(res, 200, { ok: true });
  // A YouVersion Bible's passage: stand-in words (never a licensed text), one footnote.
  if (p === "/functions/v1/yvp-web-passage") {
    const a = json();
    if (a.bible !== "NIV") return send(res, 404, { error: "This Bible isn't offered on the web." });
    return send(res, 200, {
      bible: "NIV", name: "New International Version", language: "en",
      license: "Stand-in notice line one\nStand-in notice line two", publisherUrl: "https://www.biblica.com",
      verses: [{ c: 8, v: 28, k: [45008028], t: "Stand-in words for a licensed verse", n: [{ o: 13, t: "Stand-in footnote" }] }],
    });
  }
  if (p.startsWith("/storage/v1/object/sermon-covers/") && req.method === "POST") {
    if (!signedIn(req)) return send(res, 403, {});
    covers.set(p.slice("/storage/v1/object/sermon-covers/".length), body);
    return send(res, 200, { Key: p });
  }
  if (p === "/mock/slow-close") { slowClose = Number(url.searchParams.get("ms") ?? 0); return send(res, 200, { slowClose }); }
  if (p === "/mock/fail-saves") { failSaves = url.searchParams.get("on") === "1"; return send(res, 200, { failSaves }); }
  if (p === "/mock/touch") { const t = sermons.get(url.searchParams.get("id")); t.title = url.searchParams.get("title"); if (url.searchParams.get("publish")) { t.status = "published"; t.live_audience = t.audience; } t.draft_version++; return send(res, 200, t); }
  if (p === "/mock/reveal") { const t = sermons.get(url.searchParams.get("id")); t.answers_revealed_revision_id = url.searchParams.get("on") === "1" ? t.published_revision_id : null; return send(res, 200, t); }
  if (p === "/mock/sermon") return send(res, 200, sermons.get(url.searchParams.get("id")) ?? null);
  if (p.startsWith("/storage/v1/object/authenticated/sermon-covers/")) return send(res, 400, { error: "no client reads covers" });
  if (p === "/functions/v1/sermon-cover") {
    const path = url.searchParams.get("name") ?? "";
    return covers.has(path) ? send(res, 200, covers.get(path), "image/jpeg") : send(res, 400, { error: "not found" });
  }
  if (p === "/rest/v1/profiles") return send(res, 200, []);
  if (p === "/rest/v1/groups") return send(res, 200, signedIn(req) ? [{ invite_code: inviteCode, requires_approval: false }] : []);
  if (p === "/rest/v1/church_sermons") {
    if (!signedIn(req)) return send(res, 200, []);
    const id = (url.searchParams.get("id") ?? "").replace("eq.", "");
    const s = sermons.get(id);
    if (s && isPreacher(req) && s.created_by !== "u2") return send(res, 200, []);
    return send(res, 200, s && !s.deleted ? [{ ...s, created_by: s.created_by === "u2" ? people[2].user_id : people[0].user_id }] : []);
  }
  if (p === "/rest/v1/church_sermon_revisions") {
    const rev = (url.searchParams.get("id") ?? "").replace("eq.", "");
    const s = [...sermons.values()].find((x) => x.published_revision_id === rev) ?? sermons.get(LIVE);
    return send(res, 200, [{ draft_version: s.published_version, answers: s.published_answers ?? s.answers }]);
  }
  if (p.startsWith("/rest/v1/rpc/")) {
    const fn = p.slice("/rest/v1/rpc/".length);
    const a = json();
    if (fn === "published_sermon") {
      const s = [...sermons.values()].find((x) => x.slug === a.p_slug && x.status === "published" && !x.deleted);
      if (!s) return send(res, 200, { status: "not_found" });
      if (s.live_audience === "members" && !signedIn(req)) return send(res, 200, { status: "members_only" });
      return send(res, 200, published(s));
    }
    if (fn === "youversion_web_bibles") return send(res, 200, [{ id: "NIV", name: "New International Version", language: "en" }]);
    if (!signedIn(req)) return fail(res, "not_allowed", 400);
    const s = sermons.get(a.p_sermon);
    if (isPreacher(req) && ["new_invite_code", "set_church_locations", "set_sermons_listed", "review_church_sermon_reports"].includes(fn)) return fail(res, fn === "new_invite_code" ? "leaders_only" : "not_allowed");
    if (isPreacher(req) && s && s.created_by !== "u2") return fail(res, "not_allowed");
    switch (fn) {
      case "my_sermon_churches":
        if (isPreacher(req)) return send(res, 200, [{ id: GROUP, name: "Grace Church", role: "preacher", listed: false, locations: churchLocations }]);
        return send(res, 200, [
          { id: GROUP, name: "Grace Church", role: "owner", listed: false, locations: churchLocations },
          // A second church, so Studio shows its church picker.
          { id: "00000000-0000-4000-8000-00000000c4a2", name: "Hope Chapel Youth Ministry", role: "admin", listed: false, locations: [] },
        ]);
      case "new_invite_code":
        inviteCode = "NEWCODE789";
        return send(res, 200, inviteCode);
      case "set_church_locations": {
        // Mirrors genesis_clean_church_locations (20261125000000): parts, the one-line address worked out, gatherings.
        const tx = (v) => (v ?? "").trim();
        const list = (a.p_locations ?? []).map((l) => {
          const p = { name: tx(l.name), street: tx(l.street), city: tx(l.city), region: tx(l.region), postal_code: tx(l.postal_code), country: tx(l.country), address: tx(l.address), times: tx(l.times) };
          const cityLine = [p.city, [p.region, p.postal_code].filter(Boolean).join(" ")].filter(Boolean).join(", ");
          const parts = [p.street, cityLine, p.country].filter(Boolean);
          if (parts.length) p.address = parts.join(", ");
          p.gatherings = (l.gatherings ?? []).map((g) => ({ ...(g.day ? { day: g.day } : { date: g.date }), time: g.time, note: tx(g.note) }));
          return p;
        });
        const badGathering = (g) => !!g.day === !!g.date || !/^([01]\d|2[0-3]):[0-5]\d$/.test(g.time ?? "") || (g.date && !/^\d{4}-\d{2}-\d{2}$/.test(g.date)) || g.note.length > 60;
        if (list.length > 10 || list.some((l) => !l.name || l.name.length > 80 || l.address.length > 200 || l.times.length > 300 || l.gatherings.length > 20 || l.gatherings.some(badGathering))) return fail(res, "invalid_locations");
        churchLocations = list;
        return send(res, 200, list);
      }
      case "group_sermons": {
        const me = who(req);
        const rows = [...sermons.values()].filter((x) => !x.deleted && (!isPreacher(req) || (x.created_by ?? "u1") === me || x.status === "published"));
        return send(res, 200, rows.map((x) => {
          const mine = (x.created_by ?? "u1") === me;
          const started = (x.created_by ?? "u1") === "u2" ? "Cara" : "Ana";
          return { ...x, hidden: false, has_cover: !!x.cover_id, unpublished_changes: x.status === "published" && x.published_version !== x.draft_version,
            mine, can_edit: !isPreacher(req) || mine, started_by: started, edited_by: x.edited_by ?? started };
        }));
      }
      case "delete_group":
        if (isPreacher(req)) return fail(res, "owner_only");
        return send(res, 200, null);
      case "church_people":
        if (isPreacher(req)) return fail(res, "not_allowed");
        return send(res, 200, people);
      case "set_church_role": {
        if (isPreacher(req) && !(a.p_user === people[2].user_id && a.p_role === "member")) return fail(res, "not_allowed");
        people = people.map((x) => (x.user_id === a.p_user ? { ...x, role: a.p_role } : x));
        return send(res, 200, null);
      }
      case "change_sermon_owner":
        if (isPreacher(req)) return fail(res, "not_allowed");
        if (!people.some((x) => x.user_id === a.p_user && (x.role === "admin" || x.role === "preacher" || x.role === "owner"))) return fail(res, "not_a_writer");
        if (s) s.created_by = a.p_user === people[2].user_id ? "u2" : "u1";
        return send(res, 200, null);
      case "group_sermon_reports":
        if (isPreacher(req)) return send(res, 200, []);
        return send(res, 200, [{ sermon_id: LIVE, slug: "livelivel1", title: "Rest for the Weary", hidden: false, report_count: 1, reasons: ["Typo in point two"], last_reported_at: "2026-11-20T10:00:00Z" }]);
      case "create_church_sermon": {
        const id = randomUUID();
        sermons.set(id, { ...base, id, slug: Math.random().toString(36).slice(2, 12).padEnd(10, "a"), title: "", draft_blocks: [], draft_version: 0, time_zone: null, created_by: who(req) });
        return send(res, 200, { id, slug: sermons.get(id).slug, draft_version: 0 });
      }
      case "save_church_sermon": {
        if (!s) return fail(res, "not_found");
        if (failSaves) return send(res, 503, { message: "unavailable" });
        if (a.p_expected_version !== s.draft_version) return fail(res, "draft_changed");
        const d = a.p_details ?? {};
        for (const [k, v] of Object.entries(d)) if (k === "cover") s.cover_id = v; else if (k === "review") s.draft_review = v; else s[k] = v;
        if (a.p_blocks) s.draft_blocks = a.p_blocks;
        s.draft_version += 1;
        return send(res, 200, { draft_version: s.draft_version });
      }
      case "publish_church_sermon": {
        if (a.p_expected_version !== s.draft_version) return fail(res, "draft_changed");
        if (!s.title.trim()) return fail(res, "needs_title");
        const r = s.draft_review;
        const open = (r?.items ?? []).filter((i) => !r.decisions?.[i.key] && !(i.kind === "note" && !(i.note?.count > 0))
          && !(i.kind === "reference" && !s.draft_blocks.some((b) => b.id === i.blockId && b.kind === "scripture" && b.ref.status === "ambiguous"))
          && !(i.kind === "quotation" && !s.draft_blocks.some((b) => b.id === i.blockId && b.kind !== "scripture")));
        if (open.length) return fail(res, "review_open");
        let blankCount = 0;
        try {
          blankCount = numberBlanks(s.draft_blocks).blanks.length;
          if (numberBlanks(s.draft_blocks).blanks.some((b) => b.answer === "")) return fail(res, "blank_needs_answer");
        } catch { /* as the database: only numbered blanks */ }
        s.revision = (s.revision ?? 1) + (s.status === "published" ? 1 : 0);
        s.published_revision_id = randomUUID(); s.published_answers = s.answers;
        s.status = "published"; s.live_audience = s.audience; s.published_at = new Date().toISOString(); s.published_version = s.draft_version; s.published_blocks = s.draft_blocks;
        const withheld = publishable(s.draft_blocks).filter((b) => b.kind === "scripture" && b.ref.quote_withheld).length;
        return send(res, 200, { revision: s.published_revision_id, number: s.revision, withheld_quotes: withheld, draft_version: s.draft_version, repeated: false, blanks: blankCount });
      }
      case "reveal_church_sermon_answers": {
        if (s.status !== "published") return fail(res, "not_published");
        if ((s.published_answers ?? s.answers) !== "reveal") return fail(res, "answers_not_manual");
        s.answers_revealed_revision_id = a.p_reveal ? s.published_revision_id : null;
        return send(res, 200, { revealed: !!a.p_reveal, revision: s.revision ?? 1 });
      }
      case "unpublish_church_sermon": if (slowClose) await new Promise((r) => setTimeout(r, slowClose));
        // falls through to the change
      case "unpublish_church_sermon_now": s.status = "unpublished"; s.draft_version++; return send(res, 200, { draft_version: s.draft_version, previous_version: s.draft_version - 1 });
      case "restrict_church_sermon": s.audience = "members"; if (s.live_audience) s.live_audience = "members"; s.draft_version++; return send(res, 200, { draft_version: s.draft_version, previous_version: s.draft_version - 1 });
      case "delete_church_sermon": s.deleted = true; return send(res, 200, null);
      case "duplicate_church_sermon": { const id = randomUUID(); sermons.set(id, { ...s, id, slug: "dupdupdup1", status: "draft", draft_version: 0, cover_id: null, preached_on: null }); return send(res, 200, { id, slug: "dupdupdup1", draft_version: 0 }); }
      case "new_church_sermon_cover": { const cover = randomUUID(); return send(res, 200, { cover, path: `${GROUP}/${s.id}/${cover}.jpg` }); }
      case "set_sermons_listed": case "review_church_sermon_reports": return send(res, 200, null);
      case "my_groups_for_sermons": return send(res, 200, [{ id: "00000000-0000-4000-8000-0000000000b1", name: "Tuesday Bible Study" }]);
      case "create_sermon_church":
        if (!a.p_your_name) return fail(res, "name_required");
        return send(res, 200, { id: GROUP, name: a.p_name });
      case "set_church_sermons": return send(res, 200, null);
    }
    return fail(res, `unknown ${fn}`, 404);
  }
  send(res, 404, { error: p });
}).listen(54329, () => console.log("mock on 54329"));
