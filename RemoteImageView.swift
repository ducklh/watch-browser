import ImageIO
import SwiftUI

private final class CachedImage: NSObject {
    let value: CGImage

    init(_ value: CGImage) {
        self.value = value
    }
}

@MainActor
private final class ImageLoader: ObservableObject {
    @Published private(set) var image: Image?
    @Published private(set) var didFail = false

    private static let cache: NSCache<NSURL, CachedImage> = {
        let cache = NSCache<NSURL, CachedImage>()
        cache.totalCostLimit = 2 * 1_024 * 1_024
        return cache
    }()
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = URLCache(memoryCapacity: 1 * 1_024 * 1_024, diskCapacity: 0, diskPath: nil)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()
    private let maximumBytes = 600 * 1_024

    func load(_ url: URL) async {
        image = nil
        didFail = false
        let key = url as NSURL
        if let cached = Self.cache.object(forKey: key) {
            image = Image(decorative: cached.value, scale: 1)
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (bytes, response) = try await Self.session.bytes(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  response.mimeType?.lowercased().hasPrefix("image/") == true else {
                didFail = true
                return
            }

            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBytes else {
                    didFail = true
                    return
                }
                data.append(byte)
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 480,
                        kCGImageSourceShouldCacheImmediately: true
                    ] as CFDictionary
                  ) else {
                didFail = true
                return
            }

            Self.cache.setObject(
                CachedImage(thumbnail),
                forKey: key,
                cost: thumbnail.width * thumbnail.height * 4
            )
            image = Image(decorative: thumbnail, scale: 1)
        } catch is CancellationError {
            return
        } catch {
            didFail = true
        }
    }
}

struct RemoteImageView: View {
    let url: URL
    @StateObject private var loader = ImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if loader.didFail {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel("Image unavailable")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .task(id: url) {
            await loader.load(url)
        }
    }
}
