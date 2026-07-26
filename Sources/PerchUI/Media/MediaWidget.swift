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
    private var lingerTask: Task<Void, Never>?

    /// How long the helper keeps running after the notch closes.
    ///
    /// Tearing it down immediately was wrong in both directions: the helper idles at 0% CPU and
    /// 18MB, while restarting it costs seconds of *visibly* empty panel, because `stream` emits
    /// once and then stays silent until playback changes. Lingering makes reopening instant and
    /// still releases everything if the notch is left alone.
    private static let lingerAfterClose = Duration.seconds(90)

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
        lingerTask?.cancel()
        lingerTask = nil
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
        // Deliberately keeps `playing` and `artwork`. Clearing them meant every reopen showed an
        // empty panel that then filled in piecemeal — the artwork arriving a beat after the text,
        // over a background that had already finished animating. Holding one downsampled thumbnail
        // is a few tens of kilobytes; the flicker was the real cost.
        guard lingerTask == nil else { return }

        lingerTask = Task { [weak self] in
            try? await Task.sleep(for: Self.lingerAfterClose)
            guard !Task.isCancelled else { return }
            self?.releaseSource()
        }
    }

    /// Actually stop, once the notch has stayed shut long enough to mean it.
    private func releaseSource() {
        listener?.cancel()
        listener = nil
        source?.stop()
        source = nil
        lingerTask = nil
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
        .accessibilityIdentifier(widget.artwork == nil ? "media.artwork.missing" : "media.artwork")
    }

    private func details(for playing: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playing.title ?? "")
                .accessibilityIdentifier("media.title")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let artist = playing.artist, !artist.isEmpty {
                Text(artist)
                    .accessibilityIdentifier("media.artist")
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
        // Identifiers are how `make ui-probe` finds and presses these without touching a pixel.
        .accessibilityIdentifier(command.accessibilityIdentifier)
    }
}
