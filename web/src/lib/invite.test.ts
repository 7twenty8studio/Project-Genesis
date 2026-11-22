import { test } from "node:test";
import assert from "node:assert/strict";
import { formatInviteCode } from "./invite.ts";

test("invite codes read in two halves, as in the app", () => {
  assert.equal(formatInviteCode("ABCDEFGHJK"), "ABCDE-FGHJK");
  assert.equal(formatInviteCode("SHORT"), "SHORT");
});
