import { test } from "node:test";
import assert from "node:assert/strict";
import { translator } from "./i18n.ts";
import { addressLines, dayNames, formatTime, mapsLink, scheduleLines, timeOptions } from "./locations.ts";

const place = {
  name: "Main Campus",
  street: "2827 Saint Martin Dr.",
  city: "Lancaster",
  region: "TX",
  postal_code: "75146",
  country: "United States",
  address: "2827 Saint Martin Dr., Lancaster, TX 75146, United States",
  times: "",
  gatherings: [
    { day: "sun" as const, time: "11:00" },
    { day: "wed" as const, time: "19:00", note: "Bible study" },
    { day: "sun" as const, time: "09:00" },
    { date: "2026-11-26", time: "18:00", note: "Thanksgiving" },
    { date: "2026-11-01", time: "18:00" },
  ],
};

test("the address reads as lines, and as one line for directions", () => {
  assert.deepEqual(addressLines(place), ["2827 Saint Martin Dr.", "Lancaster, TX 75146", "United States"]);
  assert.equal(mapsLink(place), "https://www.google.com/maps/search/?api=1&query=2827%20Saint%20Martin%20Dr.%2C%20Lancaster%2C%20TX%2075146%2C%20United%20States");
  // Typed on one line before there were parts.
  assert.deepEqual(addressLines({ address: "1 Hill Rd, Austin" }), ["1 Hill Rd, Austin"]);
  assert.deepEqual(addressLines({ address: "", city: "Lancaster", postal_code: "75146" }), ["Lancaster, 75146"]);
  assert.equal(mapsLink({ address: "" }), null);
});

test("weekly times are grouped by day in week order, then future dates; past dates are left out", () => {
  const en = scheduleLines(place, "en", dayNames(translator("en")), "2026-11-22");
  assert.deepEqual(en, ["Sundays · 9:00 AM, 11:00 AM", "Wednesdays · 7:00 PM (Bible study)", "Thursday, November 26, 2026 · 6:00 PM (Thanksgiving)"]);
  const pt = scheduleLines(place, "pt", dayNames(translator("pt")), "2026-11-27");
  assert.deepEqual(pt, ["Domingos · 9:00, 11:00", "Quartas-feiras · 19:00 (Bible study)"]);
});

test("times typed as text before the pickers still show", () => {
  assert.deepEqual(scheduleLines({ times: "Sundays 10 AM\n\n Youth Fridays " }, "en", dayNames(translator("en")), "2026-11-22"), ["Sundays 10 AM", "Youth Fridays"]);
});

test("the time menu has every quarter hour, shown in the page's language", () => {
  const all = timeOptions();
  assert.equal(all.length, 96);
  assert.equal(all[0], "00:00");
  assert.equal(all.at(-1), "23:45");
  assert.equal(formatTime("13:30", "en"), "1:30 PM");
  assert.equal(formatTime("13:30", "pt"), "13:30");
});
