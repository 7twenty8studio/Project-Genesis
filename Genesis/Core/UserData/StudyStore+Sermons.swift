import Foundation
import SwiftData

// The Sermon Companion. Same rules as the rest of StudyStore: every change
// updates `updatedAt`, deletions leave a tombstone for sync.

extension StudyStore {
    @discardableResult
    func createSermon(church: String = "", on date: Date = .now) -> Sermon {
        let sermon = Sermon(church: church, preachedAt: date)
        context.insert(sermon)
        save()
        return sermon
    }

    /// Sermons with any content.
    func sermonCount() -> Int {
        let descriptor = FetchDescriptor<Sermon>(predicate: #Predicate { $0.title != "" || $0.body != "" || $0.passagesRaw != "" })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    /// Attaches a passage (ids only), once.
    func attach(_ passage: PrayerPassage, to sermon: Sermon) {
        var passages = sermon.passages
        guard !passages.contains(passage), passages.count < Sermon.maximumPassages else { return }
        passages.append(passage)
        sermon.passages = passages
        sermon.updatedAt = .now
        save()
    }

    func detach(_ passage: PrayerPassage, from sermon: Sermon) {
        sermon.passages = sermon.passages.filter { $0 != passage }
        sermon.updatedAt = .now
        save()
    }

    func toggleFavourite(_ sermon: Sermon) {
        sermon.isFavourite.toggle()
        sermon.updatedAt = .now
        save()
    }

    func delete(_ sermon: Sermon) {
        deleteAttachments(of: .sermon, id: sermon.id)
        recordDeletion(of: sermon.id, in: SyncTable.sermons)
        context.delete(sermon)
        save()
    }
}
