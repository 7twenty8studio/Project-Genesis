import CoreMedia
import ReplayKit
import WebRTC

/// Sends the screen to whoever asks: the OBS source (and the host page's or
/// OBS dock's preview). Speaks 7twenty8studio.com's OBS Sharing protocol
/// (7twenty8-studio-web, src/lib/obs-sharing/protocol.ts):
/// announces "here" every 2 s; a viewer sends "want"; we offer; it answers;
/// ICE candidates both ways. All state lives on `queue`.
final class Broadcaster {
    private let queue = DispatchQueue(label: "com.7twenty8studio.versely.mirror")
    private let room: RealtimeRoom
    private let device: String
    private let name: String
    private let factory: RTCPeerConnectionFactory
    private let source: RTCVideoSource
    private let capturer: RTCVideoCapturer
    private let track: RTCVideoTrack
    private var calls: [String: Call] = [:]
    private var order: [String] = []
    private var previews: Set<String> = []
    private var announce: DispatchSourceTimer?
    private var adaptedTo: (Int32, Int32)?
    private var joined = false

    /// Every 2 s while broadcasting: whether the room is reached, and how many viewers (OBS, previews) get the screen.
    var onStatus: ((_ connected: Bool, _ viewers: Int) -> Void)?

    /// Broadcast extensions get about 50 MB: one encoder per viewer, so at most two at once.
    /// OBS always gets in (a preview gives way to it); a preview never pushes anyone out.
    private let maxViewers = 2

    init(room code: String, device: String, name: String) {
        RTCInitializeSSL()
        self.device = device
        self.name = name
        let encoders = RTCDefaultVideoEncoderFactory()
        // The iPhone's hardware H.264 encoder: little memory and battery.
        encoders.preferredCodec = RTCVideoCodecInfo(name: kRTCVideoCodecH264Name)
        factory = RTCPeerConnectionFactory(encoderFactory: encoders, decoderFactory: RTCDefaultVideoDecoderFactory())
        source = factory.videoSource(forScreenCast: true)
        capturer = RTCVideoCapturer(delegate: source)
        track = factory.videoTrack(with: source, trackId: "screen")
        room = RealtimeRoom(room: code, queue: queue)
        room.onSignal = { [weak self] in self?.handle($0) }
        room.onJoined = { [weak self] in
            self?.joined = true
            self?.sayHere()
        }
    }

    func start() {
        queue.async {
            self.room.connect()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 2, repeating: 2)
            timer.setEventHandler { [weak self] in self?.sayHere() }
            timer.resume()
            self.announce = timer
        }
    }

    func stop() {
        queue.sync {
            announce?.cancel()
            announce = nil
            room.send(["t": "bye", "device": device])
            for call in calls.values { call.close() }
            calls.removeAll()
            order.removeAll()
            room.close()
        }
    }

    /// A frame from ReplayKit (any thread).
    func send(_ sampleBuffer: CMSampleBuffer) {
        guard CMSampleBufferIsValid(sampleBuffer), let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = Int32(CVPixelBufferGetWidth(pixels))
        let height = Int32(CVPixelBufferGetHeight(pixels))
        adapt(width: width, height: height)
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: pixels), rotation: rotation(of: sampleBuffer), timeStampNs: Int64(time * 1_000_000_000))
        source.capturer(capturer, didCapture: frame)
    }

    /// At most 1600 pixels tall (or wide), the screen's own shape so nothing is cropped, 30 frames a second.
    private func adapt(width: Int32, height: Int32) {
        if let adaptedTo, adaptedTo == (width, height) { return }
        adaptedTo = (width, height)
        let scale = min(1, 1600 / Double(max(width, height)))
        let even = { (value: Double) in Int32(value / 2) * 2 }
        source.adaptOutputFormat(toWidth: even(Double(width) * scale), height: even(Double(height) * scale), fps: 30)
    }

    private func rotation(of sampleBuffer: CMSampleBuffer) -> RTCVideoRotation {
        guard let value = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
              let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value)
        else { return ._0 }
        switch orientation {
        case .left: return ._90
        case .down: return ._180
        case .right: return ._270
        default: return ._0
        }
    }

    // MARK: - Signals (on queue)

    private func sayHere() {
        room.send(["t": "here", "device": device, "name": name, "kind": "screen", "live": true])
        onStatus?(joined, calls.count)
    }

    private func handle(_ signal: [String: Any]) {
        guard signal["device"] as? String == device, let kind = signal["t"] as? String else { return }
        let viewer = signal["viewer"] as? String
        let callID = signal["call"] as? String
        switch kind {
        case "want":
            if let viewer, let callID { offer(to: viewer, call: callID, preview: signal["role"] as? String == "preview") }
        case "answer":
            guard let viewer, let call = calls[viewer], call.id == callID, let sdp = signal["sdp"] as? String else { return }
            call.accept(answer: sdp)
        case "ice":
            guard let viewer, let call = calls[viewer], call.id == callID, signal["from"] as? String == "viewer",
                  let candidate = signal["candidate"] as? [String: Any], let line = candidate["candidate"] as? String, !line.isEmpty
            else { return }
            let index = (candidate["sdpMLineIndex"] as? NSNumber)?.int32Value ?? 0
            call.add(RTCIceCandidate(sdp: line, sdpMLineIndex: index, sdpMid: candidate["sdpMid"] as? String))
        case "bye":
            if let viewer { hangUp(viewer) }
        default:
            break
        }
    }

    private func hangUp(_ viewer: String) {
        calls.removeValue(forKey: viewer)?.close()
        order.removeAll { $0 == viewer }
        previews.remove(viewer)
    }

    private func offer(to viewer: String, call id: String, preview: Bool) {
        hangUp(viewer)
        while calls.count >= maxViewers {
            if preview { return }
            // Make room for OBS: a preview goes first, then the oldest OBS source.
            guard let out = order.first(where: previews.contains) ?? order.first else { break }
            hangUp(out)
        }
        let call = Call(id: id, viewer: viewer, queue: queue)
        call.onCandidate = { [weak self] candidate in
            guard let self else { return }
            var json: [String: Any] = ["candidate": candidate.sdp, "sdpMLineIndex": candidate.sdpMLineIndex]
            if let mid = candidate.sdpMid { json["sdpMid"] = mid }
            self.room.send(["t": "ice", "device": self.device, "viewer": viewer, "call": id, "from": "device", "candidate": json])
        }
        call.onClosed = { [weak self, weak call] in
            guard let self, let call, self.calls[viewer] === call else { return }
            self.hangUp(viewer)
        }
        guard call.open(factory: factory, track: track) else { return }
        calls[viewer] = call
        order.append(viewer)
        if preview { previews.insert(viewer) }
        call.makeOffer { [weak self] sdp in
            guard let self, self.calls[viewer] === call else { return }
            self.room.send(["t": "offer", "device": self.device, "viewer": viewer, "call": id, "sdp": sdp])
        }
    }
}

/// One viewer's peer connection. WebRTC calls back on its own thread; everything is moved to `queue`.
final class Call: NSObject, RTCPeerConnectionDelegate {
    let id: String
    let viewer: String
    var onCandidate: ((RTCIceCandidate) -> Void)?
    var onClosed: (() -> Void)?

    private let queue: DispatchQueue
    private var connection: RTCPeerConnection?
    private var pending: [RTCIceCandidate] = []
    private var answered = false

    init(id: String, viewer: String, queue: DispatchQueue) {
        self.id = id
        self.viewer = viewer
        self.queue = queue
    }

    func open(factory: RTCPeerConnectionFactory, track: RTCVideoTrack) -> Bool {
        let configuration = RTCConfiguration()
        configuration.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"])]
        configuration.sdpSemantics = .unifiedPlan
        configuration.continualGatheringPolicy = .gatherContinually
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let connection = factory.peerConnection(with: configuration, constraints: constraints, delegate: self) else { return false }
        self.connection = connection
        if let sender = connection.add(track, streamIds: ["screen"]) {
            let parameters = sender.parameters
            if let encoding = parameters.encodings.first {
                encoding.maxBitrateBps = NSNumber(value: 4_000_000)
                encoding.maxFramerate = NSNumber(value: 30)
            }
            // Sharp text: lower the frame rate before the resolution.
            parameters.degradationPreference = NSNumber(value: RTCDegradationPreference.maintainResolution.rawValue)
            sender.parameters = parameters
        }
        return true
    }

    func makeOffer(_ done: @escaping (String) -> Void) {
        guard let connection else { return }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        connection.offer(for: constraints) { [weak self] description, error in
            guard let self, let description, error == nil else { return }
            connection.setLocalDescription(description) { error in
                self.queue.async {
                    guard error == nil, self.connection === connection else { return }
                    done(connection.localDescription?.sdp ?? description.sdp)
                }
            }
        }
    }

    func accept(answer sdp: String) {
        guard let connection, !answered else { return }
        answered = true
        connection.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp)) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                if error != nil {
                    self.onClosed?()
                    return
                }
                for candidate in self.pending { connection.add(candidate) { _ in } }
                self.pending.removeAll()
            }
        }
    }

    /// A candidate from the viewer (on queue). Held until its answer is in.
    func add(_ candidate: RTCIceCandidate) {
        guard let connection else { return }
        if connection.remoteDescription != nil { connection.add(candidate) { _ in } }
        else { pending.append(candidate) }
    }

    func close() {
        connection?.close()
        connection = nil
    }

    // MARK: - RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        queue.async { [weak self] in
            guard let self, self.connection === peerConnection else { return }
            self.onCandidate?(candidate)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        guard newState == .failed || newState == .closed else { return }
        queue.async { [weak self] in
            guard let self, self.connection === peerConnection else { return }
            self.onClosed?()
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
