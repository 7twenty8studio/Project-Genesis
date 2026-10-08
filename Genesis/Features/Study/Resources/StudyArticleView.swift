import SwiftUI

/// One article from a study pack: a dictionary entry, a person's profile,
/// a theme or a key term.
struct StudyArticleView: View {
    let pack: String
    let articleID: String
    var onOpenVerse: ((VerseID) -> Void)?

    @Environment(StudyResourceLibrary.self) private var resources
    @Environment(EntitlementService.self) private var entitlements
    @Environment(\.palette) private var palette
    @State private var article: StudyArticle?
    @State private var hasLoaded = false

    private var resource: DownloadableStudyResource? { resources.resource(pack) }
    private var locked: Bool { resource?.premium == true && !entitlements.allows(.wordStudy) }

    var body: some View {
        List {
            ThemedRows {
                if !resources.isInstalled(pack) {
                    let name = resource?.name ?? String(localized: "this resource")
                    Section {
                        Text("Download \(name) from the Study Library to read this article.")
                            .foregroundStyle(palette.secondaryText)
                    }
                } else if locked {
                    Section {
                        PremiumTeaser(message: String(localized: "Read this resource with Premium."), feature: .wordStudy)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    }
                } else if let article {
                    Section {
                        StudyTextRows(text: article.text)
                    } footer: {
                        if let resource {
                            Text(resource.attribution.isEmpty ? resource.name : resource.attribution)
                        }
                    }
                } else if hasLoaded {
                    Section {
                        Text("This article isn't in the downloaded edition.")
                            .foregroundStyle(palette.secondaryText)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .themedScreen()
        .navigationTitle(article?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .studyLinks(onOpenVerse: onOpenVerse)
        .task(id: articleID) { await load() }
    }

    private func load() async {
        guard let repository = resources.repository(pack) else {
            hasLoaded = true
            return
        }
        let id = articleID
        article = await Task.detached(priority: .userInitiated) {
            try? repository.article(id: id)
        }.value
        hasLoaded = true
    }
}

/// A pack's articles by title, with search (accents and case don't matter).
struct StudyArticleBrowserView: View {
    let pack: String

    @Environment(StudyResourceLibrary.self) private var resources
    @Environment(\.palette) private var palette
    @State private var query = ""
    @State private var results: [StudyArticleSummary] = []

    var body: some View {
        List {
            ThemedRows {
                ForEach(results) { summary in
                    NavigationLink(value: StudyArticleRoute(pack: pack, id: summary.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.title).foregroundStyle(palette.text)
                            if let kind = StudyArticleKind.title(summary.kind) {
                                Text(kind)
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                }
            }
        }
        .themedScreen()
        .navigationTitle(resources.resource(pack)?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .accessibilityIdentifier("studyResources.articles")
        .navigationDestination(for: StudyArticleRoute.self) { route in
            StudyArticleView(pack: route.pack, articleID: route.id)
        }
        .task(id: query) { await search() }
    }

    private func search() async {
        guard let repository = resources.repository(pack) else { return }
        let text = query
        if !text.isEmpty {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
        }
        results = await Task.detached(priority: .userInitiated) {
            (try? repository.searchArticles(text, limit: 200)) ?? []
        }.value
    }
}

/// Names for the packs' article kinds.
enum StudyArticleKind {
    static func title(_ kind: String) -> String? {
        switch kind {
        case "profile": String(localized: "Profile", comment: "Kind of study article: about a person")
        case "theme": String(localized: "Theme", comment: "Kind of study article")
        case "keyterm": String(localized: "Key term", comment: "Kind of study article")
        case "name": String(localized: "Name", comment: "Kind of study article: a person or place name")
        case "term": String(localized: "Term", comment: "Kind of study article")
        default: nil
        }
    }
}
