// yvp-catalog: which YouVersion Platform Bibles Versely's app key can use.
// An owner tool, not called by the app. Run it from the SQL editor:
//   select net.http_post(
//     url := 'https://ulbpwygzwchsnvdeeife.supabase.co/functions/v1/yvp-catalog',
//     headers := jsonb_build_object('content-type', 'application/json',
//       'x-ops-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'ops_cron_secret')),
//     body := '{}'::jsonb);
//   select content from net._http_response order by id desc limit 1;
// Deployed with --no-verify-jwt; the caller proves itself with the Vault's
// ops_cron_secret (public.ops_cron_secret_matches), like ops-alerts.
// The app key (YVP_APP_KEY) is a Supabase secret and never leaves here.
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// YVP_APP_KEY is the name to use; the others catch a secret saved under a
// near-miss name, and the response says which one was found.
const KEY_NAMES = ["YVP_APP_KEY", "YVP_API_KEY", "YOUVERSION_APP_KEY", "YOUVERSION_API_KEY", "YVP_KEY"];
const KEY_NAME = KEY_NAMES.find((name) => Deno.env.get(name)?.trim());
const APP_KEY = KEY_NAME ? Deno.env.get(KEY_NAME)!.trim() : "";
const API = "https://api.youversion.com/v1";
const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

interface Listed {
  id: number | string;
  abbreviation?: string;
  title?: string;
  localized_title?: string;
  language_tag?: string;
}

/** Every Bible in one language, following next_page_token. */
async function list(language: string, allAvailable: boolean): Promise<{ bibles: Listed[]; error?: string }> {
  const bibles: Listed[] = [];
  let token: string | undefined;
  for (let page = 0; page < 20; page++) {
    const url = new URL(`${API}/bibles`);
    url.searchParams.append("language_ranges[]", language);
    if (allAvailable) url.searchParams.set("all_available", "true");
    if (token) url.searchParams.set("page_token", token);
    const response = await fetch(url, { headers: { "X-YVP-App-Key": APP_KEY, Accept: "application/json" } });
    if (!response.ok) {
      const text = await response.text().catch(() => "");
      return { bibles, error: `HTTP ${response.status}: ${text.slice(0, 200)}` };
    }
    const body = await response.json();
    for (const bible of body?.data ?? []) {
      bibles.push({
        id: bible.id,
        abbreviation: bible.abbreviation,
        title: bible.title,
        localized_title: bible.localized_title,
        language_tag: bible.language_tag,
      });
    }
    token = body?.next_page_token ?? undefined;
    if (!token) break;
  }
  return { bibles };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);
  const secret = req.headers.get("x-ops-secret") ?? "";
  const { data: matches, error } = await admin.rpc("ops_cron_secret_matches", { p_secret: secret });
  if (error || matches !== true) return json({ error: "Not allowed." }, 403);
  if (!APP_KEY) {
    // Names only (never values) of the project's own secrets, to spot a typo.
    const similar = Object.keys(Deno.env.toObject())
      .filter((name) => /^[A-Z][A-Z0-9_]*$/.test(name) && !/^(SUPABASE_|SB_|DENO_|PATH$|HOME$|HOSTNAME$)/.test(name))
      .sort();
    return json({ error: "Add the YVP_APP_KEY secret first.", similar }, 400);
  }

  const result: Record<string, unknown> = { keyName: KEY_NAME };
  for (const language of ["en", "es"]) {
    const licensed = await list(language, false);
    const everything = await list(language, true);
    const licensedIDs = new Set(licensed.bibles.map((b) => String(b.id)));
    result[language] = {
      licensed: licensed.bibles,
      licensedError: licensed.error,
      // On the Platform but not (yet) licensed for this app key.
      notLicensed: everything.bibles.filter((b) => !licensedIDs.has(String(b.id))),
      allError: everything.error,
    };
  }
  return json(result);
});
