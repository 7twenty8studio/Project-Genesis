import Foundation

/// The prayer wall or the reflections feed, newest first, with "load more".
@MainActor
@Observable
final class CommunityFeedModel {
    let kind: CommunityPostKind
    private(set) var posts: [CommunityPost] = []
    private(set) var reacted: Set<UUID> = []
    private(set) var isLoading = false
    private(set) var reachedEnd = false
    var errorMessage: String?

    @ObservationIgnored private let store: CommunityStore
    private var backend: CommunityBackend { store.backend }

    init(kind: CommunityPostKind, store: CommunityStore) {
        self.kind = kind
        self.store = store
    }

    var visiblePosts: [CommunityPost] {
        posts.filter { post in post.authorID.map { !store.blocked.contains($0) } ?? true }
    }

    /// Makes sure a post opened from elsewhere (an older one, say) can be
    /// reacted to.
    func include(_ post: CommunityPost) async {
        guard !posts.contains(where: { $0.id == post.id }) else { return }
        posts.append(post)
        if let mine = try? await backend.myReactions([post.id]) { reacted.formUnion(mine) }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await backend.feed(kind, before: nil)
            posts = page
            reachedEnd = page.count < 40
            reacted = try await backend.myReactions(page.map(\.id))
            errorMessage = nil
        } catch {
            errorMessage = CommunityError.from(error).localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoading, !reachedEnd, let oldest = posts.last?.createdAt else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await backend.feed(kind, before: oldest)
            let known = Set(posts.map(\.id))
            posts += page.filter { !known.contains($0.id) }
            reachedEnd = page.count < 40
            reacted.formUnion(try await backend.myReactions(page.map(\.id)))
        } catch {
            errorMessage = CommunityError.from(error).localizedDescription
        }
    }

    func post(_ draft: CommunityDraft) async -> Bool {
        do {
            try await backend.addCommunityPost(draft)
            await refresh()
            return errorMessage == nil
        } catch {
            errorMessage = CommunityError.from(error).localizedDescription
            return false
        }
    }

    func toggleReaction(_ post: CommunityPost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let reacting = !reacted.contains(post.id)
        if reacting { reacted.insert(post.id) } else { reacted.remove(post.id) }
        posts[index].reactionCount += reacting ? 1 : -1
        do {
            try await backend.setReacted(reacting, post: post.id)
        } catch {
            if reacting { reacted.remove(post.id) } else { reacted.insert(post.id) }
            if let index = posts.firstIndex(where: { $0.id == post.id }) { posts[index].reactionCount += reacting ? -1 : 1 }
            errorMessage = CommunityError.from(error).localizedDescription
        }
    }

    func remove(_ post: CommunityPost) async {
        do {
            try await backend.remove(.communityPost, id: post.id)
            posts.removeAll { $0.id == post.id }
        } catch {
            errorMessage = CommunityError.from(error).localizedDescription
        }
    }

    /// Reported posts disappear for the person who reported them.
    func hide(_ id: UUID) {
        posts.removeAll { $0.id == id }
    }
}
