// The sharing side: one device, one stream, a peer connection per viewer (the
// OBS source, and the host page's preview). Viewers ask ("want"); the device
// offers. Announces itself every 2 s so OBS and the host page know it's there.
import { ICE_SERVERS, Room } from "./room.ts";
import type { ShareKind, Signal } from "./protocol.ts";

type Call = { pc: RTCPeerConnection; call: string; pending: RTCIceCandidateInit[] };

export class Sender {
  private readonly room: Room;
  private readonly calls = new Map<string, Call>();
  private stream: MediaStream | null = null;
  private kind: ShareKind | null = null;
  private announce: number;
  name: string;

  constructor(
    roomCode: string,
    readonly device: string,
    name: string,
    private readonly onChange: (state: { status: Room["status"]; viewers: number }) => void,
  ) {
    this.name = name;
    this.room = new Room(roomCode, (signal) => this.handle(signal), () => {
      this.here();
      this.report();
    });
    this.announce = window.setInterval(() => this.here(), 2000);
  }

  /** Starts (or replaces) what this device shares. Viewers reconnect to the new stream by themselves. */
  share(stream: MediaStream, kind: ShareKind) {
    this.stopStream(false);
    this.stream = stream;
    this.kind = kind;
    for (const track of stream.getTracks()) {
      if (track.kind === "video") track.contentHint = kind === "screen" ? "detail" : "motion";
      // Stopping from the browser's own "Stop sharing" bar.
      track.addEventListener("ended", () => {
        if (this.stream === stream && stream.getVideoTracks().every((t) => t.readyState === "ended")) this.stop();
      });
    }
    this.here();
  }

  stop() {
    this.stopStream(true);
    this.here();
  }

  rename(name: string) {
    this.name = name;
    this.here();
  }

  close() {
    window.clearInterval(this.announce);
    this.stopStream(true);
    this.room.close();
  }

  get live() {
    return this.stream !== null;
  }

  private stopStream(sayBye: boolean) {
    for (const [viewer, call] of this.calls) {
      call.pc.close();
      this.calls.delete(viewer);
    }
    this.stream?.getTracks().forEach((track) => track.stop());
    this.stream = null;
    this.kind = null;
    if (sayBye) this.room.send({ t: "bye", device: this.device });
    this.report();
  }

  private here() {
    this.room.send({ t: "here", device: this.device, name: this.name, kind: this.kind, live: this.stream !== null });
  }

  private report() {
    const viewers = [...this.calls.values()].filter((c) => c.pc.connectionState === "connected").length;
    this.onChange({ status: this.room.status, viewers });
  }

  private handle(signal: Signal) {
    if (signal.device !== this.device) return;
    if (signal.t === "want") void this.offer(signal.viewer, signal.call);
    else if (signal.t === "answer") {
      const call = this.calls.get(signal.viewer);
      if (!call || call.call !== signal.call) return;
      void call.pc
        .setRemoteDescription({ type: "answer", sdp: signal.sdp })
        .then(() => Promise.all(call.pending.splice(0).map((c) => call.pc.addIceCandidate(c).catch(() => {}))))
        .catch(() => this.hangUp(signal.viewer));
    } else if (signal.t === "ice" && signal.from === "viewer") {
      const call = this.calls.get(signal.viewer);
      if (!call || call.call !== signal.call) return;
      if (call.pc.remoteDescription) void call.pc.addIceCandidate(signal.candidate).catch(() => {});
      else call.pending.push(signal.candidate);
    } else if (signal.t === "bye" && signal.viewer) this.hangUp(signal.viewer);
  }

  private hangUp(viewer: string) {
    this.calls.get(viewer)?.pc.close();
    this.calls.delete(viewer);
    this.report();
  }

  private async offer(viewer: string, callId: string) {
    const stream = this.stream;
    if (!stream) return;
    this.hangUp(viewer);
    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS });
    const call: Call = { pc, call: callId, pending: [] };
    this.calls.set(viewer, call);
    pc.onicecandidate = (event) => {
      if (event.candidate) this.room.send({ t: "ice", device: this.device, viewer, call: callId, from: "device", candidate: event.candidate.toJSON() });
    };
    pc.onconnectionstatechange = () => {
      if (pc.connectionState === "failed" || pc.connectionState === "closed") this.hangUp(viewer);
      else this.report();
    };
    for (const track of stream.getTracks()) {
      const sender = pc.addTrack(track, stream);
      if (track.kind === "video") void tune(sender, this.kind ?? "screen");
    }
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    if (this.calls.get(viewer) !== call) return;
    this.room.send({ t: "offer", device: this.device, viewer, call: callId, sdp: pc.localDescription?.sdp ?? offer.sdp ?? "" });
  }
}

/** Sharp text for screens (keep the resolution, drop frames if the network must); smooth motion for cameras. */
async function tune(sender: RTCRtpSender, kind: ShareKind) {
  try {
    const params = sender.getParameters();
    if (!params.encodings?.length) params.encodings = [{}];
    params.encodings[0].maxBitrate = kind === "screen" ? 8_000_000 : 6_000_000;
    params.encodings[0].maxFramerate = kind === "screen" ? 60 : 30;
    (params as RTCRtpSendParameters & { degradationPreference?: string }).degradationPreference =
      kind === "screen" ? "maintain-resolution" : "balanced";
    await sender.setParameters(params);
  } catch {
    // Older browsers: their defaults are fine.
  }
}
