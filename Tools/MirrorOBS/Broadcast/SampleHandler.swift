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
            stop(saying: "Open Mirror OBS and type your room code first.")
            return
        }
        guard Mirror.canBroadcast() else {
            stop(saying: "Your free trial has ended. Open Mirror OBS to unlock it.")
            return
        }
        let broadcaster = Broadcaster(room: room, device: Mirror.deviceID, name: Mirror.name)
        broadcaster.onStatus = { connected, viewers in Mirror.writeStatus(connected: connected, viewers: viewers) }
        self.broadcaster = broadcaster
        Mirror.writeStatus(connected: false, viewers: 0)
        broadcaster.start()
    }

    private func stop(saying reason: String) {
        finishBroadcastWithError(NSError(domain: "MirrorOBS", code: 1, userInfo: [NSLocalizedDescriptionKey: reason]))
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
