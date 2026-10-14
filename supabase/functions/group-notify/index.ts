// group-notify: tells a group's members about a new announcement, or one
// member about a nudge ("read with me today?").
//
// POST /functions/v1/group-notify with the sender's access token and
//   { announcementID }   right after the app posts an announcement, or
//   { nudgeID }          right after send_group_nudge. Returns { sent, removed }.
//
// - Only the announcement's author (or the nudge's sender) can trigger it,
//   once, within an hour.
// - Members who turned notifications off for the group (or Group
//   Announcements off in Settings, profiles.accepts_announcements) are skipped; a nudge
//   goes only to someone who accepts nudges (profiles.accepts_nudges).
// - Needs the APNS_KEY (the .p8 file's text), APNS_KEY_ID and APNS_TEAM_ID
//   secrets; without them it does nothing and says so.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { apnsHost, apnsToken, isDeadToken, notificationPayload, NotifyError, nudgePayload, parseNotifyRequest, parseNudgeRequest } from "./lib.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APNS_KEY = Deno.env.get("APNS_KEY");
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID");
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID");
const BUNDLE_ID = Deno.env.get("GENESIS_BUNDLE_ID") ?? "com.7twenty8studio.versely";

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });
let cachedToken: { value: string; issuedAt: number } | undefined;

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  try {
    const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "") ?? "";
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser(token);
    if (userError || !userData.user) return json({ error: "Sign in first." }, 401);

    const body = await req.json().catch(() => null);
    const nudge = parseNudgeRequest(body);
    if (nudge) return json(await sendNudge(nudge.nudgeID, userData.user.id));
    const { announcementID } = parseNotifyRequest(body);

    // Claim the announcement: the author's own, recent, and not sent before.
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { data: claimed, error: claimError } = await admin
      .from("group_announcements")
      .update({ notified_at: new Date().toISOString() })
      .eq("id", announcementID)
      .eq("user_id", userData.user.id)
      .is("notified_at", null)
      .is("deleted_at", null)
      .gte("created_at", since)
      .select("id, group_id, title, body")
      .maybeSingle();
    if (claimError) throw claimError;
    if (!claimed) return json({ sent: 0, removed: 0, reason: "not_found_or_already_sent" });

    if (!APNS_KEY || !APNS_KEY_ID || !APNS_TEAM_ID) {
      console.warn("group-notify: APNS_KEY, APNS_KEY_ID or APNS_TEAM_ID isn't set; nothing sent.");
      return json({ sent: 0, removed: 0, reason: "not_configured" });
    }

    // Still a leader of a group that's open, with groups switched on?
    const [{ data: group, error: groupError }, { data: leader, error: leaderError }, { data: flag, error: flagError }] = await Promise.all([
      admin.from("groups").select("name, deleted_at").eq("id", claimed.group_id).maybeSingle(),
      admin.from("group_members").select("role").eq("group_id", claimed.group_id).eq("user_id", userData.user.id).maybeSingle(),
      admin.from("feature_flags").select("enabled").eq("key", "groups").maybeSingle(),
    ]);
    if (groupError || leaderError || flagError) throw groupError ?? leaderError ?? flagError;
    if (!group || group.deleted_at || leader?.role !== "leader" || flag?.enabled !== true) {
      return json({ sent: 0, removed: 0, reason: "not_allowed" });
    }

    const { data: members, error: membersError } = await admin
      .from("group_members")
      .select("user_id")
      .eq("group_id", claimed.group_id)
      .eq("notifications", true)
      .neq("user_id", userData.user.id);
    if (membersError) throw membersError;
    let userIDs = (members ?? []).map((member) => member.user_id);
    // Members who turned Group Announcements off in Settings (kept on the
    // server so their devices can still take nudges).
    if (userIDs.length > 0) {
      const declined = new Set<string>();
      for (const batch of chunks(userIDs, 100)) {
        const { data, error } = await admin.from("profiles").select("user_id").in("user_id", batch).eq("accepts_announcements", false);
        if (error) throw error;
        for (const row of data ?? []) declined.add(row.user_id);
      }
      userIDs = userIDs.filter((id) => !declined.has(id));
    }
    if (userIDs.length === 0) return json({ sent: 0, removed: 0 });

    const payload = notificationPayload(group?.name ?? "Your group", claimed);
    return json(await deliver(userIDs, payload));
  } catch (error) {
    if (error instanceof NotifyError) return json({ error: error.message }, error.status);
    console.error("group-notify failed", error);
    return json({ error: "Couldn't send notifications." }, 500);
  }
});

/** Pushes one payload to every device of these accounts; forgets dead tokens. */
async function deliver(userIDs: string[], payload: Record<string, unknown>): Promise<{ sent: number; removed: number }> {
  // In batches, so a large group doesn't make an over-long request.
  const tokens: { user_id: string; token: string; environment: string }[] = [];
  for (const batch of chunks(userIDs, 100)) {
    const { data, error } = await admin.from("push_tokens").select("user_id, token, environment").in("user_id", batch);
    if (error) throw error;
    tokens.push(...(data ?? []));
  }
  const body = JSON.stringify(payload);
  const providerToken = await currentProviderToken();

  let sent = 0;
  const dead: { user_id: string; token: string }[] = [];
  // A few at a time keeps a large group from opening hundreds of connections.
  const queue = [...tokens];
  const send = (environment: string, token: string) =>
    fetch(`${apnsHost(environment)}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${providerToken}`,
        "apns-topic": BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body,
    });
  await Promise.all(Array.from({ length: Math.min(8, queue.length) }, async () => {
    for (let item = queue.shift(); item; item = queue.shift()) {
      let response = await send(item.environment, item.token);
      let reason = response.ok ? undefined : (await response.json().catch(() => ({})))?.reason;
      // A token from a differently signed build (e.g. a Release build run
      // from Xcode) belongs to the other service: try it there once.
      if (reason === "BadDeviceToken") {
        const other = item.environment === "sandbox" ? "production" : "sandbox";
        response = await send(other, item.token);
        reason = response.ok ? undefined : (await response.json().catch(() => ({})))?.reason;
        if (response.ok) {
          await admin.from("push_tokens").update({ environment: other }).eq("user_id", item.user_id).eq("token", item.token);
        }
      }
      if (response.ok) {
        sent += 1;
      } else if (isDeadToken(response.status, reason)) {
        dead.push({ user_id: item.user_id, token: item.token });
      } else {
        console.warn(`group-notify: APNs ${response.status} ${reason ?? ""}`);
      }
    }
  }));

  for (const item of dead) {
    await admin.from("push_tokens").delete().eq("user_id", item.user_id).eq("token", item.token);
  }
  return { sent, removed: dead.length };
}

/** A nudge: claimed once by its sender, pushed to the one member it's for. */
async function sendNudge(nudgeID: string, senderID: string): Promise<Record<string, unknown>> {
  const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { data: claimed, error: claimError } = await admin
    .from("group_nudges")
    .update({ notified_at: new Date().toISOString() })
    .eq("id", nudgeID)
    .eq("from_user", senderID)
    .is("notified_at", null)
    .gte("created_at", since)
    .select("id, group_id, to_user")
    .maybeSingle();
  if (claimError) throw claimError;
  if (!claimed) return { sent: 0, removed: 0, reason: "not_found_or_already_sent" };
  if (!APNS_KEY || !APNS_KEY_ID || !APNS_TEAM_ID) {
    console.warn("group-notify: APNS_KEY, APNS_KEY_ID or APNS_TEAM_ID isn't set; nothing sent.");
    return { sent: 0, removed: 0, reason: "not_configured" };
  }
  const [{ data: group }, { data: sender }, { data: profile }] = await Promise.all([
    admin.from("groups").select("name, deleted_at").eq("id", claimed.group_id).maybeSingle(),
    admin.from("group_members").select("display_name").eq("group_id", claimed.group_id).eq("user_id", senderID).maybeSingle(),
    admin.from("profiles").select("accepts_nudges").eq("user_id", claimed.to_user).maybeSingle(),
  ]);
  if (!group || group.deleted_at || !sender || profile?.accepts_nudges === false) {
    return { sent: 0, removed: 0, reason: "not_allowed" };
  }
  return await deliver([claimed.to_user], nudgePayload(group.name, claimed.group_id, sender.display_name));
}

/** Provider tokens last an hour; Apple asks for reuse rather than one per push. */
async function currentProviderToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now - cachedToken.issuedAt < 45 * 60) return cachedToken.value;
  const value = await apnsToken(APNS_KEY!, APNS_KEY_ID!, APNS_TEAM_ID!, now);
  cachedToken = { value, issuedAt: now };
  return value;
}

function chunks<T>(items: T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size) result.push(items.slice(index, index + size));
  return result;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}
