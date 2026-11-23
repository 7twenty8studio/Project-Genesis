// One room's channel on Supabase Realtime, spoken over a plain WebSocket (the
// Phoenix protocol Realtime uses; no SDK, like the rest of the web app). Public
// broadcast only: nothing is stored, and a message reaches everyone else in
// the room. Reconnects by itself (venue Wi-Fi drops) and rejoins the room.
import { config } from "@/config";
import { parseSignal, topicFor, type Signal } from "./protocol.ts";

type Status = "connecting" | "open" | "closed";

export class Room {
  private socket: WebSocket | null = null;
  private ref = 0;
  private heartbeat: number | undefined;
  private retry: number | undefined;
  private attempts = 0;
  private stopped = false;
  private readonly topic: string;
  status: Status = "connecting";

  constructor(
    room: string,
    private readonly onSignal: (signal: Signal) => void,
    private readonly onStatus: (status: Status) => void = () => {},
  ) {
    this.topic = topicFor(room);
    this.connect();
  }

  send(signal: Signal): boolean {
    if (this.socket?.readyState !== WebSocket.OPEN || this.status !== "open") return false;
    this.push({ event: "broadcast", payload: { type: "broadcast", event: "signal", payload: signal } });
    return true;
  }

  close() {
    this.stopped = true;
    window.clearInterval(this.heartbeat);
    window.clearTimeout(this.retry);
    this.socket?.close();
    this.setStatus("closed");
  }

  private connect() {
    const key = config.supabaseAnonKey;
    const url = `${config.supabaseUrl.replace(/^http/, "ws")}/realtime/v1/websocket?apikey=${encodeURIComponent(key)}&vsn=1.0.0`;
    const socket = new WebSocket(url);
    this.socket = socket;
    this.setStatus("connecting");
    socket.onopen = () => {
      this.push({
        event: "phx_join",
        payload: { config: { broadcast: { self: false, ack: false }, presence: { key: "" }, private: false }, access_token: key },
      });
      window.clearInterval(this.heartbeat);
      this.heartbeat = window.setInterval(() => this.push({ event: "heartbeat", payload: {} }, "phoenix"), 25_000);
    };
    socket.onmessage = (message) => {
      let data: { event?: string; topic?: string; payload?: { status?: string; payload?: unknown; event?: string } };
      try {
        data = JSON.parse(String(message.data));
      } catch {
        return;
      }
      if (data.topic !== this.topic) return;
      if (data.event === "phx_reply" && data.payload?.status === "ok" && this.status !== "open") {
        this.attempts = 0;
        this.setStatus("open");
      } else if (data.event === "broadcast" && data.payload?.event === "signal") {
        const signal = parseSignal(data.payload.payload);
        if (signal) this.onSignal(signal);
      } else if (data.event === "phx_error" || data.event === "phx_close") {
        socket.close();
      }
    };
    socket.onclose = () => {
      window.clearInterval(this.heartbeat);
      if (this.stopped) return;
      this.setStatus("connecting");
      // 0.5 s, 1 s, 2 s… up to 8 s.
      const wait = Math.min(8000, 500 * 2 ** this.attempts++);
      this.retry = window.setTimeout(() => this.connect(), wait);
    };
    socket.onerror = () => socket.close();
  }

  private push(message: { event: string; payload: unknown }, topic = this.topic) {
    this.socket?.send(JSON.stringify({ topic, ...message, ref: String(++this.ref) }));
  }

  private setStatus(status: Status) {
    if (this.status === status) return;
    this.status = status;
    this.onStatus(status);
  }
}

/** Public STUN only: on the venue's network the devices find each other directly. */
export const ICE_SERVERS: RTCIceServer[] = [{ urls: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"] }];

export const newId = () => Math.random().toString(36).slice(2, 10);
