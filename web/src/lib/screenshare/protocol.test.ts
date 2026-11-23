import { test } from "node:test";
import assert from "node:assert/strict";
import { canShareScreen, cleanId, obsLink, parseSignal, randomCode, roster, shareLink, type Seen } from "./protocol.ts";

test("codes avoid look-alike characters", () => {
  let i = 0;
  const code = randomCode(40, (n) => i++ % n);
  assert.equal(code.length, 40);
  assert.doesNotMatch(code, /[01OIL]/);
});

test("ids are short, plain and safe in a link", () => {
  assert.equal(cleanId("stage-laptop"), "stage-laptop");
  assert.equal(cleanId(" K7Q2 "), "K7Q2");
  assert.equal(cleanId("ab"), null);
  assert.equal(cleanId("a b c"), null);
  assert.equal(cleanId("<script>"), null);
  assert.equal(cleanId(undefined), null);
});

test("signals from the channel are checked", () => {
  assert.deepEqual(parseSignal({ t: "here", device: "K7Q2", name: "  Pastor's   laptop ", kind: "screen", live: true }), {
    t: "here",
    device: "K7Q2",
    name: "Pastor's laptop",
    kind: "screen",
    live: true,
  });
  assert.equal(parseSignal({ t: "here", device: "x", live: true }), null);
  assert.equal(parseSignal({ t: "offer", device: "K7Q2", viewer: "V1", call: "C1" }), null);
  assert.equal(parseSignal({ t: "ice", device: "K7Q2", viewer: "V1", call: "C1", from: "nobody", candidate: {} }), null);
  assert.ok(parseSignal({ t: "ice", device: "K7Q2", viewer: "V1", call: "C1", from: "device", candidate: { candidate: "x" } }));
  assert.equal(parseSignal({ t: "steal", device: "K7Q2" }), null);
  assert.equal(parseSignal("here"), null);
});

test("links for OBS and for sharing", () => {
  assert.equal(obsLink("https://v.example/", "ROOM1234", "K7Q2"), "https://v.example/screen/obs?room=ROOM1234&device=K7Q2");
  assert.equal(
    obsLink("https://v.example", "ROOM1234", "K7Q2", { fit: "cover", background: "black", audio: true }),
    "https://v.example/screen/obs?room=ROOM1234&device=K7Q2&fit=cover&bg=black&audio=1",
  );
  assert.equal(shareLink("https://v.example", "ROOM1234"), "https://v.example/screen?room=ROOM1234");
  assert.equal(shareLink("https://v.example", "ROOM1234", "stage-laptop"), "https://v.example/screen?room=ROOM1234&device=stage-laptop");
});

test("the roster drops devices that went quiet", () => {
  const seen = new Map<string, Seen>([
    ["B", { device: "B", name: "Zed", kind: "screen", live: true, at: 9_000 }],
    ["A", { device: "A", name: "Amy", kind: null, live: false, at: 9_500 }],
    ["C", { device: "C", name: "Old", kind: "camera", live: true, at: 1_000 }],
  ]);
  assert.deepEqual(roster(seen, 10_000).map((d) => d.device), ["A", "B"]);
});

test("iPhones can't share their screen from a web page", () => {
  assert.equal(canShareScreen({ mediaDevices: { getDisplayMedia: () => null } }), true);
  assert.equal(canShareScreen({ mediaDevices: {} }), false);
  assert.equal(canShareScreen(undefined), false);
});
