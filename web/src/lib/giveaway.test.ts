import { test } from "node:test";
import assert from "node:assert/strict";
import { drawFromRange, looksLikeEmail, poolFor, rollFrames, stopwatch, ticket, tidyEmail, tidyName, type Board } from "./giveaway.ts";

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
