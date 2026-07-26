import AppKit
import PerchCore
import PerchMedia
import SwiftUI

/// Shows what is playing, with transport controls.
@MainActor
@Observable
public final class MediaWidget: NotchWidget {

    public static let kind = "media"

    public let placement: Placement

    private let showsArtwork: Bool
    private let artworkSize: CGFloat

    private var source: (any MediaSource)?
    private var listener: Task<Void, Never>?

    /// What is playing, or nil.
    fileprivate private(set) var playing: NowPlaying?

    /// Decoded album art for `playing`, once it has been prepared off the main thread.
    fileprivate private(set) var artwork: NSImage?

    public init(settings: WidgetSettings) throws {
        placement = try settings.enumeration("placement", default: .expanded)
        showsArtwork = try settings.bool("artwork", default: true)
        artworkSize = try settings.length("artwork-size", default: 56)
    }

    public func activate() {
        guard listener == nil else { return }

        // Built here rather than in `init` so a widget that is configured but never shown never
        // spawns a subprocess.
        let source = source ?? MediaRemoteAdapterSource()
        self.source = source
        guard let source else { return }

        source.start()
        listener = Task { [weak self] in
            for await update in source.updates {
                guard !Task.isCancelled else { return }
                await self?.apply(update)
            }
        }
    }

    public func deactivate() {
        listener?.cancel()
        listener = nil
        source?.stop()
        // Drop the artwork too: it is the largest thing this widget holds, and a hidden widget
        // holding a decoded bitmap is exactly the leak `deactivate` exists to prevent.
        artwork = nil
    }

    public var body: AnyView {
        AnyView(MediaWidgetView(widget: self, showsArtwork: showsArtwork, artworkSize: artworkSize))
    }

    fileprivate func send(_ command: MediaCommand) {
        source?.send(command)
    }

    private func apply(_ update: NowPlaying?) async {
        playing = update

        guard showsArtwork, let data = update?.artworkData else {
            artwork = nil
            return
        }

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = artworkSize
        let decoded = await ArtworkCache.shared.image(
            for: data, maximumDimension: size, scale: scale
        )

        // The track may have moved on while that was decoding; dropping a stale image is cheaper
        // than showing the wrong album.
        guard playing?.artworkData == data else { return }
        artwork = decoded
    }
}

/// The media widget's appearance.
private struct MediaWidgetView: View {

    let widget: MediaWidget
    let showsArtwork: Bool
    let artworkSize: CGFloat

    var body: some View {
        if let playing = widget.playing, playing.isPresentable {
            HStack(spacing: 12) {
                if showsArtwork { artworkView }
                details(for: playing)
                Spacer(minLength: 0)
                controls
            }
            .padding(.horizontal, 4)
        } else {
            Text("Nothing playing")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var artworkView: some View {
        Group {
            if let artwork = widget.artwork {
                Image(nsImage: artwork).resizable()
            } else {
                // A neutral placeholder rather than nothing, so the row does not resize the
                // instant artwork finishes decoding.
                RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08))
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func details(for playing: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playing.title ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let artist = playing.artist, !artist.isEmpty {
                Text(artist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            button("backward.fill", .previousTrack)
            button(
                widget.playing?.isPlaying == true ? "pause.fill" : "play.fill",
                .togglePlayPause
            )
            button("forward.fill", .nextTrack)
        }
    }

    private func button(_ symbol: String, _ command: MediaCommand) -> some View {
        Button {
            widget.send(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
