# Pocket Reader for Apple Watch

A lightweight watchOS 10+ reader app for Apple Watch Series 7 and later. It fetches HTML with `URLSession`, turns visible page text into a simple reader layout, and displays a small number of downsampled images and supported video links. It does not embed a web browser or execute website scripts.

## Project layout

```text
PocketReaderWatch/
├── BrowserApp.swift
├── MainView.swift
├── BrowserViewModel.swift
├── BrowserEngine.swift
├── HTMLReaderParser.swift
├── ReaderModels.swift
├── BookmarkStore.swift
├── RemoteImageView.swift
├── PlayerView.swift
└── PocketReaderWatch.xcodeproj/
    ├── project.pbxproj
    └── xcshareddata/xcschemes/PocketReader.xcscheme
```

## Open and run

1. Open `PocketReaderWatch.xcodeproj` in Xcode 15 or newer on a Mac.
2. Select the `PocketReader` scheme and a watchOS 10 simulator or a paired Apple Watch Series 7+.
3. Set your Apple Developer team under **Signing & Capabilities** if deploying to a physical watch. The bundle identifier in the project is `com.example.PocketReaderWatch`; change it before publishing.
4. Build and run. Enter a URL in the top field. The watch text-entry UI supports the available dictation and Scribble input methods. Use the arrows for browser history and the bookmark controls to save pages.

No third-party packages are required. The project is a standalone watch app; it does not include an iPhone companion target.

## Resource and compatibility notes

- HTML responses are read incrementally and capped at 1.2 MB. Requests have 20/35 second timeouts and use an ephemeral URL cache capped at 2 MB in memory and 8 MB on disk.
- The reader retains at most 80 text blocks, 8 images, 5 video links, 50 history entries, and 40 bookmarks.
- Images are downloaded one at a time per visible reader row, limited to 600 KB each, downsampled to 480 pixels, and held in a 2 MB cost-limited image cache.
- The parser is deliberately small and tolerant, not a standards-complete HTML5 parser. Sites requiring JavaScript, authentication, cookies, or complex page layouts may not render meaningful content. Only HTTP and HTTPS sources are accepted.
- `AVKit` playback depends on the stream format, server headers, DRM, and watchOS support. The system-app button is a best-effort fallback; a standalone watch app cannot force a paired iPhone app to open a URL. An iPhone companion app would be required for explicit Watch Connectivity handoff.
- The UI uses lazy rendering and bounded data to keep work small, but a 60 fps guarantee cannot be made for all content or hardware conditions.
