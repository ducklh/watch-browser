import Foundation
import Combine
import OSLog

@MainActor
final class BookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark]

    private let storageKey = "pocket-reader.bookmarks"
    private let logger = Logger(subsystem: "com.example.PocketReaderWatch", category: "Bookmarks")

    init() {
        bookmarks = []
        if let data = UserDefaults.standard.data(forKey: storageKey),
           !data.isEmpty {
            do {
                bookmarks = try JSONDecoder().decode([Bookmark].self, from: data)
            } catch {
                logger.error("Could not decode saved bookmarks: \(error.localizedDescription, privacy: .public)")
                bookmarks = []
            }
        } else {
            bookmarks = []
        }
    }

    func contains(_ url: URL) -> Bool {
        bookmarks.contains { $0.url == url.absoluteString }
    }

    func toggle(_ page: ReaderPage) {
        let address = page.finalURL.absoluteString
        if let index = bookmarks.firstIndex(where: { $0.url == address }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.insert(Bookmark(title: page.title, url: address), at: 0)
            if bookmarks.count > 40 {
                bookmarks.removeLast(bookmarks.count - 40)
            }
        }
        persist()
    }

    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(bookmarks)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            logger.error("Could not save bookmarks: \(error.localizedDescription, privacy: .public)")
        }
    }
}
