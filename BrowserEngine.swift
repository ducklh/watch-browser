import Foundation

enum BrowserError: LocalizedError {
    case unsupportedURL
    case invalidResponse
    case unsuccessfulResponse(Int)
    case unsupportedContentType
    case pageTooLarge
    case unreadablePage

    var errorDescription: String? {
        switch self {
        case .unsupportedURL:
            return "Enter a valid HTTP or HTTPS address."
        case .invalidResponse:
            return "The website returned an unsupported response."
        case .unsuccessfulResponse(let status):
            return "The website returned an error (HTTP \(status))."
        case .unsupportedContentType:
            return "This page does not provide readable HTML."
        case .pageTooLarge:
            return "This page is too large to read on Apple Watch."
        case .unreadablePage:
            return "The page could not be decoded."
        }
    }
}

actor BrowserEngine {
    private static let maximumHTMLBytes = 1_200_000
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = URLCache(
            memoryCapacity: 2 * 1_024 * 1_024,
            diskCapacity: 8 * 1_024 * 1_024,
            diskPath: "pocket-reader"
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 35
        configuration.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: configuration)
    }

    func load(_ url: URL) async throws -> ReaderPage {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw BrowserError.unsupportedURL
        }

        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml;q=0.9,*/*;q=0.2", forHTTPHeaderField: "Accept")
        request.setValue("PocketReaderWatch/1.0", forHTTPHeaderField: "User-Agent")

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BrowserError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BrowserError.unsuccessfulResponse(httpResponse.statusCode)
        }

        let mimeType = httpResponse.mimeType?.lowercased()
        guard mimeType == "text/html" || mimeType == "application/xhtml+xml" else {
            throw BrowserError.unsupportedContentType
        }

        var data = Data()
        data.reserveCapacity(64 * 1_024)
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.maximumHTMLBytes else {
                throw BrowserError.pageTooLarge
            }
            data.append(byte)
        }

        guard let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw BrowserError.unreadablePage
        }

        return HTMLReaderParser.parse(html, baseURL: httpResponse.url ?? url)
    }
}
