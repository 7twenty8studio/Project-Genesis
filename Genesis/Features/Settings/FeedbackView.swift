import SwiftUI
import UIKit

/// What someone is telling us about.
enum FeedbackCategory: String, CaseIterable, Identifiable, Sendable {
    case bug, idea, question, scripture, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: String(localized: "Something isn't working")
        case .idea: String(localized: "An idea")
        case .question: String(localized: "A question")
        case .scripture: String(localized: "A mistake in a Bible text")
        case .other: String(localized: "Something else", comment: "Feedback category")
        }
    }

    var systemImage: String {
        switch self {
        case .bug: "ladybug"
        case .idea: "lightbulb"
        case .question: "questionmark.bubble"
        case .scripture: "book"
        case .other: "ellipsis.bubble"
        }
    }
}

/// Settings › Send Feedback: report a problem or share an idea. Saved to
/// public.app_feedback (anyone can send; only the owner can read them).
struct FeedbackView: View {
    @Environment(AuthService.self) private var auth
    @Environment(ReaderViewModel.self) private var reader
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var category: FeedbackCategory = .bug
    @State private var message = ""
    @State private var email = ""
    @State private var includesDetails = true
    @State private var isSending = false
    @State private var sent = false
    @State private var errorMessage: String?

    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            ThemedRows {
                if sent {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(palette.accent)
                            Text("Thank you")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(palette.text)
                            Text("Your message was sent. Every report is read.")
                                .multilineTextAlignment(.center)
                                .foregroundStyle(palette.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("feedback.sent")
                    }
                } else {
                    Section("What's it about?") {
                        Picker("Topic", selection: $category) {
                            ForEach(FeedbackCategory.allCases) { item in
                                Label(item.title, systemImage: item.systemImage).tag(item)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }

                    Section {
                        TextEditor(text: $message)
                            .frame(minHeight: 140)
                            .accessibilityLabel("Message")
                            .accessibilityIdentifier("feedback.message")
                    } header: {
                        Text("Message")
                    } footer: {
                        if category == .scripture {
                            Text("Please include the Bible, book, chapter and verse.")
                        } else {
                            Text("What happened, and what did you expect? Steps to repeat it help a lot.")
                        }
                    }

                    Section {
                        if !auth.isSignedIn {
                            TextField("Email (optional, for a reply)", text: $email)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        Toggle("Include app and device details", isOn: $includesDetails)
                            .tint(palette.accent)
                    } footer: {
                        Text("Details: \(Self.appVersion) · iOS \(UIDevice.current.systemVersion) · \(Self.deviceModel). Nothing else from your device is sent.")
                    }

                    Section {
                        Button {
                            Task { await send() }
                        } label: {
                            HStack {
                                Spacer()
                                if isSending { ProgressView() } else { Text("Send").fontWeight(.semibold) }
                                Spacer()
                            }
                        }
                        .disabled(trimmed.isEmpty || isSending)
                        .accessibilityIdentifier("feedback.send")
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sending

    private struct Row: Encodable {
        let category: String
        let message: String
        let contact_email: String?
        let app_version: String?
        let os_version: String?
        let device: String?
        let language: String
        let context: String?
    }

    private func send() async {
        guard let client = auth.client else {
            errorMessage = String(localized: "Feedback can't be sent from this build. Please try again later.")
            return
        }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let row = Row(
            category: category.rawValue,
            message: String(trimmed.prefix(4000)),
            contact_email: address.isEmpty ? nil : String(address.prefix(320)),
            app_version: includesDetails ? Self.appVersion : nil,
            os_version: includesDetails ? UIDevice.current.systemVersion : nil,
            device: includesDetails ? Self.deviceModel : nil,
            language: AppLanguage.code,
            context: includesDetails ? "\(reader.translation.id) \(reader.chapterID.description(in: "en"))" : nil
        )
        do {
            var token: String?
            if auth.isSignedIn { token = try? await auth.accessToken() }
            let body = try JSONEncoder().encode([row])
            _ = try await client.send("POST", path: "rest/v1/app_feedback", body: body, prefer: "return=minimal", accessToken: token)
            withAnimation { sent = true }
        } catch {
            errorMessage = String(localized: "Your message couldn't be sent. Check your connection and try again.")
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// e.g. "iPhone17,1".
    static var deviceModel: String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
