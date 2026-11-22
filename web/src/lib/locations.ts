// A church's Locations and Times (VRS-18, migrations 20261124000000 and
// 20261125000000): where it meets, as separate address lines, and when, as
// gatherings picked from lists (every week on a day, or once on a date, at a
// time). Readers see them in their own language; nothing here is Scripture.
// The same rules as the app's ChurchLocation (PublishedSermon.swift).
import { formatDay, type Lang, type Translate } from "./i18n.ts";

export const WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"] as const;
export type Weekday = (typeof WEEKDAYS)[number];

/** One gathering: every week on `day`, or once on `date` (YYYY-MM-DD), at `time` (HH:MM, the church's own clock). */
export interface Gathering {
  day?: Weekday | null;
  date?: string | null;
  time: string;
  /** A few words of the church's own, such as "Spanish service". */
  note?: string;
}

export interface ChurchLocation {
  name: string;
  street?: string;
  city?: string;
  region?: string;
  postal_code?: string;
  country?: string;
  gatherings?: Gathering[];
  /** The address on one line: worked out by the database from the parts (or typed before there were parts). */
  address: string;
  /** Times typed as text before there were pickers; still shown. */
  times: string;
}

export const LIMITS = { places: 10, gatherings: 20, name: 80, street: 120, city: 80, region: 80, postal_code: 20, country: 80, note: 60 } as const;

const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
const DATE = /^\d{4}-\d{2}-\d{2}$/;

export const isTime = (s: unknown): s is string => typeof s === "string" && TIME.test(s);
export const isDate = (s: unknown): s is string => typeof s === "string" && DATE.test(s) && !Number.isNaN(Date.parse(`${s}T00:00:00Z`));

/** Every quarter hour of the day, for the time menu. */
export function timeOptions(): string[] {
  const out: string[] = [];
  for (let h = 0; h < 24; h++) for (const m of [0, 15, 30, 45]) out.push(`${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`);
  return out;
}

/** "9:00 AM" / "9:00" in the page's language (a clock time, no time zone). */
export function formatTime(time: string, lang: Lang): string {
  if (!isTime(time)) return time;
  const [h, m] = time.split(":").map(Number);
  const locale = lang === "es" ? "es" : lang === "pt" ? "pt-BR" : "en-US";
  return new Intl.DateTimeFormat(locale, { hour: "numeric", minute: "2-digit", timeZone: "UTC" }).format(new Date(Date.UTC(2000, 0, 1, h, m)));
}

/** The address as lines: street; "City, ST 75146"; country. Falls back to the one-line address. */
export function addressLines(place: Pick<ChurchLocation, "street" | "city" | "region" | "postal_code" | "country" | "address">): string[] {
  const trim = (s?: string) => (s ?? "").trim();
  const cityLine = [trim(place.city), [trim(place.region), trim(place.postal_code)].filter(Boolean).join(" ")].filter(Boolean).join(", ");
  const lines = [trim(place.street), cityLine, trim(place.country)].filter(Boolean);
  return lines.length ? lines : trim(place.address) ? [trim(place.address)] : [];
}

/** A maps search for the address that opens on any phone or computer (Google Maps' universal link; the app uses Apple Maps). */
export function mapsLink(place: Parameters<typeof addressLines>[0]): string | null {
  const lines = addressLines(place);
  return lines.length ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(lines.join(", "))}` : null;
}

/** Weekday names for the schedule ("Sundays") and the day menu ("Sunday"), from t() so they're translated. */
export interface DayNames {
  plural: Record<Weekday, string>;
  single: Record<Weekday, string>;
}

export function dayNames(t: Translate): DayNames {
  return {
    plural: { sun: t("Sundays"), mon: t("Mondays"), tue: t("Tuesdays"), wed: t("Wednesdays"), thu: t("Thursdays"), fri: t("Fridays"), sat: t("Saturdays") },
    single: { sun: t("Sunday"), mon: t("Monday"), tue: t("Tuesday"), wed: t("Wednesday"), thu: t("Thursday"), fri: t("Friday"), sat: t("Saturday") },
  };
}

/**
 * The schedule as lines, in order: each weekday once with its times
 * ("Sundays · 9:00 AM, 11:00 AM (Spanish)"), then dates from `today` on
 * (past ones are left out), then any times typed as text.
 */
export function scheduleLines(place: Pick<ChurchLocation, "gatherings" | "times">, lang: Lang, names: DayNames, today: string): string[] {
  const at = (g: Gathering) => formatTime(g.time, lang) + (g.note?.trim() ? ` (${g.note.trim()})` : "");
  const byTime = (a: Gathering, b: Gathering) => a.time.localeCompare(b.time);
  const all = (place.gatherings ?? []).filter((g) => isTime(g.time));
  const lines: string[] = [];
  for (const day of WEEKDAYS) {
    const on = all.filter((g) => g.day === day).sort(byTime);
    if (on.length) lines.push(`${names.plural[day]} · ${on.map(at).join(", ")}`);
  }
  const dates = [...new Set(all.filter((g) => !g.day && isDate(g.date) && g.date! >= today).map((g) => g.date!))].sort();
  for (const date of dates) {
    lines.push(`${formatDay(date, lang)} · ${all.filter((g) => !g.day && g.date === date).sort(byTime).map(at).join(", ")}`);
  }
  for (const line of (place.times ?? "").split("\n")) if (line.trim()) lines.push(line.trim());
  return lines;
}

/** Today as YYYY-MM-DD where the reader is (dates are plain days). */
export function localToday(now = new Date()): string {
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}
