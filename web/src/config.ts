/**
 * Versely web (versely.7twenty8studio.com): Church Studio and the guest sermon
 * page (VRS-18). These are the Versely Supabase project's PUBLIC values, the
 * same ones the app ships with; every check happens in the database
 * (20261120000000_church_sermons.sql), so nothing secret lives here.
 */
export const config = {
  supabaseUrl: process.env.NEXT_PUBLIC_VERSELY_SUPABASE_URL ?? "https://ulbpwygzwchsnvdeeife.supabase.co",
  supabaseAnonKey:
    process.env.NEXT_PUBLIC_VERSELY_SUPABASE_ANON_KEY ??
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsYnB3eWd6d2Noc252ZGVlaWZlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA2MjY3MjAsImV4cCI6MjEwNjIwMjcyMH0.LieY3BPC1MHQZ8qzO06oulde048Pv5x9GsVVPYrUMUE",
  /** The one address links and QR codes use (Universal Links need the exact host). */
  siteUrl: process.env.NEXT_PUBLIC_VERSELY_SITE_URL ?? "https://versely.7twenty8studio.com",
  /** Apple Team ID for apple-app-site-association (public: it's in that file; Config/Signing.xcconfig's DEVELOPMENT_TEAM). */
  appleTeamId: process.env.VERSELY_APPLE_TEAM_ID ?? "4XTR53RY2V",
  appBundleId: "com.7twenty8studio.versely",
  /** App Store id for Safari's Smart App Banner, once Versely is listed. "" leaves it out. */
  appStoreId: process.env.NEXT_PUBLIC_VERSELY_APP_STORE_ID ?? "",
  /** Sign in with Apple on the web needs an Apple Services ID (APPLE_SETUP.md); "on" once it's set up. */
  /** A published link sermon shown as "View a sample sermon" on the home page; "" hides the button. */
  sampleSermon: process.env.NEXT_PUBLIC_VERSELY_SAMPLE_SERMON ?? "6audf2zagi",
  appleWebSignIn: process.env.NEXT_PUBLIC_VERSELY_APPLE_WEB === "on",
  /** The launch-day giveaway behind /launch (giveaway_events.slug, 20261127000000). */
  giveawayEvent: process.env.NEXT_PUBLIC_VERSELY_GIVEAWAY ?? "launch-2026",
};
