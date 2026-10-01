import SwiftUI

/// The prayer wall or reflections: newest first, "I prayed" / "Amen",
/// comments, and report or block on everything.
struct CommunityFeedView: View {
    let kind: CommunityPostKind

    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette
    @State private var model: CommunityFeedModel?
    @State private var composing = false
    @State private var showsGuidelines = false
    /// Open the composer once the guidelines sheet has gone.
    @State private var composeAfterGuidelines = false

    var body: some View {
        Group {
            if let model {
                list(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: kind) {
            let model = CommunityFeedModel(kind: kind, store: community)
            self.model = model
            await model.refresh()
        }
        .sheet(isPresented: $composing) {
            if let model { CommunityComposeView(model: model) }
        }
        .sheet(isPresented: $showsGuidelines, onDismiss: {
            if composeAfterGuidelines {
                composeAfterGuidelines = false
                composing = true
            }
        }) {
            CommunityGuidelinesView { composeAfterGuidelines = true }
        }
    }

    private func list(_ model: CommunityFeedModel) -> some View {
        List {
            Section {
                Button {
                    if community.profile?.hasAcceptedTerms == true { composing = true } else { showsGuidelines = true }
                } label: {
                    Label(kind == .prayer ? "Share a Prayer Request" : "Share a Reflection", systemImage: kind == .prayer ? "hands.and.sparkles" : "text.quote")
                }
                .accessibilityIdentifier("community.compose")
            } footer: {
                Text(kind == .prayer
                    ? "Everyone signed in to Genesis can see and pray for these."
                    : "Short thoughts on a passage. Everyone signed in to Genesis can see these.")
            }
            .listRowBackground(palette.surface)

            if let error = model.errorMessage {
                Text(error).font(.footnote).foregroundStyle(.orange).listRowBackground(Color.clear)
            }
            if model.visiblePosts.isEmpty, !model.isLoading {
                QuietEmptyState(
                    systemImage: kind.reactionSymbol,
                    title: kind == .prayer ? "No prayer requests yet" : "No reflections yet",
                    message: kind == .prayer ? "Be the first to share a request." : "Share what you're reading."
                )
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(model.visiblePosts) { post in
                    CommunityPostRow(post: post, model: model)
                        .onAppear {
                            if post.id == model.visiblePosts.last?.id { Task { await model.loadMore() } }
                        }
                }
            }
            .listRowBackground(palette.surface)
        }
        .refreshable { await model.refresh() }
    }
}

struct CommunityPostRow: View {
    let post: CommunityPost
    let model: CommunityFeedModel
    var showsComments = true

    @Environment(CommunityStore.self) private var community
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette

    var body: some View {
        let reacted = model.reacted.contains(post.id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(post.displayName).font(.subheadline.weight(.semibold))
                Text(post.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                if post.hiddenAt != nil {
                    Text("Under review").font(.caption2).foregroundStyle(.orange)
                }
            }
            if let reference = post.reference {
                Button {
                    router.read(reference)
                } label: {
                    Label(reference.description, systemImage: "book")
                        .font(.footnote.weight(.semibold))
                }
                .accessibilityHint("Opens the passage in the reader")
            }
            Text(post.body)
                .foregroundStyle(palette.text)
                .accessibilityIdentifier("community.body")
            HStack(spacing: 18) {
                Button {
                    Task { await model.toggleReaction(post) }
                } label: {
                    Label(
                        post.reactionCount > 0 ? "\(post.kind.reactionTitle) · \(post.reactionCount)" : post.kind.reactionTitle,
                        systemImage: reacted ? post.kind.reactionSymbol + ".fill" : post.kind.reactionSymbol
                    )
                }
                .accessibilityIdentifier("community.react")
                if showsComments {
                    Button {
                        router.togetherPath.append(.post(post))
                    } label: {
                        Label(post.commentCount > 0 ? "\(post.commentCount)" : "Comment", systemImage: "bubble.left")
                    }
                    .accessibilityIdentifier("community.comments")
                }
            }
            .font(.subheadline)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
        .contentActions(
            .communityPost, id: post.id, authorName: post.displayName, isMine: post.isMine,
            canRemove: post.isMine,
            onRemove: { await model.remove(post) },
            onBlock: { _ = await community.blockAuthor(ofPost: post.id) },
            onHidden: { model.hide(post.id) }
        )
    }
}

/// Write a prayer request or a reflection.
struct CommunityComposeView: View {
    let model: CommunityFeedModel

    @Environment(\.dismiss) private var dismiss
    @Environment(ReaderViewModel.self) private var reader
    @State private var draft: CommunityDraft
    @State private var referenceText = ""
    @State private var isSending = false

    init(model: CommunityFeedModel) {
        self.model = model
        _draft = State(initialValue: CommunityDraft(kind: model.kind))
    }

    private var reference: PassageReference? {
        ReferenceParser.parse(referenceText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(draft.kind == .prayer ? "What can people pray for?" : "What did you notice?", text: $draft.body, axis: .vertical)
                        .lineLimit(4...10)
                        .accessibilityIdentifier("community.text")
                } footer: {
                    Text("\(draft.body.count)/1500")
                }
                Section {
                    TextField("Passage (optional), e.g. Psalm 23", text: $referenceText)
                        .autocorrectionDisabled()
                    if !referenceText.isEmpty {
                        Text(reference?.description ?? "Not a passage Genesis recognises")
                            .font(.footnote)
                            .foregroundStyle(reference == nil ? .orange : .secondary)
                    }
                    if draft.kind == .prayer {
                        Toggle("Post anonymously", isOn: $draft.isAnonymous)
                    }
                } footer: {
                    Text("Scripture is shown from your Bible in the reader; posts link to the passage rather than quoting it.")
                }
                if let error = model.errorMessage {
                    Section { Text(error).foregroundStyle(.orange) }
                }
            }
            .navigationTitle(draft.kind == .prayer ? "Prayer Request" : "Reflection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post", systemImage: "paperplane", action: post)
                        .disabled(!canPost || isSending)
                        .accessibilityIdentifier("community.post.send")
                }
            }
        }
    }

    private var canPost: Bool {
        let text = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.count <= 1500 && (referenceText.isEmpty || reference != nil)
    }

    private func post() {
        var draft = draft
        if let reference {
            // Verse 0 stands for the whole chapter.
            let chapter = reference.chapter ?? 1
            draft.start = VerseID(book: reference.book.id, chapter: chapter, verse: reference.verseStart ?? 0)
            draft.end = reference.verseEnd.map { VerseID(book: reference.book.id, chapter: chapter, verse: $0) }
        }
        isSending = true
        Task {
            if await model.post(draft) { dismiss() }
            isSending = false
        }
    }
}

/// A post and its comments.
struct CommunityPostDetailView: View {
    let post: CommunityPost

    @Environment(CommunityStore.self) private var community
    @Environment(\.palette) private var palette
    @State private var feed: CommunityFeedModel?
    @State private var comments: [CommunityComment] = []
    @State private var draft = ""
    @State private var errorMessage: String?
    @State private var isSending = false
    @State private var showsGuidelines = false
    @State private var sendAfterGuidelines = false

    var body: some View {
        List {
            if let feed {
                Section {
                    CommunityPostRow(post: feed.posts.first { $0.id == post.id } ?? post, model: feed, showsComments: false)
                }
                .listRowBackground(palette.surface)
            }
            Section("Comments") {
                ForEach(comments.filter { !community.blocked.contains($0.userID) }) { comment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(comment.displayName).font(.subheadline.weight(.semibold))
                            Text(comment.createdAt, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                        }
                        Text(comment.body).foregroundStyle(palette.text)
                    }
                    .contentActions(
                        .communityComment, id: comment.id, authorName: comment.displayName,
                        isMine: community.isMine(comment.userID),
                        canRemove: community.isMine(comment.userID),
                        onRemove: { await removeComment(comment) },
                        onBlock: { await community.block(comment.userID) },
                        onHidden: { comments.removeAll { $0.id == comment.id } }
                    )
                }
                HStack(alignment: .bottom) {
                    TextField(post.kind == .prayer ? "Send encouragement" : "Add a comment", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .accessibilityIdentifier("community.commentField")
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("community.sendComment")
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.orange)
                }
            }
            .listRowBackground(palette.surface)
        }
        .buttonStyle(.borderless)
        .themedScreen()
        .navigationTitle(post.kind == .prayer ? "Prayer Request" : "Reflection")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let feed = CommunityFeedModel(kind: post.kind, store: community)
            self.feed = feed
            await load()
            await feed.include(post)
        }
        .refreshable { await load() }
        .sheet(isPresented: $showsGuidelines, onDismiss: {
            if sendAfterGuidelines {
                sendAfterGuidelines = false
                send()
            }
        }) {
            CommunityGuidelinesView { sendAfterGuidelines = true }
        }
    }

    private func load() async {
        do {
            comments = try await community.backend.comments(on: post.id)
            if let feed { await feed.refresh() }
        } catch {
            errorMessage = CommunityError.from(error).localizedDescription
        }
    }

    private func send() {
        guard community.profile?.hasAcceptedTerms == true else {
            showsGuidelines = true
            return
        }
        isSending = true
        Task {
            do {
                try await community.backend.addComment(draft.trimmingCharacters(in: .whitespacesAndNewlines), on: post.id)
                draft = ""
                errorMessage = nil
                await load()
            } catch {
                errorMessage = CommunityError.from(error).localizedDescription
            }
            isSending = false
        }
    }

    private func removeComment(_ comment: CommunityComment) async {
        do {
            try await community.backend.remove(.communityComment, id: comment.id)
            comments.removeAll { $0.id == comment.id }
        } catch {
            errorMessage = CommunityError.from(error).localizedDescription
        }
    }
}
