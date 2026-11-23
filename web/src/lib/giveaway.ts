// translatable returns
// The launch-day giveaway (supabase/migrations/20261127000000_launch_giveaway.sql):
// the pure parts of the entry page and the host page, tested in giveaway.test.ts.
// The database checks everything again; these only spare a round trip.

export type BoardEntry = { number: number; name: string };
export type BoardDraw = { id: number; number: number; name: string; purpose: Purpose; no_show: boolean };
/** The race timer as the database keeps it (20261129000000): each lane's go time (epoch ms) and its result (ms). */
export type LiveTimer = { started: (number | null)[]; finished: (number | null)[] };
/** What every screen shares: the last "clear" (epoch ms), the timer and the players' names. */
export type Live = { cleared?: number; timer?: LiveTimer; names?: string[] };
/** `live` and `now` (the database's clock, epoch ms) come from 20261129000000. */
export type Board = { name: string; open: boolean; entries: BoardEntry[]; draws: BoardDraw[]; live?: Live; now?: number };
export type Purpose = "volunteer" | "raffle";

/** "#007": entry numbers are shown with three digits, as on the paper tickets. */
export function ticket(number: number): string {
  return `#${String(number).padStart(3, "0")}`;
}

export function tidyName(name: string): string {
  return name.replace(/\s+/g, " ").trim();
}

export function tidyEmail(email: string): string {
  return email.trim().toLowerCase();
}

/** The same rule as giveaway_enter: something@something.something, no spaces. */
export function looksLikeEmail(email: string): boolean {
  const e = tidyEmail(email);
  return e.length <= 254 && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e);
}

/** The English message for a refusal (the page translates it). */
export function entryProblem(code: string): string {
  switch (code) {
    case "closed":
      return "Entries are closed.";
    case "invalid_name":
      return "Add your first name.";
    case "invalid_email":
      return "Check your email address.";
    case "full":
      return "The giveaway is full.";
    default:
      return "That didn't go through. Check your connection and try again.";
  }
}

/** The English message for a refusal on the host page. */
export function hostProblem(code: string): string {
  switch (code) {
    case "not_allowed":
      return "This account can't run the giveaway.";
    case "nobody_left":
      return "Everyone has been drawn already.";
    case "not_signed_in":
      return "Sign in again to keep going.";
    default:
      return "That didn't go through. Check your connection and try again.";
  }
}

/**
 * The numbers the roll shows before it lands, and how long each stays:
 * quick at first, slowing to a stop on `winner` (strong ease-out), about
 * `seconds` long. `pool` is every number that could be drawn; `random` is
 * injectable for tests.
 */
export function rollFrames(pool: number[], winner: number, seconds = 4, random: () => number = Math.random): { number: number; ms: number }[] {
  const others = pool.filter((n) => n !== winner);
  const steps = 26;
  const weights = Array.from({ length: steps }, (_, i) => 1 + Math.pow(i / (steps - 1), 3) * 14);
  const total = weights.reduce((a, b) => a + b, 0);
  const frames: { number: number; ms: number }[] = [];
  let last = -1;
  for (let i = 0; i < steps - 1; i++) {
    let n = winner;
    if (others.length > 0) {
      n = others[Math.floor(random() * others.length)];
      if (n === last && others.length > 1) n = others[(others.indexOf(n) + 1) % others.length];
    }
    last = n;
    frames.push({ number: n, ms: Math.round((weights[i] / total) * seconds * 1000) });
  }
  frames.push({ number: winner, ms: 0 });
  return frames;
}

/** Without the internet: a number from 1 to `last` not yet drawn, or null when none is left. */
export function drawFromRange(last: number, drawn: number[], random: () => number = Math.random): number | null {
  const taken = new Set(drawn);
  const left: number[] = [];
  for (let n = 1; n <= last; n++) if (!taken.has(n)) left.push(n);
  return left.length ? left[Math.floor(random() * left.length)] : null;
}

/** "1:07.3": minutes, seconds and tenths, for the game timer. */
export function stopwatch(ms: number): string {
  const tenths = Math.max(0, Math.floor(ms / 100));
  const minutes = Math.floor(tenths / 600);
  const seconds = Math.floor((tenths % 600) / 10);
  return `${minutes}:${String(seconds).padStart(2, "0")}.${tenths % 10}`;
}

/** Numbers that can still be drawn for `purpose` (not drawn for it before, no-shows included). */
export function poolFor(board: Board, purpose: Purpose): number[] {
  const drawn = new Set(board.draws.filter((d) => d.purpose === purpose).map((d) => d.number));
  return board.entries.map((e) => e.number).filter((n) => !drawn.has(n));
}

const fold = (s: string) => s.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().trim();

/** The host's "find a number" box: entries whose first name starts with what was typed (accents aside), or the number itself. */
export function findEntries(entries: BoardEntry[], query: string, limit = 8): BoardEntry[] {
  const q = fold(query).replace(/^#/, "");
  if (!q) return [];
  if (/^\d+$/.test(q)) return entries.filter((e) => e.number === Number(q)).slice(0, limit);
  return entries.filter((e) => fold(e.name).split(" ").some((word) => word.startsWith(q)) || fold(e.name).startsWith(q)).slice(0, limit);
}

/** The newest draw id for `purpose` (0 when none), so a screen only rolls draws made after it opened. */
export function lastDrawId(board: Board, purpose: Purpose): number {
  return board.draws.reduce((id, d) => (d.purpose === purpose && d.id > id ? d.id : id), 0);
}

/** A draw for `purpose` newer than `after`, made on another screen (the newest, if several), or null. */
export function drawSince(board: Board, purpose: Purpose, after: number): BoardDraw | null {
  let found: BoardDraw | null = null;
  for (const d of board.draws) if (d.purpose === purpose && d.id > after && (!found || d.id > found.id)) found = d;
  return found;
}

/**
 * The shared timer on this screen at the database's time `serverNow`:
 * the 3-2-1 still to show (or null), and each lane's time so far (or its
 * result once stopped). A lane that hasn't started reads 0.
 */
export function timerAt(timer: LiveTimer | undefined, serverNow: number): { count: number | null; elapsed: number[]; running: boolean[]; done: boolean[] } {
  const started = [0, 1].map((i) => timer?.started?.[i] ?? null);
  const finished = [0, 1].map((i) => timer?.finished?.[i] ?? null);
  const waiting = started.filter((go): go is number => go !== null && go > serverNow);
  const count = waiting.length ? Math.min(3, Math.max(1, Math.ceil((Math.min(...waiting) - serverNow) / 1000))) : null;
  const elapsed = [0, 1].map((i) => finished[i] ?? (started[i] !== null && started[i]! <= serverNow ? serverNow - started[i]! : 0));
  const running = [0, 1].map((i) => finished[i] === null && started[i] !== null && started[i]! <= serverNow);
  const done = [0, 1].map((i) => finished[i] !== null);
  return { count, elapsed, running, done };
}
