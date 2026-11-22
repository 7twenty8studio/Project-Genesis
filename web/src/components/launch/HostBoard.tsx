"use client";

import QRCode from "qrcode";
import { useCallback, useEffect, useRef, useState } from "react";
import { drawNumber, loadBoard, markNoShow, setEntriesOpen } from "@/app/launch/actions";
import { translator, type Lang } from "@/lib/i18n";
import { drawFromRange, findEntries, hostProblem, poolFor, rollFrames, stopwatch, ticket, type Board, type Purpose } from "@/lib/giveaway";
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
 */
export function HostBoard({ lang, initial, entryLink }: { lang: Lang; initial: Board; entryLink: string }) {
  const t = translator(lang);
  const [board, setBoard] = useState(initial);
  const [mode, setMode] = useState<Mode>("volunteer");
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

  // New entries keep arriving until the draw.
  const refresh = useCallback(async () => {
    const result = await loadBoard();
    if (result.ok) setBoard(result.value);
  }, []);
  useEffect(() => {
    const id = window.setInterval(refresh, 5000);
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

  // The game timer: two players, head to head or one at a time.
  const [players, setPlayers] = useState([t("Player 1"), t("Player 2")]);
  const [together, setTogether] = useState(true);
  const [count, setCount] = useState<number | null>(null);
  const [startedAt, setStartedAt] = useState<(number | null)[]>([null, null]);
  const [finished, setFinished] = useState<(number | null)[]>([null, null]);
  const [now, setNow] = useState(0);
  useEffect(() => {
    if (!startedAt.some((s, i) => s !== null && finished[i] === null)) return;
    let frame = 0;
    const tick = () => {
      setNow(performance.now());
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [startedAt, finished]);

  const startTimer = useCallback(() => {
    if (count !== null) return;
    const lanes = together ? [0, 1].filter((i) => finished[i] === null && startedAt[i] === null) : [[0, 1].find((i) => finished[i] === null && startedAt[i] === null)].filter((i): i is number => i !== undefined);
    if (!lanes.length) return;
    clearTimers();
    setCount(3);
    timers.current.push(window.setTimeout(() => setCount(2), 1000));
    timers.current.push(window.setTimeout(() => setCount(1), 2000));
    timers.current.push(
      window.setTimeout(() => {
        const at = performance.now();
        setCount(null);
        setNow(at);
        setStartedAt((s) => s.map((v, i) => (lanes.includes(i) ? at : v)));
      }, 3000),
    );
  }, [count, together, finished, startedAt]);

  const stopLane = useCallback(
    (lane: number) => {
      const begun = startedAt[lane];
      if (begun === null || finished[lane] !== null) return;
      const time = performance.now() - begun;
      setFinished((f) => f.map((v, i) => (i === lane ? time : v)));
      if (finished[1 - lane] !== null) setBurst((b) => b + 1);
    },
    [startedAt, finished],
  );

  const resetTimer = useCallback(() => {
    clearTimers();
    setCount(null);
    setStartedAt([null, null]);
    setFinished([null, null]);
  }, []);

  const [lookup, setLookup] = useState("");
  const matches = findEntries(board.entries, lookup);

  const best = finished[0] !== null && finished[1] !== null ? (finished[0] <= finished[1] ? 0 : 1) : null;

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
        else setShown(null);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [mode, draw, notHere, offlineDraw, startTimer, stopLane, resetTimer]);

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
    <div className="stage relative flex min-h-screen flex-col">
      <Confetti burst={burst} />
      <header className="flex flex-wrap items-center justify-between gap-3 px-6 pt-5 opacity-60 transition-opacity duration-200 hover:opacity-100 focus-within:opacity-100">
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
        <img src="/brand/logo-cream.svg" alt="Versely" width={180} height={45} className="mb-6 h-10 w-auto" />
        <h1 className="text-5xl font-semibold tracking-tight md:text-6xl">{heading}</h1>

        {mode === "timer" ? (
          <div className="mt-10 w-full max-w-5xl">
            {count !== null ? (
              <p key={count} className="rise-in text-[10rem] font-semibold leading-none tabular-nums text-[#e0b48d]" aria-live="assertive">
                {count}
              </p>
            ) : null}
            <div className={`grid grid-cols-2 gap-6 ${count !== null ? "hidden" : ""}`}>
              {[0, 1].map((lane) => {
                const begun = startedAt[lane];
                const done = finished[lane];
                const ms = done ?? (begun !== null ? now - begun : 0);
                return (
                  <div key={lane} className={`rounded-3xl p-6 ${best === lane ? "golden-ticket rise-in" : "bg-white/5"}`}>
                    <input
                      value={players[lane]}
                      onChange={(e) => setPlayers((p) => p.map((v, i) => (i === lane ? e.target.value : v)))}
                      aria-label={t("Player name")}
                      className="w-full bg-transparent text-center text-2xl font-semibold outline-none"
                    />
                    <p className="mt-3 text-7xl font-semibold tabular-nums">{stopwatch(ms)}</p>
                    <p className="mt-3 h-7 text-lg font-semibold">{best === lane ? t("Winner") : null}</p>
                    <button
                      type="button"
                      onClick={() => stopLane(lane)}
                      disabled={begun === null || done !== null}
                      className="mt-3 rounded-full border border-current/30 px-5 py-2 text-sm disabled:opacity-30"
                    >
                      {t("Stop (key {key})", { key: lane + 1 })}
                    </button>
                  </div>
                );
              })}
            </div>
            <div className="mt-8 flex flex-wrap items-center justify-center gap-3 text-sm text-[#e0b48d]">
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

            <div className="mt-10 flex flex-wrap items-center justify-center gap-3 text-sm">
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
                <button type="button" onClick={() => setShown(null)} className="rounded-full border border-[#e0b48d]/40 px-5 py-3 text-[#e0b48d]">
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
