import Foundation

/// One room's channel on Supabase Realtime (public broadcast, nothing stored),
/// over a plain WebSocket, as the website's lib/screenshare/room.ts does.
/// Reconnects by itself. Everything runs on `queue`.
final class RealtimeRoom: NSObject, URLSessionWebSocketDelegate {
    var onSignal: (([String: Any]) -> Void)?
    var onJoined: (() -> Void)?

    private let queue: DispatchQueue
    private let topic: String
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var heartbeat: DispatchSourceTimer?
    private var ref = 0
    private var joined = false
    private var stopped = false

    init(room: String, queue: DispatchQueue) {
        self.queue = queue
        self.topic = "realtime:versely-screen-\(room)"
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect() {
        guard !stopped else { return }
        var components = URLComponents(string: Mirror.supabaseURL.replacingOccurrences(of: "https://", with: "wss://") + "/realtime/v1/websocket")!
        components.queryItems = [URLQueryItem(name: "apikey", value: Mirror.anonKey), URLQueryItem(name: "vsn", value: "1.0.0")]
        let task = session.webSocketTask(with: components.url!)
        self.task = task
        joined = false
        task.resume()
        receive(task)
    }

    func close() {
        stopped = true
        heartbeat?.cancel()
        heartbeat = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session.invalidateAndCancel()
    }

    /// Sends a signal to everyone else in the room (false before the room is joined).
    @discardableResult
    func send(_ signal: [String: Any]) -> Bool {
        guard joined else { return false }
        push(event: "broadcast", payload: ["type": "broadcast", "event": "signal", "payload": signal])
        return true
    }

    // MARK: - Socket

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        queue.async {
            guard webSocketTask === self.task else { return }
            self.push(event: "phx_join", payload: [
                "config": ["broadcast": ["self": false, "ack": false], "presence": ["key": ""], "private": false],
                "access_token": Mirror.anonKey,
            ])
            self.startHeartbeat()
        }
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard task === self.task else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message { self.handle(text) }
                    self.receive(task)
                case .failure:
                    self.reconnect(after: task)
                }
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["topic"] as? String == topic
        else { return }
        let event = message["event"] as? String
        let payload = message["payload"] as? [String: Any]
        if event == "phx_reply", payload?["status"] as? String == "ok", !joined {
            joined = true
            onJoined?()
        } else if event == "broadcast", payload?["event"] as? String == "signal", let signal = payload?["payload"] as? [String: Any] {
            onSignal?(signal)
        } else if event == "phx_error" || event == "phx_close" {
            if let task { reconnect(after: task) }
        }
    }

    private func reconnect(after failed: URLSessionWebSocketTask) {
        guard failed === task, !stopped else { return }
        failed.cancel(with: .goingAway, reason: nil)
        task = nil
        joined = false
        heartbeat?.cancel()
        heartbeat = nil
        queue.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.connect() }
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 25, repeating: 25)
        timer.setEventHandler { [weak self] in self?.push(event: "heartbeat", payload: [:], topic: "phoenix") }
        timer.resume()
        heartbeat = timer
    }

    private func push(event: String, payload: [String: Any], topic: String? = nil) {
        ref += 1
        let message: [String: Any] = ["topic": topic ?? self.topic, "event": event, "payload": payload, "ref": String(ref)]
        guard let data = try? JSONSerialization.data(withJSONObject: message), let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }
}
