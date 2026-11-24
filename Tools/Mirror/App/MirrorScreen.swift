import SwiftUI

/// The app's one screen: status and the big Start button, this iPhone's ID
/// and name, the room, and OBS links. The broadcast itself runs in the
/// extension (SampleHandler), so it keeps going while any other app is open.
struct MirrorScreen: View {
    @AppStorage("seenGuide") private var seenGuide = false
    @State private var showGuide = false
    @State private var launcher = BroadcastLauncher()
    @State private var status: Mirror.Status?
    @State private var roomDraft = Mirror.room
    @State private var room = Mirror.room
    @State private var name = Mirror.name
    @State private var copied: String?
    @FocusState private var editing: Bool

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusCard
                    phoneCard
                    roomCard
                    obsCard
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("7Twenty8 Mirror")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showGuide = true } label: { Image(systemName: "questionmark.circle") }
                        .accessibilityLabel("How it works")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editing = false }
                }
            }
            .background(HiddenPicker(launcher: launcher).frame(width: 1, height: 1))
        }
        .tint(Studio.copper)
        .sheet(isPresented: $showGuide) { GuideView() }
        .onAppear {
            if !seenGuide {
                seenGuide = true
                showGuide = true
            }
            status = Mirror.readStatus()
        }
        .onReceive(tick) { _ in status = Mirror.readStatus() }
    }

    // MARK: Status and Start

    private var statusCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Circle().fill(dotColor).frame(width: 12, height: 12)
                Text(statusText).font(.headline)
                Spacer()
            }
            Text(statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                editing = false
                launcher.open()
            } label: {
                Label(status == nil ? "Start Broadcast" : "Stop Broadcast", systemImage: status == nil ? "record.circle" : "stop.circle")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            .buttonStyle(.borderedProminent)
            .tint(status == nil ? Studio.live : Studio.ink)
            .clipShape(Capsule())
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var dotColor: Color {
        guard let status else { return .gray }
        if status.viewers > 0 { return Studio.live }
        return status.connected ? .green : .orange
    }

    private var statusText: String {
        guard let status else { return "Not broadcasting" }
        if status.viewers > 0 { return "Live in OBS" }
        return status.connected ? "Broadcasting" : "Connecting…"
    }

    private var statusDetail: String {
        guard let status else {
            return "Tap Start Broadcast, then Start Broadcast again in the sheet. Then open the app you want to show."
        }
        if status.viewers > 0 {
            return status.viewers == 1 ? "1 screen is showing this iPhone. Switch to any app: it stays live." : "\(status.viewers) screens are showing this iPhone (OBS and a preview)."
        }
        return status.connected ? "In room \(room). Waiting for OBS to show this iPhone." : "Reaching room \(room). Check this iPhone is online."
    }

    // MARK: This iPhone

    private var phoneCard: some View {
        Card(title: "This iPhone") {
            Text(Mirror.deviceID)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
            Text("Its ID in OBS. It stays the same until the app is deleted.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Name shown to the host", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($editing)
                .submitLabel(.done)
                .onChange(of: name) { _, value in Mirror.name = value }
            Text("Name shown on the host page and the OBS dock.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Room

    private var roomValid: Bool { Mirror.cleanRoom(roomDraft) != nil }

    private var roomCard: some View {
        Card(title: "Room") {
            HStack {
                TextField("Room code", text: $roomDraft)
                    .font(.system(.title3, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .focused($editing)
                    .submitLabel(.done)
                    .onSubmit(saveRoom)
                Button {
                    if let text = UIPasteboard.general.string { roomDraft = text }
                } label: { Image(systemName: "doc.on.clipboard") }
                    .accessibilityLabel("Paste")
            }
            if roomDraft != room {
                HStack {
                    Button("Use This Room", action: saveRoom)
                        .buttonStyle(.borderedProminent)
                        .tint(Studio.ink)
                        .disabled(!roomValid)
                    Button("Cancel") { roomDraft = room }
                }
                if !roomValid {
                    Text("3 to 40 letters, numbers or dashes.")
                        .font(.footnote)
                        .foregroundStyle(Studio.live)
                }
            } else {
                Text(status == nil
                     ? "Get the code from whoever runs OBS (the host page shows it)."
                     : "A new room takes effect the next time you start a broadcast.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if room != Mirror.defaultRoom && roomDraft == room {
                Button("Back to the Launch Show Room") {
                    roomDraft = Mirror.defaultRoom
                    saveRoom()
                }
                .font(.footnote)
            }
        }
    }

    private func saveRoom() {
        guard let code = Mirror.cleanRoom(roomDraft) else { return }
        Mirror.room = code
        room = code
        roomDraft = code
        editing = false
    }

    // MARK: OBS

    private var obsCard: some View {
        Card(title: "OBS") {
            Text("Add a Browser source in OBS with this link, 500 × 1080, so the screen fills it edge to edge.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(Mirror.obsLink(room: room))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button(copied == "obs" ? "Copied" : "Copy OBS Link") { copy(Mirror.obsLink(room: room), "obs") }
                    .buttonStyle(.bordered)
                ShareLink(item: URL(string: Mirror.obsLink(room: room))!) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Share OBS link")
            }
            Divider()
            Link(destination: URL(string: Mirror.hostLink(room: room))!) {
                Label("Open the Host Page", systemImage: "safari")
            }
            Button(copied == "dock" ? "Copied" : "Copy OBS Dock Link") { copy(Mirror.dockLink(room: room), "dock") }
                .font(.subheadline)
            Text("The dock goes in OBS under Docks › Custom Browser Docks and lists every device in the room.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func copy(_ text: String, _ key: String) {
        UIPasteboard.general.string = text
        copied = key
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copied == key { copied = nil }
        }
    }
}
