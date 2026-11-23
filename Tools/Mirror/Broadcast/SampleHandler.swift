import ReplayKit
import WebRTC

/// The broadcast extension: iOS hands it every frame of the screen while the
/// broadcast runs (in any app); it sends them to OBS with WebRTC, the same way
/// the website's /screen page does, so OBS shows this iPhone through
/// /screen/obs?room=…&device=…
final class SampleHandler: RPBroadcastSampleHandler {
    private var broadcaster: Broadcaster?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let broadcaster = Broadcaster(room: Mirror.room, device: Mirror.deviceID, name: "iPhone \(Mirror.deviceID.suffix(4))")
        self.broadcaster = broadcaster
        broadcaster.start()
    }

    override func broadcastPaused() {}
    override func broadcastResumed() {}

    override func broadcastFinished() {
        broadcaster?.stop()
        broadcaster = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        broadcaster?.send(sampleBuffer)
    }
}
