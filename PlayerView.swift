import AVKit
import SwiftUI
import WatchKit

struct PlayerView: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 10) {
            if let player {
                VideoPlayer(player: player)
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                ProgressView("Preparing video")
            }

            Button("Open with system app") {
                WKExtension.shared().openSystemURL(url)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Video")
        .onAppear {
            let item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item)
            player?.play()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}
