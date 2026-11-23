// The watching side (the OBS browser source, or a preview on the host page):
// shows one device. Asks for its stream whenever the device says it's live and
// nothing is playing, so a device that reloads, drops off the Wi-Fi or starts
// sharing again comes back on screen without anyone touching OBS.
import { ICE_SERVERS, newId, Room } from "./room.ts";
import type { Seen, Signal } from "./protocol.ts";

export type ViewerState = { status: Room["status"]; device: Seen | null; playing: boolean };

export class Viewer {
  private readonly room: Room;
  private readonly id = newId();
  private pc: RTCPeerConnection | null = null;
  private call = "";
  private pending: RTCIceCandidateInit[] = [];
  private askedAt = 0;
  private seen: Seen | null = null;
  private playing = false;
  private watchdog: number;

  constructor(
    roomCode: string,
    private readonly device: string,
    private readonly onStream: (stream: MediaStream | null) => void,
    private readonly onState: (state: ViewerState) => void,
  ) {
    this.room = new Room(roomCode, (signal) => this.handle(signal), () => this.report());
    this.watchdog = window.setInterval(() => {
      // Gone quiet: the device closed its page or lost the network.
      if (this.seen && Date.now() - this.seen.at > 8000) {
        this.seen = null;
        this.hangUp();
      }
      this.maybeAsk();
    }, 1000);
  }

  close() {
    window.clearInterval(this.watchdog);
    if (this.pc) this.room.send({ t: "bye", device: this.device, viewer: this.id });
    this.hangUp();
    this.room.close();
  }

  private report() {
    this.onState({ status: this.room.status, device: this.seen, playing: this.playing });
  }

  private hangUp() {
    this.pc?.close();
    this.pc = null;
    this.call = "";
    this.pending = [];
    if (this.playing) {
      this.playing = false;
      this.onStream(null);
    }
    this.report();
  }

  private maybeAsk() {
    if (!this.seen?.live || this.pc || Date.now() - this.askedAt < 3000) return;
    this.askedAt = Date.now();
    this.call = newId();
    this.room.send({ t: "want", device: this.device, viewer: this.id, call: this.call });
  }

  private handle(signal: Signal) {
    if (signal.device !== this.device) return;
    switch (signal.t) {
      case "here": {
        const wasLive = this.seen?.live;
        this.seen = { device: signal.device, name: signal.name, kind: signal.kind, live: signal.live, at: Date.now() };
        if (!signal.live && this.pc) this.hangUp();
        else if (signal.live && !wasLive) this.askedAt = 0;
        this.maybeAsk();
        this.report();
        break;
      }
      case "bye":
        if (!signal.viewer || signal.viewer === this.id) this.hangUp();
        break;
      case "offer":
        if (signal.viewer === this.id && signal.call === this.call) void this.answer(signal.sdp);
        break;
      case "ice":
        if (signal.viewer !== this.id || signal.call !== this.call || signal.from !== "device") break;
        if (this.pc?.remoteDescription) void this.pc.addIceCandidate(signal.candidate).catch(() => {});
        else this.pending.push(signal.candidate);
        break;
    }
  }

  private async answer(sdp: string) {
    this.pc?.close();
    const call = this.call;
    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
    this.pc = pc;
    pc.onicecandidate = (event) => {
      if (event.candidate) this.room.send({ t: "ice", device: this.device, viewer: this.id, call, from: "viewer", candidate: event.candidate.toJSON() });
    };
    pc.ontrack = (event) => {
      this.playing = true;
      this.onStream(event.streams[0] ?? new MediaStream([event.track]));
      this.report();
    };
    let lost: number | undefined;
    pc.onconnectionstatechange = () => {
      if (this.pc !== pc) return;
      window.clearTimeout(lost);
      if (pc.connectionState === "failed" || pc.connectionState === "closed") this.hangUp();
      // A short Wi-Fi blip often recovers by itself; after 4 s, start over.
      else if (pc.connectionState === "disconnected") lost = window.setTimeout(() => this.pc === pc && this.hangUp(), 4000);
    };
    try {
      await pc.setRemoteDescription({ type: "offer", sdp });
      for (const candidate of this.pending.splice(0)) await pc.addIceCandidate(candidate).catch(() => {});
      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      if (this.pc !== pc) return;
      this.room.send({ t: "answer", device: this.device, viewer: this.id, call, sdp: pc.localDescription?.sdp ?? answer.sdp ?? "" });
    } catch {
      if (this.pc === pc) this.hangUp();
    }
  }
}

/** The host page's list: every device in the room, from their announcements. */
export class Watcher {
  private readonly room: Room;
  private readonly seen = new Map<string, Seen>();
  private tick: number;

  constructor(roomCode: string, private readonly onChange: (seen: Map<string, Seen>, status: Room["status"]) => void) {
    this.room = new Room(roomCode, (signal) => {
      if (signal.t === "here") {
        this.seen.set(signal.device, { device: signal.device, name: signal.name, kind: signal.kind, live: signal.live, at: Date.now() });
        this.report();
      } else if (signal.t === "bye" && !signal.viewer) {
        const known = this.seen.get(signal.device);
        if (known) known.live = false;
        this.report();
      }
    }, () => this.report());
    this.tick = window.setInterval(() => this.report(), 2000);
  }

  private report() {
    this.onChange(new Map(this.seen), this.room.status);
  }

  close() {
    window.clearInterval(this.tick);
    this.room.close();
  }
}
