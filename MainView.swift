import SwiftUI

struct MainView: View {
    @StateObject private var browser = BrowserViewModel()
    @StateObject private var bookmarkStore = BookmarkStore()
    @State private var showingBookmarks = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    TextField("Web address", text: $browser.addressText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .onSubmit {
                            browser.navigate(to: browser.addressText)
                        }

                    Button {
                        browser.navigate(to: browser.addressText)
                    } label: {
                        Image(systemName: "arrow.right")
                    }
                    .accessibilityLabel("Go to address")
                }

                HStack {
                    Button(action: browser.goBack) {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!browser.canGoBack)
                    .accessibilityLabel("Back")

                    Button(action: browser.goForward) {
                        Image(systemName: "chevron.forward")
                    }
                    .disabled(!browser.canGoForward)
                    .accessibilityLabel("Forward")

                    Spacer(minLength: 4)

                    if let page = browser.page {
                        Button {
                            bookmarkStore.toggle(page)
                        } label: {
                            Image(systemName: bookmarkStore.contains(page.finalURL) ? "bookmark.fill" : "bookmark")
                        }
                        .accessibilityLabel(
                            bookmarkStore.contains(page.finalURL) ? "Remove bookmark" : "Add bookmark"
                        )
                    }

                    Button {
                        showingBookmarks = true
                    } label: {
                        Image(systemName: "books.vertical")
                    }
                    .accessibilityLabel("Bookmarks")
                }
                .buttonStyle(.plain)

                if browser.isLoading {
                    ProgressView("Loading")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let error = browser.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let page = browser.page {
                    ReaderView(page: page)
                } else if !browser.isLoading && browser.errorMessage == nil {
                    ContentPlaceholder()
                }
            }
            .padding(.horizontal, 8)
            .navigationTitle("Pocket Reader")
            .sheet(isPresented: $showingBookmarks) {
                BookmarkListView(store: bookmarkStore) { url in
                    showingBookmarks = false
                    browser.navigate(to: url)
                }
            }
        }
    }
}

private struct ReaderView: View {
    let page: ReaderPage

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text(page.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.finalURL.host ?? page.finalURL.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if page.paragraphs.isEmpty {
                    Text("No readable article text was found.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(page.paragraphs.indices, id: \.self) { index in
                        Text(page.paragraphs[index])
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ForEach(page.images, id: \.absoluteString) { imageURL in
                    RemoteImageView(url: imageURL)
                }

                ForEach(page.videoURLs, id: \.absoluteString) { videoURL in
                    NavigationLink {
                        PlayerView(url: videoURL)
                    } label: {
                        Label(videoURL.lastPathComponent.isEmpty ? "Play video" : videoURL.lastPathComponent,
                              systemImage: "play.rectangle")
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }
}

private struct ContentPlaceholder: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Enter a web address to read.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BookmarkListView: View {
    @ObservedObject var store: BookmarkStore
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if store.bookmarks.isEmpty {
                    ContentUnavailableView("No Bookmarks", systemImage: "bookmark")
                } else {
                    List {
                        ForEach(store.bookmarks) { bookmark in
                            Button {
                                onSelect(bookmark.url)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(bookmark.title)
                                        .lineLimit(2)
                                    Text(bookmark.url)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.remove(bookmark)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bookmarks")
        }
    }
}
