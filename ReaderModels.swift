import Foundation

struct ReaderPage: Sendable {
    let title: String
    let finalURL: URL
    let paragraphs: [String]
    let images: [URL]
    let videoURLs: [URL]

    var bodyText: String {
        paragraphs.joined(separator: "\n\n")
    }
}

struct Bookmark: Identifiable, Codable, Equatable {
    var id: String { url }

    let title: String
    let url: String
}
