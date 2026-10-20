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
// USFM code and the KJV's chapter count (as in yvp-bible/lib.ts).
const BOOKS: [string, number][] = [
  ["GEN", 50], ["EXO", 40], ["LEV", 27], ["NUM", 36], ["DEU", 34], ["JOS", 24], ["JDG", 21], ["RUT", 4],
  ["1SA", 31], ["2SA", 24], ["1KI", 22], ["2KI", 25], ["1CH", 29], ["2CH", 36], ["EZR", 10], ["NEH", 13],
  ["EST", 10], ["JOB", 42], ["PSA", 150], ["PRO", 31], ["ECC", 12], ["SNG", 8], ["ISA", 66], ["JER", 52],
  ["LAM", 5], ["EZK", 48], ["DAN", 12], ["HOS", 14], ["JOL", 3], ["AMO", 9], ["OBA", 1], ["JON", 4],
  ["MIC", 7], ["NAM", 3], ["HAB", 3], ["ZEP", 3], ["HAG", 2], ["ZEC", 14], ["MAL", 4],
  ["MAT", 28], ["MRK", 16], ["LUK", 24], ["JHN", 21], ["ACT", 28], ["ROM", 16], ["1CO", 16], ["2CO", 13],
  ["GAL", 6], ["EPH", 6], ["PHP", 4], ["COL", 4], ["1TH", 5], ["2TH", 3], ["1TI", 6], ["2TI", 4],
  ["TIT", 3], ["PHM", 1], ["HEB", 13], ["JAS", 5], ["1PE", 5], ["2PE", 3], ["1JN", 5], ["2JN", 1],
  ["3JN", 1], ["JUD", 1], ["REV", 22],
];
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

  // { action: "sample", path: "/bibles/111/passages/JHN.3?format=html" }:
  // one raw API response, for checking its shape while building.
  const body = await req.json().catch(() => ({}));
  if (body?.action === "sample" && typeof body.path === "string" && body.path.startsWith("/bibles")) {
    const response = await fetch(`${API}${body.path}`, { headers: { "X-YVP-App-Key": APP_KEY, Accept: "application/json" } });
    const text = await response.text();
    return json({ status: response.status, headers: Object.fromEntries(response.headers), body: text.slice(0, 20000) });
  }

  // { action: "wholeBible", bible: 111 }: reads every chapter at the app's
  // pace (two books at a time, four chapters each), to check a whole Bible
  // comes through without hitting the Platform's rate limit.
  if (body?.action === "wholeBible" && Number.isInteger(body.bible)) {
    const started = Date.now();
    let chapters = 0;
    let requests = 0;
    const problems: string[] = [];
    let nextBook = 0;
    const worker = async () => {
      while (nextBook < BOOKS.length && problems.length < 5) {
        const [code, count] = BOOKS[nextBook++];
        let nextChapter = 1;
        await Promise.all(Array.from({ length: 4 }, async () => {
          while (nextChapter <= count && problems.length < 5) {
            const chapter = nextChapter++;
            requests++;
            const response = await fetch(`${API}/bibles/${body.bible}/passages/${code}.${chapter}?format=html&include_headings=true`, {
              headers: { "X-YVP-App-Key": APP_KEY, Accept: "application/json" },
            });
            if (!response.ok) {
              problems.push(`${code} ${chapter}: ${response.status} retry-after ${response.headers.get("retry-after")}`);
              await response.body?.cancel();
              continue;
            }
            const data = await response.json();
            if (typeof data?.content === "string" && data.content.includes("yv-v")) chapters++;
          }
        }));
      }
    };
    await Promise.all([worker(), worker()]);
    return json({ chapters, requests, seconds: (Date.now() - started) / 1000, problems });
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
