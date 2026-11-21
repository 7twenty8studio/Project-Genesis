// Universal Links (VRS-18): sermon links open Versely when it's installed.
// Served as JSON from the exact host links use; the Team ID comes from
// VERSELY_APPLE_TEAM_ID (Vercel), the app's Associated Domains entitlement
// lists applinks:versely.7twenty8studio.com (checkpoint 3).
import { config } from "@/config";

export const dynamic = "force-static";

export function GET() {
  const appID = config.appleTeamId ? `${config.appleTeamId}.${config.appBundleId}` : null;
  const body = {
    applinks: {
      details: appID ? [{ appIDs: [appID], components: [{ "/": "/s/*", comment: "Church sermons" }] }] : [],
    },
  };
  return Response.json(body, { headers: { "Cache-Control": "public, max-age=3600" } });
}
