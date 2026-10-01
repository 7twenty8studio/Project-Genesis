// group-notify: tells a group's members about a new announcement.
//
// POST /functions/v1/group-notify with the leader's access token and
//   { announcementID }
// right after the app posts an announcement. Returns { sent, removed }.
//
// - Only the announcement's author can trigger it, once, within an hour.
// - Members who turned notifications off for the group are skipped.
// - Needs the APNS_KEY (the .p8 file's text), APNS_KEY_ID and APNS_TEAM_ID
//   secrets; without them it does nothing and says so.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { apnsHost, apnsToken, isDeadToken, notificationPayload, NotifyError, parseNotifyRequest } from "./lib.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APNS_KEY = Deno.env.get("APNS_KEY");
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID");
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID");
const BUNDLE_ID = Deno.env.get("GENESIS_BUNDLE_ID") ?? "com.7twenty8studio.genesis";

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

    const { announcementID } = parseNotifyRequest(await req.json().catch(() => null));

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
    const userIDs = (members ?? []).map((member) => member.user_id);
    if (userIDs.length === 0) return json({ sent: 0, removed: 0 });

    // In batches, so a large group doesn't make an over-long request.
    const tokens: { user_id: string; token: string; environment: string }[] = [];
    for (const batch of chunks(userIDs, 100)) {
      const { data, error } = await admin.from("push_tokens").select("user_id, token, environment").in("user_id", batch);
      if (error) throw error;
      tokens.push(...(data ?? []));
    }
    const payload = JSON.stringify(notificationPayload(group?.name ?? "Your group", claimed));
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
        body: payload,
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
    return json({ sent, removed: dead.length });
  } catch (error) {
    if (error instanceof NotifyError) return json({ error: error.message }, error.status);
    console.error("group-notify failed", error);
    return json({ error: "Couldn't send notifications." }, 500);
  }
});

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
