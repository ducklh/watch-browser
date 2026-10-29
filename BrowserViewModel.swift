import Foundation
import Combine

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var addressText = ""
    @Published private(set) var page: ReaderPage?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    private enum HistoryAction {
        case push
        case move(to: Int)
    }

    private let engine = BrowserEngine()
    private var history: [URL] = []
    private var historyIndex = -1
    private var loadTask: Task<Void, Never>?
    private var activeLoadID: UUID?

    func navigate(to input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let candidate = URL(string: text.contains("://") ? text : "https://\(text)")
        guard let url = candidate,
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.host != nil else {
            loadTask?.cancel()
            activeLoadID = UUID()
            isLoading = false
            errorMessage = BrowserError.unsupportedURL.localizedDescription
            return
        }
        load(url, action: .push)
    }

    func goBack() {
        guard historyIndex > 0 else { return }
        load(history[historyIndex - 1], action: .move(to: historyIndex - 1))
    }

    func goForward() {
        guard historyIndex + 1 < history.count else { return }
        load(history[historyIndex + 1], action: .move(to: historyIndex + 1))
    }

    private func load(_ url: URL, action: HistoryAction) {
        loadTask?.cancel()
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        errorMessage = nil

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loadedPage = try await engine.load(url)
                try Task.checkCancellation()
                guard activeLoadID == loadID else { return }
                page = loadedPage
                addressText = loadedPage.finalURL.absoluteString

                switch action {
                case .push:
                    if historyIndex + 1 < history.count {
                        history.removeSubrange((historyIndex + 1)..<history.count)
                    }
                    history.append(loadedPage.finalURL)
                    if history.count > 50 {
                        history.removeFirst(history.count - 50)
                    }
                    historyIndex = history.count - 1
                case .move(let index):
                    historyIndex = index
                }
                updateNavigationAvailability()
                isLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard activeLoadID == loadID else { return }
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func updateNavigationAvailability() {
        canGoBack = historyIndex > 0
        canGoForward = historyIndex >= 0 && historyIndex + 1 < history.count
    }
}
