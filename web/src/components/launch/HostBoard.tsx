"use client";

import QRCode from "qrcode";
import { useCallback, useEffect, useRef, useState } from "react";
import { changeLive, drawNumber, loadBoard, markNoShow, setEntriesOpen, type LiveAction } from "@/app/launch/actions";
import { translator, type Lang } from "@/lib/i18n";
import { drawFromRange, drawSince, findEntries, hostProblem, lastDrawId, poolFor, rollFrames, stopwatch, ticket, timerAt, type Board, type Live, type Purpose } from "@/lib/giveaway";
import { Confetti } from "./Confetti";

type Mode = "volunteer" | "raffle" | "timer" | "offline";
type Shown = { id: number | null; number: number; name: string | null; landed: boolean };

const OFFLINE_KEY = "vs_giveaway_offline";
const reduceMotion = () => typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const typing = (event: KeyboardEvent) => {
  const el = event.target as HTMLElement | null;
  return !!el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable);
};

/**
 * The projector page for launch day: draws volunteers and the final golden
 * ticket (the database picks the number), the game timer, and a draw from
 * paper ticket numbers if the internet is down. Space or Enter does the main
 * thing; N draws again when someone isn't there; 1 and 2 stop the players.
 *
 * Every screen follows the others (20261129000000): a draw made anywhere
 * rolls here too, Clear empties every draw screen, and the timer lives in
 * the database. So the host can run it all from an iPad while the
 * projector's OBS scenes (?scene=...) follow within a second.
 */
export function HostBoard({ lang, initial, entryLink, scene }: { lang: Lang; initial: Board; entryLink: string; scene?: "volunteer" | "raffle" | "timer" }) {
  const t = translator(lang);
  const [board, setBoard] = useState(initial);
  const [mode, setMode] = useState<Mode>(scene ?? "volunteer");
  const inScene = scene !== undefined;
  const [shown, setShown] = useState<Shown | null>(null);
  const [rolling, setRolling] = useState(false);
  const [problem, setProblem] = useState<string | null>(null);
  const [burst, setBurst] = useState(0);
  const [qr, setQr] = useState<string | null>(null);
  const timers = useRef<number[]>([]);

  // The entry QR, for the idle screen.
  useEffect(() => {
    QRCode.toDataURL(entryLink, { errorCorrectionLevel: "M", margin: 2, width: 560, color: { dark: "#2d1d10", light: "#fff9f0" } })
      .then(setQr)
      .catch(() => setQr(null));
  }, [entryLink]);

  // The database's clock minus this screen's: the largest sample wins, since a
  // slow answer can only make it look smaller.
  const offset = useRef<number | null>(null);
  const sampleClock = (serverNow: number | undefined) => {
    if (typeof serverNow !== "number") return;
    const sample = serverNow - Date.now();
    if (offset.current === null || sample > offset.current) offset.current = sample;
  };
  const serverNow = () => Date.now() + (offset.current ?? 0);

  // What this screen has already shown, so only newer draws and clears play here.
  const seen = useRef({ volunteer: lastDrawId(initial, "volunteer"), raffle: lastDrawId(initial, "raffle"), cleared: initial.live?.cleared ?? 0 });
  const [live, setLive] = useState<Live>(initial.live ?? {});

  // New entries, and what the other screens did, about once a second.
  const refresh = useCallback(async () => {
    const result = await loadBoard();
    if (result.ok) {
      sampleClock(result.value.now);
      setBoard(result.value);
      if (result.value.live) setLive(result.value.live);
    }
  }, []);
  useEffect(() => {
    const id = window.setInterval(refresh, 1000);
    return () => window.clearInterval(id);
  }, [refresh]);

  const clearTimers = () => {
    timers.current.forEach((id) => window.clearTimeout(id));
    timers.current = [];
  };

  /** Rolls through `pool` and lands on the winner. */
  const roll = useCallback((pool: number[], winner: Shown) => {
    clearTimers();
    if (reduceMotion() || pool.length < 2) {
      setShown({ ...winner, landed: true });
      setBurst((b) => b + 1);
      setRolling(false);
      return;
    }
    setRolling(true);
    let at = 0;
    for (const frame of rollFrames(pool, winner.number)) {
      const { number } = frame;
      const last = number === winner.number && frame.ms === 0;
      timers.current.push(
        window.setTimeout(() => {
          setShown(last ? { ...winner, landed: true } : { id: null, number, name: null, landed: false });
          if (last) {
            setRolling(false);
            setBurst((b) => b + 1);
          }
        }, at),
      );
      at += frame.ms;
    }
  }, []);

  // A draw or a clear made on another screen.
  useEffect(() => {
    if (rolling) return;
    const cleared = board.live?.cleared ?? 0;
    if (cleared > seen.current.cleared) {
      seen.current.cleared = cleared;
      clearTimers();
      setShown(null);
    }
    if (mode !== "volunteer" && mode !== "raffle") return;
    const next = drawSince(board, mode, seen.current[mode]);
    if (!next) return;
    seen.current[mode] = next.id;
    roll([...poolFor(board, mode), next.number], { id: next.id, number: next.number, name: next.name, landed: true });
  }, [board, mode, rolling, roll]);

  /** Clear on every draw screen. */
  const clearShown = useCallback(async () => {
    clearTimers();
    setRolling(false);
    setShown(null);
    const result = await changeLive("clear");
    if (result.ok && typeof result.value.cleared === "number") seen.current.cleared = Math.max(seen.current.cleared, result.value.cleared);
  }, []);

  const draw = useCallback(
    async (purpose: Purpose) => {
      if (rolling) return;
      setProblem(null);
      const pool = poolFor(board, purpose);
      const result = await drawNumber(purpose);
      if (!result.ok) {
        setProblem(t(hostProblem(result.code)));
        return;
      }
      seen.current[purpose] = Math.max(seen.current[purpose], result.value.id);
      roll(pool.length ? pool : [result.value.number], { id: result.value.id, number: result.value.number, name: result.value.name, landed: true });
      void refresh();
    },
    [board, rolling, roll, refresh, t],
  );

  const notHere = useCallback(async () => {
    if (!shown?.landed || shown.id === null || rolling || (mode !== "volunteer" && mode !== "raffle")) return;
    await markNoShow(shown.id);
    await draw(mode);
  }, [shown, rolling, mode, draw]);

  // Without the internet: numbers from the paper tickets, remembered on this computer.
  // Read once on this computer (the offline panel isn't shown until chosen, so nothing differs from the server's render).
  const saved = useState(() => {
    try {
      const value = typeof window === "undefined" ? null : JSON.parse(window.localStorage.getItem(OFFLINE_KEY) ?? "null");
      return {
        last: Number.isInteger(value?.last) ? (value.last as number) : 100,
        drawn: Array.isArray(value?.drawn) ? (value.drawn as unknown[]).filter((n): n is number => Number.isInteger(n)) : [],
      };
    } catch {
      return { last: 100, drawn: [] as number[] }; // private window: start fresh
    }
  })[0];
  const [lastTicket, setLastTicket] = useState(saved.last);
  const [offlineDrawn, setOfflineDrawn] = useState<number[]>(saved.drawn);
  const offlineDraw = useCallback(() => {
    if (rolling) return;
    const number = drawFromRange(lastTicket, offlineDrawn);
    if (number === null) {
      setProblem(t(hostProblem("nobody_left")));
      return;
    }
    setProblem(null);
    const drawn = [...offlineDrawn, number];
    setOfflineDrawn(drawn);
    try {
      window.localStorage.setItem(OFFLINE_KEY, JSON.stringify({ last: lastTicket, drawn }));
    } catch {
      /* not kept: fine for one evening */
    }
    const pool = Array.from({ length: lastTicket }, (_, i) => i + 1);
    roll(pool, { id: null, number, name: null, landed: true });
  }, [rolling, lastTicket, offlineDrawn, roll, t]);

  // The game timer: two players, head to head or one at a time. Its state is
  // the database's (giveaway_live), so the iPad and the projector agree.
  const [players, setPlayers] = useState(() => [initial.live?.names?.[0] || t("Player 1"), initial.live?.names?.[1] || t("Player 2")]);
  // Names typed on another screen (not while typing one here).
  const typingName = useRef(false);
  useEffect(() => {
    if (typingName.current || !live.names) return;
    setPlayers((p) => p.map((v, i) => live.names?.[i] || v));
  }, [live.names]);
  const [together, setTogether] = useState(true);
  const [now, setNow] = useState(initial.now ?? 0); // the database's time, moved on each frame while it matters
  const clock = timerAt(live.timer, now);
  const { count } = clock;
  const ticking = count !== null || clock.running.some(Boolean);
  useEffect(() => {
    let frame = 0;
    const tick = () => {
      setNow(serverNow());
      if (ticking) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [ticking, live]);

  const timerStep = useCallback(
    async (action: LiveAction, lane: number | null = null) => {
      const result = await changeLive(action, lane, together, action === "timer_names" ? players : null);
      if (!result.ok) {
        setProblem(t(hostProblem(result.code)));
        return;
      }
      setProblem(null);
      sampleClock(result.value.now);
      setLive({ cleared: result.value.cleared, timer: result.value.timer, names: result.value.names });
    },
    [together, players, t],
  );
  const startTimer = useCallback(() => void timerStep("timer_start"), [timerStep]);
  const stopLane = useCallback((lane: number) => void timerStep("timer_stop", lane), [timerStep]);
  const resetTimer = useCallback(() => void timerStep("timer_reset"), [timerStep]);

  // Confetti once both players have finished, on every screen.
  const bothDone = clock.done[0] && clock.done[1];
  const celebrated = useRef(bothDone);
  useEffect(() => {
    if (bothDone && !celebrated.current) setBurst((b) => b + 1);
    celebrated.current = bothDone;
  }, [bothDone]);

  const [lookup, setLookup] = useState("");
  const matches = findEntries(board.entries, lookup);

  const best = bothDone ? (clock.elapsed[0] <= clock.elapsed[1] ? 0 : 1) : null;

  // Keys, so the co-host can run it from the laptop without aiming.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (typing(event) || event.metaKey || event.ctrlKey || event.altKey) return;
      const key = event.key.toLowerCase();
      if (key === " " || key === "enter") {
        event.preventDefault();
        if (mode === "timer") startTimer();
        else if (mode === "offline") offlineDraw();
        else void draw(mode);
      } else if (key === "n") void notHere();
      else if (key === "1" && mode === "timer") stopLane(0);
      else if (key === "2" && mode === "timer") stopLane(1);
      else if (key === "r") {
        if (mode === "timer") resetTimer();
        else if (mode === "offline") setShown(null);
        else void clearShown();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [mode, draw, notHere, offlineDraw, startTimer, stopLane, resetTimer, clearShown]);

  const switchMode = (next: Mode) => {
    clearTimers();
    setRolling(false);
    setShown(null);
    setProblem(null);
    setMode(next);
  };

  const toggleOpen = async () => {
    const result = await setEntriesOpen(!board.open);
    if (result.ok) setBoard((b) => ({ ...b, open: result.value }));
    else setProblem(t(hostProblem(result.code)));
  };

  const fullScreen = () => {
    if (document.fullscreenElement) void document.exitFullscreen();
    else void document.documentElement.requestFullscreen?.();
  };

  const tab = (value: Mode, label: string) => (
    <button
      type="button"
      onClick={() => switchMode(value)}
      aria-pressed={mode === value}
      className={`rounded-full px-4 py-2 text-sm font-medium transition-colors ${mode === value ? "bg-[#f9ebd7] text-[#3a240f]" : "text-[#e0b48d] hover:bg-white/10"}`}
    >
      {label}
    </button>
  );

  const heading =
    mode === "volunteer" ? t("Who's coming up?") : mode === "raffle" ? t("The final golden ticket") : mode === "offline" ? t("Drawing from paper tickets") : t("Ready, set, go");
  const winnerLine =
    shown?.landed && shown.name
      ? mode === "raffle"
        ? t("Wins a free year of Versely Premium!")
        : t("Come on up!")
      : null;

  return (
    <div
      className={`relative flex min-h-screen flex-col ${inScene && mode === "timer" ? "text-[#f9ebd7] [--ticket-notch:#2b1b0e]" : "stage"}`}
    >
      <Confetti burst={burst} />
      <header className={`${inScene ? "hidden" : "flex"} flex-wrap items-center justify-between gap-3 px-6 pt-5 opacity-60 transition-opacity duration-200 hover:opacity-100 focus-within:opacity-100`}>
        <nav className="flex flex-wrap gap-1" aria-label={t("Giveaway")}>
          {tab("volunteer", t("Draw a volunteer"))}
          {tab("raffle", t("Final golden ticket"))}
          {tab("timer", t("Game timer"))}
          {tab("offline", t("Without internet"))}
        </nav>
        <div className="flex flex-wrap items-center gap-3 text-sm text-[#e0b48d]">
          <div className="relative">
            <input
              type="search"
              value={lookup}
              onChange={(e) => setLookup(e.target.value)}
              placeholder={t("Find a number")}
              aria-label={t("Find a number by first name")}
              className="w-44 rounded-full border border-[#e0b48d]/40 bg-transparent px-3 py-1.5 text-[#f9ebd7] placeholder:text-[#e0b48d]/70 outline-none focus:border-[#e0b48d]"
            />
            {lookup.trim() ? (
              <ul className="absolute right-0 top-full z-10 mt-2 w-64 rounded-2xl bg-[#2d1d10] p-2 text-left text-base shadow-xl" aria-live="polite">
                {matches.length ? (
                  matches.map((entry) => (
                    <li key={entry.number} className="flex justify-between gap-3 rounded-xl px-3 py-1.5">
                      <span className="truncate text-[#f9ebd7]">{entry.name}</span>
                      <span className="tabular-nums">{ticket(entry.number)}</span>
                    </li>
                  ))
                ) : (
                  <li className="px-3 py-1.5">{t("No one by that name")}</li>
                )}
              </ul>
            ) : null}
          </div>
          <span data-testid="entry-count">{t("{count} entered", { count: board.entries.length })}</span>
          <button type="button" onClick={toggleOpen} className="rounded-full border border-[#e0b48d]/40 px-3 py-1.5 hover:bg-white/10">
            {board.open ? t("Close entries") : t("Open entries")}
          </button>
          <button type="button" onClick={fullScreen} className="rounded-full border border-[#e0b48d]/40 px-3 py-1.5 hover:bg-white/10">
            {t("Full screen")}
          </button>
        </div>
      </header>

      <main className="flex flex-1 flex-col items-center justify-center px-6 pb-10 text-center">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/brand/logo-cream.svg" alt="Versely" width={180} height={45} className={`mb-6 h-10 w-auto ${inScene && mode === "timer" ? "hidden" : ""}`} />
        <h1 className={`text-5xl font-semibold tracking-tight md:text-6xl ${inScene && mode === "timer" ? "sr-only" : ""}`}>{heading}</h1>

        {mode === "timer" ? (
          <div className={`w-full max-w-5xl ${inScene ? "" : "mt-10"}`}>
            {count !== null ? (
              <p key={count} className="rise-in text-[10rem] font-semibold leading-none tabular-nums text-[#e0b48d]" aria-live="assertive">
                {count}
              </p>
            ) : null}
            <div className={`grid grid-cols-2 gap-6 ${count !== null ? "hidden" : ""}`}>
              {[0, 1].map((lane) => {
                const ms = clock.elapsed[lane];
                return (
                  <div key={lane} className={`rounded-3xl p-6 ${best === lane ? "golden-ticket rise-in" : inScene ? "bg-[#2d1d10]/90" : "bg-white/5"}`}>
                    <input
                      value={players[lane]}
                      onChange={(e) => setPlayers((p) => p.map((v, i) => (i === lane ? e.target.value : v)))}
                      onFocus={() => (typingName.current = true)}
                      onBlur={() => {
                        typingName.current = false;
                        void timerStep("timer_names");
                      }}
                      aria-label={t("Player name")}
                      className="w-full bg-transparent text-center text-2xl font-semibold outline-none"
                    />
                    <p className="mt-3 text-7xl font-semibold tabular-nums">{stopwatch(ms)}</p>
                    <p className="mt-3 h-7 text-lg font-semibold">{best === lane ? t("Winner") : null}</p>
                    <button
                      type="button"
                      onClick={() => stopLane(lane)}
                      disabled={!clock.running[lane]}
                      className={`mt-3 rounded-full border border-current/30 px-5 py-2 text-sm disabled:opacity-30 ${inScene ? "hidden" : ""}`}
                    >
                      {t("Stop (key {key})", { key: lane + 1 })}
                    </button>
                  </div>
                );
              })}
            </div>
            <div className={`mt-8 flex-wrap items-center justify-center gap-3 text-sm text-[#e0b48d] ${inScene ? "hidden" : "flex"}`}>
              <button type="button" onClick={startTimer} className="rounded-full bg-[#f9ebd7] px-6 py-2.5 font-semibold text-[#3a240f]">
                {t("Start (Space)")}
              </button>
              <button type="button" onClick={resetTimer} className="rounded-full border border-[#e0b48d]/40 px-5 py-2.5">
                {t("Reset (R)")}
              </button>
              <label className="ml-2 inline-flex items-center gap-2">
                <input type="checkbox" checked={together} onChange={(e) => setTogether(e.target.checked)} className="h-4 w-4" />
                {t("Both play at once")}
              </label>
            </div>
          </div>
        ) : (
          <div className="mt-10 flex w-full max-w-4xl flex-col items-center">
            {shown ? (
              <div className={`golden-ticket w-full max-w-2xl rounded-[2rem] px-10 py-12 ${shown.landed ? "rise-in" : ""}`} aria-live="polite">
                {shown.landed ? <span className="sheen" aria-hidden="true" /> : null}
                <p className="text-sm font-semibold uppercase tracking-[0.3em]">{mode === "raffle" ? t("Golden ticket") : t("Number")}</p>
                {shown.landed && shown.name ? (
                  <>
                    <p className="rise-in mt-3 break-words text-7xl font-semibold leading-none tracking-tight md:text-8xl" data-testid="drawn-name">
                      {shown.name}
                    </p>
                    <p className="mt-4 text-5xl font-semibold tabular-nums tracking-tight" data-testid="drawn-number">
                      {ticket(shown.number)}
                    </p>
                  </>
                ) : (
                  <p className="mt-2 text-[9rem] font-semibold leading-none tabular-nums tracking-tight" data-testid="drawn-number">
                    {ticket(shown.number)}
                  </p>
                )}
                <p className="mt-5 min-h-10 text-3xl font-semibold">{winnerLine}</p>
              </div>
            ) : (
              <div className="flex flex-col items-center gap-6 md:flex-row md:gap-12">
                {qr && mode !== "offline" ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={qr} alt="" width={280} height={280} className="h-56 w-56 rounded-3xl md:h-72 md:w-72" />
                ) : null}
                <div className="max-w-md text-left">
                  {mode === "offline" ? (
                    <label className="block text-xl">
                      {t("Last paper ticket number")}
                      <input
                        type="number"
                        min={1}
                        max={9999}
                        value={lastTicket}
                        onChange={(e) => setLastTicket(Math.max(1, Math.min(9999, Number(e.target.value) || 1)))}
                        className="mt-3 block w-40 rounded-2xl bg-white/10 px-4 py-3 text-3xl font-semibold tabular-nums outline-none"
                      />
                    </label>
                  ) : (
                    <>
                      <p className="text-3xl font-semibold">{t("Not entered yet?")}</p>
                      <p className="mt-3 text-xl text-[#e0b48d]">{t("Scan the code to enter. It's free.")}</p>
                    </>
                  )}
                </div>
              </div>
            )}

            {problem ? (
              <p role="alert" className="mt-6 rounded-2xl bg-white/10 px-5 py-3 text-lg">
                {problem}
              </p>
            ) : null}

            <div className={`mt-10 flex-wrap items-center justify-center gap-3 text-sm ${inScene ? "hidden" : "flex"}`}>
              <button
                type="button"
                disabled={rolling}
                onClick={() => (mode === "offline" ? offlineDraw() : void draw(mode as Purpose))}
                className="rounded-full bg-[#f9ebd7] px-8 py-3 text-lg font-semibold text-[#3a240f] disabled:opacity-50"
              >
                {shown ? t("Draw another (Space)") : t("Draw (Space)")}
              </button>
              {shown?.landed && shown.id !== null ? (
                <button type="button" disabled={rolling} onClick={() => void notHere()} className="rounded-full border border-[#e0b48d]/40 px-5 py-3 text-[#e0b48d]">
                  {t("Not here? Draw again (N)")}
                </button>
              ) : null}
              {shown ? (
                <button type="button" onClick={() => (mode === "offline" ? setShown(null) : void clearShown())} className="rounded-full border border-[#e0b48d]/40 px-5 py-3 text-[#e0b48d]">
                  {t("Clear (R)")}
                </button>
              ) : null}
            </div>
            {mode === "offline" && offlineDrawn.length ? (
              <p className="mt-6 text-sm text-[#e0b48d]">
                {t("Drawn so far: {numbers}", { numbers: offlineDrawn.map(ticket).join(", ") })}{" "}
                <button
                  type="button"
                  className="underline"
                  onClick={() => {
                    setOfflineDrawn([]);
                    try {
                      window.localStorage.removeItem(OFFLINE_KEY);
                    } catch {
                      /* nothing kept */
                    }
                  }}
                >
                  {t("Start over")}
                </button>
              </p>
            ) : null}
          </div>
        )}
      </main>
    </div>
  );
}
