import ReplayKit
import WebRTC

/// The broadcast extension: iOS hands it every frame of the screen while the
/// broadcast runs (in any app); it sends them to OBS with WebRTC, the same way
/// OBS Sharing's web pages do, so OBS shows this iPhone through
/// /services/obs-sharing/obs?room=…&device=… on 7twenty8studio.com
final class SampleHandler: RPBroadcastSampleHandler {
    private var broadcaster: Broadcaster?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard let room = Mirror.room else {
            let reason = "Open Mirror and type your room code first."
            finishBroadcastWithError(NSError(domain: "Mirror", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]))
            return
        }
        let broadcaster = Broadcaster(room: room, device: Mirror.deviceID, name: Mirror.name)
        broadcaster.onStatus = { connected, viewers in Mirror.writeStatus(connected: connected, viewers: viewers) }
        self.broadcaster = broadcaster
        Mirror.writeStatus(connected: false, viewers: 0)
        broadcaster.start()
    }

    override func broadcastPaused() {}
    override func broadcastResumed() {}

    override func broadcastFinished() {
        broadcaster?.stop()
        broadcaster = nil
        Mirror.clearStatus()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        broadcaster?.send(sampleBuffer)
    }
}
