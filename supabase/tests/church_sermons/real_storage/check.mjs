// Cover access against a real Supabase Storage API (supabase/storage-api
// v1.25.7, file backend) and the real sermon-cover function in Supabase's
// Edge Runtime, on a local Postgres with every Versely migration applied.
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { jwt } from "./jwt.mjs";
// WORK (set by run.sh) holds ids.json, anon.key and service.key.

const GW = "http://127.0.0.1:54400";
const ids = JSON.parse(readFileSync(process.env.WORK + "/ids.json", "utf8"));
const anon = readFileSync(process.env.WORK + "/anon.key", "utf8").trim();
const service = readFileSync(process.env.WORK + "/service.key", "utf8").trim();
const person = (name) => jwt({ role: "authenticated", aud: "authenticated", sub: ids.people[name] });
const tokens = { anon, pastor: person("pastor"), moderator: person("moderator"), member: person("member"), outsider: person("outsider"), banned: person("banned") };
const path = ids.cover.path;
const results = [];
const check = (name, ok, detail = "") => results.push(`${ok ? "PASS" : "FAIL"} ${name}${ok ? "" : ` (${detail})`}`);

const sql = (q) => execFileSync(process.env.PSQL, ["-X", "-q", "-At", "-v", "ON_ERROR_STOP=1", "-h", "127.0.0.1", "-p", process.env.PGPORT_, "-U", "cs_super", "-d", "dvtest", "-c", q], { encoding: "utf8" }).trim();
const asPastor = (call) => sql(`select ct.run('pastor', ${"'" + call.split("'").join("''") + "'"})`);
const version = () => Number(sql(`select draft_version from public.church_sermons where id = '${ids.sermon}'`));

const headers = (token) => ({ apikey: anon, Authorization: `Bearer ${token}` });
const cover = (who) => fetch(`${GW}/functions/v1/sermon-cover?name=${encodeURIComponent(path)}`, { headers: headers(tokens[who]) });
const sign = (token) => fetch(`${GW}/storage/v1/object/sign/sermon-covers/${path}`, { method: "POST", headers: { ...headers(token), "Content-Type": "application/json" }, body: JSON.stringify({ expiresIn: 3600 }) });
const direct = (token) => fetch(`${GW}/storage/v1/object/authenticated/sermon-covers/${path}`, { headers: headers(token) });

const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(200, 7), Buffer.from([0xff, 0xd9])]);

// 1. A leader uploads with the INSERT policy alone.
const up = await fetch(`${GW}/storage/v1/object/sermon-covers/${path}`, { method: "POST", headers: { ...headers(tokens.pastor), "Content-Type": "image/jpeg", "x-upsert": "false" }, body: jpeg });
check("the pastor uploads the cover (INSERT policy only)", up.status === 200, `${up.status} ${await up.text()}`);
const member = await fetch(`${GW}/storage/v1/object/sermon-covers/${ids.grace}/${ids.sermon}/${crypto.randomUUID()}.jpg`, { method: "POST", headers: { ...headers(tokens.member), "Content-Type": "image/jpeg" }, body: jpeg });
check("a member cannot upload", member.status >= 400, String(member.status));

// 2. Nobody but the service role can sign a link or read the file directly.
for (const who of ["pastor", "moderator", "member", "outsider", "anon"]) {
  const s = await sign(tokens[who]);
  check(`${who} cannot create a signed link`, s.status >= 400, `${s.status} ${await s.text()}`);
  const d = await direct(tokens[who]);
  check(`${who} cannot download from storage directly`, d.status >= 400, String(d.status));
}
const listed = await fetch(`${GW}/storage/v1/object/list/sermon-covers`, { method: "POST", headers: { ...headers(tokens.pastor), "Content-Type": "application/json" }, body: JSON.stringify({ prefix: `${ids.grace}/${ids.sermon}` }) });
const listedBody = await listed.json().catch(() => null);
check("the pastor cannot list the bucket", Array.isArray(listedBody) ? listedBody.length === 0 : listed.status >= 400, JSON.stringify(listedBody));
const control = await sign(service);
check("control: the service role can sign (the endpoint works)", control.status === 200, String(control.status));

// 3. Through the sermon-cover function: a draft cover only for leaders.
asPastor(`public.save_church_sermon('${ids.sermon}', ${version()}, '{"cover": "${ids.cover.cover}"}', null)`);
const expect = async (label, who, status) => {
  const r = await cover(who);
  const body = Buffer.from(await r.arrayBuffer());
  const cc = r.headers.get("cache-control") ?? "";
  check(label, r.status === status && (status !== 200 || (body.equals(jpeg) && r.headers.get("content-type") === "image/jpeg")) && cc.includes("no-store") && cc.includes("private"), `${r.status} ${cc}`);
};
await expect("draft cover: the pastor gets it", "pastor", 200);
await expect("draft cover: a moderator gets it", "moderator", 200);
await expect("draft cover: a member does not", "member", 404);
await expect("draft cover: a guest does not", "anon", 404);

// 4. Published to the link: everyone, until it closes.
asPastor(`public.publish_church_sermon('${ids.sermon}', ${version()})`);
await expect("published: a guest gets it", "anon", 200);
await expect("published: an outsider gets it", "outsider", 200);
asPastor(`public.restrict_church_sermon('${ids.sermon}')`);
await expect("members only: the guest's next request is refused", "anon", 404);
await expect("members only: an outsider is refused", "outsider", 404);
await expect("members only: a banned person is refused", "banned", 404);
await expect("members only: a member still gets it", "member", 200);
sql(`insert into public.group_bans (group_id, user_id, display_name) values ('${ids.grace}', '${ids.people.member}', 'Member'); delete from public.group_members where group_id = '${ids.grace}' and user_id = '${ids.people.member}'`);
await expect("banned now: the member's next request is refused", "member", 404);
asPastor(`public.save_church_sermon('${ids.sermon}', ${version()}, '{"audience": "link"}', null)`);
asPastor(`public.publish_church_sermon('${ids.sermon}', ${version()})`);
await expect("open to the link again: a guest gets it", "anon", 200);
asPastor(`public.unpublish_church_sermon('${ids.sermon}')`);
await expect("unpublished: the guest's next request is refused", "anon", 404);
await expect("unpublished: an outsider is refused", "outsider", 404);
await expect("unpublished: the pastor still has it in Studio", "pastor", 200);
asPastor(`public.publish_church_sermon('${ids.sermon}', ${version()})`);
await expect("published again: a guest gets it", "anon", 200);
sql(`update public.feature_flags set enabled = false where key = 'church_sermons'`);
await expect("switch off: the guest's next request is refused", "anon", 404);
await expect("switch off: even the pastor is refused", "pastor", 404);
sql(`update public.feature_flags set enabled = true where key = 'church_sermons'`);

// 5. Bad requests.
const bad = await fetch(`${GW}/functions/v1/sermon-cover?name=${encodeURIComponent("../../etc/passwd")}`, { headers: headers(anon) });
check("a made-up name is refused", bad.status === 404, String(bad.status));
const forged = await fetch(`${GW}/functions/v1/sermon-cover?name=${encodeURIComponent(path)}`, { headers: headers(anon.slice(0, -4) + "AAAA") });
check("a forged token gets nothing", forged.status === 404, String(forged.status));

// 6. The test would have caught the problem: with checkpoint 2's first
// SELECT policy back, the pastor signs a link that works with no session.
sql(`alter policy "Sermon covers: leaders see" on storage.objects using (bucket_id = 'sermon-covers' and public.genesis_can_edit_cover(name))`);
const old = await sign(tokens.pastor);
const signed = old.status === 200 ? (await old.json()).signedURL : null;
const leaked = signed ? await fetch(`${GW}/storage/v1${signed}`) : null;
check("control: with the old SELECT policy a signed link works without a session (what this fix stops)", leaked?.status === 200, String(old.status));
sql(`alter policy "Sermon covers: leaders see" on storage.objects using (false)`);
const after = await sign(tokens.pastor);
check("and with the policy switched off again, signing is refused", after.status >= 400, String(after.status));

console.log(results.join("\n"));
const failed = results.filter((r) => r.startsWith("FAIL")).length;
console.log(failed ? `${failed} of ${results.length} failed` : `all ${results.length} passed`);
process.exit(failed ? 1 : 0);
