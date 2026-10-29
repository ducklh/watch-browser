import Foundation

enum HTMLReaderParser {
    private static let tagExpression = try! NSRegularExpression(
        pattern: #"<!--[\s\S]*?-->|<![^>]*>|</?([A-Za-z][A-Za-z0-9:-]*)\b([^>]*)>"#
    )
    private static let attributeExpression = try! NSRegularExpression(
        pattern: #"([A-Za-z_:][A-Za-z0-9:._-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#
    )
    private static let entityExpression = try! NSRegularExpression(
        pattern: #"&(#x[0-9A-Fa-f]+|#[0-9]+|amp|lt|gt|quot|apos|nbsp|copy|reg|mdash|ndash|hellip);?"#,
        options: [.caseInsensitive]
    )

    private static let excludedTags: Set<String> = [
        "script", "style", "noscript", "svg", "nav", "footer", "header",
        "aside", "form", "button", "iframe", "object", "template", "head"
    ]
    private static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]
    private static let blockTags: Set<String> = [
        "article", "blockquote", "br", "div", "h1", "h2", "h3", "h4",
        "h5", "h6", "li", "main", "p", "pre", "section", "tr"
    ]
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "copy": "©", "reg": "®", "mdash": "—",
        "ndash": "–", "hellip": "…"
    ]

    static func parse(_ html: String, baseURL: URL) -> ReaderPage {
        let source = html as NSString
        let fullRange = NSRange(location: 0, length: source.length)
        let matches = tagExpression.matches(in: html, range: fullRange)

        var paragraphs: [String] = []
        var images: [URL] = []
        var videos: [URL] = []
        var currentBlock = ""
        var titleText = ""
        var isReadingTitle = false
        var ignoredDepth = 0
        var cursor = 0

        func appendText(_ rawText: String) {
            let text = decodeEntities(rawText)
            let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !collapsed.isEmpty else { return }
            if isReadingTitle {
                titleText += collapsed + " "
            } else if ignoredDepth == 0 {
                currentBlock += collapsed + " "
            }
        }

        func flushBlock() {
            let value = currentBlock.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty, paragraphs.count < 80 {
                paragraphs.append(value)
            }
            currentBlock = ""
        }

        for match in matches {
            if match.range.location > cursor {
                appendText(source.substring(with: NSRange(
                    location: cursor,
                    length: match.range.location - cursor
                )))
            }

            let tagRange = match.range(at: 1)
            guard tagRange.location != NSNotFound else {
                cursor = NSMaxRange(match.range)
                continue
            }

            let tag = source.substring(with: tagRange).lowercased()
            let rawTag = source.substring(with: match.range)
            let isClosing = rawTag.dropFirst().first == "/"
            let attributesRange = match.range(at: 2)
            let attributes = attributesRange.location == NSNotFound
                ? [:]
                : parseAttributes(source.substring(with: attributesRange))

            if tag == "title" {
                isReadingTitle = !isClosing
            }

            if isClosing {
                if ignoredDepth > 0, !voidTags.contains(tag) {
                    ignoredDepth -= 1
                }
                if blockTags.contains(tag), ignoredDepth == 0 {
                    flushBlock()
                }
            } else {
                let isIgnored = excludedTags.contains(tag)
                    || attributes["aria-hidden"]?.lowercased() == "true"
                    || attributes["hidden"] != nil
                if (isIgnored || ignoredDepth > 0),
                   !voidTags.contains(tag),
                   !rawTag.hasSuffix("/>") {
                    ignoredDepth += 1
                }

                if tag == "img", ignoredDepth == 0 {
                    let candidates = [
                        attributes["src"], attributes["data-src"],
                        attributes["data-original"], firstSource(in: attributes["srcset"])
                    ]
                    for candidate in candidates.compactMap({ $0 }) {
                        if let url = resolve(candidate, relativeTo: baseURL) {
                            appendUnique(url, to: &images, limit: 8)
                            break
                        }
                    }
                } else if tag == "video", ignoredDepth == 0,
                          let source = attributes["src"],
                          let url = resolve(source, relativeTo: baseURL) {
                    appendUnique(url, to: &videos, limit: 5)
                } else if tag == "source", ignoredDepth == 0,
                          let source = attributes["src"],
                          let url = resolve(source, relativeTo: baseURL),
                          isVideo(url, type: attributes["type"]) {
                    appendUnique(url, to: &videos, limit: 5)
                } else if tag == "a", ignoredDepth == 0,
                          let href = attributes["href"],
                          let url = resolve(href, relativeTo: baseURL),
                          isVideo(url, type: nil) {
                    appendUnique(url, to: &videos, limit: 5)
                }

                if blockTags.contains(tag), ignoredDepth == 0 {
                    flushBlock()
                }
            }

            if voidTags.contains(tag), blockTags.contains(tag), ignoredDepth == 0 {
                flushBlock()
            }
            cursor = NSMaxRange(match.range)
        }

        if cursor < source.length {
            appendText(source.substring(from: cursor))
        }
        flushBlock()

        let title = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? (baseURL.host ?? "Web page") : title
        return ReaderPage(
            title: String(resolvedTitle.prefix(180)),
            finalURL: baseURL,
            paragraphs: paragraphs,
            images: images,
            videoURLs: videos
        )
    }

    private static func parseAttributes(_ text: String) -> [String: String] {
        let source = text as NSString
        let matches = attributeExpression.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        var result: [String: String] = [:]
        for match in matches {
            let name = source.substring(with: match.range(at: 1)).lowercased()
            let valueRange = [2, 3, 4]
                .map { match.range(at: $0) }
                .first { $0.location != NSNotFound }
            if let valueRange {
                result[name] = decodeEntities(source.substring(with: valueRange))
            }
        }
        return result
    }

    private static func decodeEntities(_ text: String) -> String {
        let source = text as NSString
        let matches = entityExpression.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else { return text }

        var output = text
        for match in matches.reversed() {
            let token = source.substring(with: match.range(at: 1))
            let replacement: String?
            if token.hasPrefix("#x") || token.hasPrefix("#X") {
                if let value = UInt32(token.dropFirst(2), radix: 16),
                   let scalar = UnicodeScalar(value) {
                    replacement = String(scalar)
                } else {
                    replacement = nil
                }
            } else if token.hasPrefix("#") {
                if let value = UInt32(token.dropFirst()),
                   let scalar = UnicodeScalar(value) {
                    replacement = String(scalar)
                } else {
                    replacement = nil
                }
            } else {
                replacement = namedEntities[token.lowercased()]
            }
            if let replacement, let range = Range(match.range, in: output) {
                output.replaceSubrange(range, with: replacement)
            }
        }
        return output
    }

    private static func firstSource(in srcset: String?) -> String? {
        guard let srcset else { return nil }
        return srcset.split(separator: ",").first?
            .split(whereSeparator: \.isWhitespace).first.map { String($0) }
    }

    private static func resolve(_ value: String, relativeTo baseURL: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func isVideo(_ url: URL, type: String?) -> Bool {
        let path = url.path.lowercased()
        let supportedExtensions = [".mp4", ".m3u8", ".mov", ".m4v"]
        return supportedExtensions.contains(where: path.hasSuffix)
            || type?.lowercased().contains("video/") == true
            || type?.lowercased().contains("mpegurl") == true
    }

    private static func appendUnique(_ url: URL, to list: inout [URL], limit: Int) {
        guard list.count < limit, !list.contains(url) else { return }
        list.append(url)
    }
}
