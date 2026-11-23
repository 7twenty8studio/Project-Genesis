// The launch-day screenshare (/screen): a device shares its screen (or, on an
// iPhone or iPad, its camera) peer to peer with WebRTC; OBS shows each device
// through its own browser source (/screen/obs?room=…&device=…). Signalling
// (offers, answers, ICE candidates) goes through a public Supabase Realtime
// broadcast channel named after the room, so nothing is stored and there is no
// table. The video itself never touches a server: on the venue's network it
// goes straight from the device to the Mac running OBS. Pure, Node-tested.

/** Codes people read aloud or type: no 0/O, 1/I/L. */
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export function randomCode(length: number, random: (n: number) => number = cryptoRandom): string {
  let code = "";
  for (let i = 0; i < length; i++) code += ALPHABET[random(ALPHABET.length)];
  return code;
}

function cryptoRandom(n: number): number {
  const value = new Uint32Array(1);
  crypto.getRandomValues(value);
  return value[0] % n;
}

/** Rooms and device ids: letters, digits, - and _, 3 to 40 long. A device id may be a word ("stage-laptop"). */
export function cleanId(value: string | null | undefined): string | null {
  const id = (value ?? "").trim();
  return /^[A-Za-z0-9_-]{3,40}$/.test(id) ? id : null;
}

export function cleanName(value: string | null | undefined): string {
  return (value ?? "").replace(/\s+/g, " ").trim().slice(0, 40);
}

export type ShareKind = "screen" | "camera";

/** Everything sent on the room's channel. `call` ties one viewer's request to its offer, answer and candidates. */
export type Signal =
  | { t: "here"; device: string; name: string; kind: ShareKind | null; live: boolean }
  | { t: "want"; device: string; viewer: string; call: string }
  | { t: "offer"; device: string; viewer: string; call: string; sdp: string }
  | { t: "answer"; device: string; viewer: string; call: string; sdp: string }
  | { t: "ice"; device: string; viewer: string; call: string; from: "device" | "viewer"; candidate: RTCIceCandidateInit }
  | { t: "bye"; device: string; viewer?: string };

const KINDS = new Set(["here", "want", "offer", "answer", "ice", "bye"]);

/** Anything from the channel is checked before use (anyone who knows the room can send). */
export function parseSignal(value: unknown): Signal | null {
  if (!value || typeof value !== "object") return null;
  const s = value as Record<string, unknown>;
  if (typeof s.t !== "string" || !KINDS.has(s.t) || !cleanId(s.device as string)) return null;
  const has = (key: string) => typeof s[key] === "string" && (s[key] as string).length > 0;
  switch (s.t) {
    case "here":
      return {
        t: "here",
        device: s.device as string,
        name: cleanName(s.name as string),
        kind: s.kind === "screen" || s.kind === "camera" ? s.kind : null,
        live: s.live === true,
      };
    case "want":
      return has("viewer") && has("call") ? (s as unknown as Signal) : null;
    case "offer":
    case "answer":
      return has("viewer") && has("call") && has("sdp") ? (s as unknown as Signal) : null;
    case "ice":
      return has("viewer") && has("call") && (s.from === "device" || s.from === "viewer") && s.candidate && typeof s.candidate === "object"
        ? (s as unknown as Signal)
        : null;
    case "bye":
      return s as unknown as Signal;
  }
  return null;
}

export type ObsOptions = { fit?: "contain" | "cover"; background?: "clear" | "black"; audio?: boolean };

/** The address an OBS browser source opens for one device. */
export function obsLink(site: string, room: string, device: string, options: ObsOptions = {}): string {
  const params = new URLSearchParams({ room, device });
  if (options.fit === "cover") params.set("fit", "cover");
  if (options.background === "black") params.set("bg", "black");
  if (options.audio) params.set("audio", "1");
  return `${site.replace(/\/$/, "")}/screen/obs?${params}`;
}

/** The address a device opens to share into the room (optionally with a fixed id for a ready-made OBS source). */
export function shareLink(site: string, room: string, device?: string): string {
  const params = new URLSearchParams({ room });
  if (device) params.set("device", device);
  return `${site.replace(/\/$/, "")}/screen?${params}`;
}

/** The Realtime topic for a room. */
export const topicFor = (room: string) => `realtime:versely-screen-${room}`;

export type Seen = { device: string; name: string; kind: ShareKind | null; live: boolean; at: number };

/** Devices heard from lately, newest first by name; one that has been silent for `staleMs` is gone. */
export function roster(seen: Map<string, Seen>, now: number, staleMs = 8000): Seen[] {
  return [...seen.values()]
    .filter((d) => now - d.at < staleMs)
    .sort((a, b) => (a.name || a.device).localeCompare(b.name || b.device) || a.device.localeCompare(b.device));
}

/** Screen sharing in a browser: desktops yes; iPhone and iPad (every iOS browser is Safari's engine) no. */
export function canShareScreen(nav: { mediaDevices?: { getDisplayMedia?: unknown } } | undefined): boolean {
  return typeof nav?.mediaDevices?.getDisplayMedia === "function";
}
