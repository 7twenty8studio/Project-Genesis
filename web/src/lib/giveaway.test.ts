import { test } from "node:test";
import assert from "node:assert/strict";
import { drawFromRange, drawSince, findEntries, lastDrawId, looksLikeEmail, poolFor, rollFrames, stopwatch, ticket, tidyEmail, tidyName, timerAt, type Board } from "./giveaway.ts";

test("numbers read like the paper tickets", () => {
  assert.equal(ticket(7), "#007");
  assert.equal(ticket(47), "#047");
  assert.equal(ticket(1234), "#1234");
});

test("names and emails are tidied the way the database does", () => {
  assert.equal(tidyName("  Ana   Maria "), "Ana Maria");
  assert.equal(tidyEmail(" Ana@Example.COM "), "ana@example.com");
  assert.ok(looksLikeEmail("ana@example.com"));
  assert.ok(!looksLikeEmail("ana@example"));
  assert.ok(!looksLikeEmail("ana example.com"));
});

test("the roll slows down and lands on the winner", () => {
  let seed = 1;
  const random = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const frames = rollFrames([1, 2, 3, 4, 5], 3, 4, random);
  assert.equal(frames.at(-1)?.number, 3);
  assert.ok(frames[0].ms < frames.at(-2)!.ms, "later frames stay longer");
  const total = frames.reduce((a, f) => a + f.ms, 0);
  assert.ok(total > 3500 && total <= 4000, `about four seconds (${total})`);
  for (let i = 1; i < frames.length - 1; i++) assert.notEqual(frames[i].number, frames[i - 1].number);
});

test("a roll with one entry still lands", () => {
  const frames = rollFrames([9], 9);
  assert.ok(frames.every((f) => f.number === 9));
});

test("the offline draw never repeats and says when nobody is left", () => {
  assert.equal(drawFromRange(3, [1, 2], () => 0), 3);
  assert.equal(drawFromRange(2, [1, 2]), null);
  assert.equal(drawFromRange(0, []), null);
});

test("the pool leaves out numbers already drawn for the same purpose only", () => {
  const board: Board = {
    name: "x",
    open: true,
    entries: [1, 2, 3].map((number) => ({ number, name: `P${number}` })),
    draws: [
      { id: 1, number: 2, name: "P2", purpose: "volunteer", no_show: false },
      { id: 2, number: 3, name: "P3", purpose: "raffle", no_show: true },
    ],
  };
  assert.deepEqual(poolFor(board, "volunteer"), [1, 3]);
  assert.deepEqual(poolFor(board, "raffle"), [1, 2]);
});

test("the timer shows minutes, seconds and tenths", () => {
  assert.equal(stopwatch(0), "0:00.0");
  assert.equal(stopwatch(67_340), "1:07.3");
  assert.equal(stopwatch(-5), "0:00.0");
});

test("the host finds a forgotten number by first name or number", () => {
  const entries = [
    { number: 1, name: "Ana María" },
    { number: 2, name: "Ben" },
    { number: 3, name: "Mariana" },
    { number: 12, name: "José" },
  ];
  assert.deepEqual(findEntries(entries, "maria").map((e) => e.number), [1, 3]);
  assert.deepEqual(findEntries(entries, "jose").map((e) => e.number), [12]);
  assert.deepEqual(findEntries(entries, "#012").map((e) => e.number), [12]);
  assert.deepEqual(findEntries(entries, "  "), []);
  assert.deepEqual(findEntries(entries, "zed"), []);
});

test("a screen rolls only draws made after it opened, the newest first", () => {
  const board: Board = {
    name: "x", open: true, entries: [{ number: 1, name: "Ana" }, { number: 2, name: "Ben" }, { number: 3, name: "Cy" }],
    draws: [
      { id: 4, number: 1, name: "Ana", purpose: "volunteer", no_show: false },
      { id: 5, number: 2, name: "Ben", purpose: "raffle", no_show: false },
    ],
  };
  assert.equal(lastDrawId(board, "volunteer"), 4);
  assert.equal(lastDrawId(board, "raffle"), 5);
  assert.equal(lastDrawId({ ...board, draws: [] }, "raffle"), 0);
  assert.equal(drawSince(board, "volunteer", 4), null);
  const later: Board = { ...board, draws: [...board.draws, { id: 6, number: 2, name: "Ben", purpose: "volunteer", no_show: true }, { id: 7, number: 3, name: "Cy", purpose: "volunteer", no_show: false }] };
  assert.equal(drawSince(later, "volunteer", 4)?.id, 7, "a no-show and its redraw arrive together: show the redraw");
  assert.equal(drawSince(later, "raffle", 5), null);
});

test("the shared timer counts down, runs and stops on the database's clock", () => {
  assert.deepEqual(timerAt(undefined, 1000), { count: null, elapsed: [0, 0], running: [false, false], done: [false, false] });
  const timer = { started: [10_000, 10_000], finished: [null, null] };
  assert.equal(timerAt(timer, 7_000).count, 3);
  assert.equal(timerAt(timer, 8_500).count, 2);
  assert.equal(timerAt(timer, 9_999).count, 1);
  assert.deepEqual(timerAt(timer, 9_000).elapsed, [0, 0]);
  const running = timerAt(timer, 12_345);
  assert.equal(running.count, null);
  assert.deepEqual(running.elapsed, [2_345, 2_345]);
  assert.deepEqual(running.running, [true, true]);
  const stopped = timerAt({ started: [10_000, 10_000], finished: [4_200, null] }, 20_000);
  assert.deepEqual(stopped.elapsed, [4_200, 10_000]);
  assert.deepEqual(stopped.done, [true, false]);
  const oneAtATime = timerAt({ started: [10_000, null], finished: [null, null] }, 11_000);
  assert.deepEqual(oneAtATime.running, [true, false]);
});
