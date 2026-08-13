import AppKit
import PerchCore
import PerchMedia
import SwiftUI

/// Shows what is playing, with transport controls.
@MainActor
@Observable
public final class MediaWidget: NotchWidget {

    public static let kind = "media"

    public static let summary = "Shows the current track with transport controls."

    public static let settings: [WidgetSetting] = [
        WidgetSetting(
            name: "placement", syntax: "leading | trailing | expanded", defaultValue: "expanded",
            documentation: "Where the widget draws."),
        WidgetSetting(
            name: "artwork", syntax: "true | false", defaultValue: "true",
            documentation: "Show album art."),
        WidgetSetting(
            name: "artwork-size", syntax: "points", defaultValue: "48",
            documentation: "Size of the album art."),
    ]

    public let placement: Placement

    private let showsArtwork: Bool
    private let artworkSize: CGFloat

    private var source: (any MediaSource)?
    private var listener: Task<Void, Never>?
    private var lingerTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var seekSettleTask: Task<Void, Never>?

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

    /// The app the current track is coming from, when it is one that can be opened.
    ///
    /// Nil means the artwork is a picture rather than a door: nothing on this Mac claims the
    /// identifier the system reported. Resolved when the identifier changes rather than on demand,
    /// because "on demand" is every repaint, and the scrubber repaints twice a second.
    fileprivate private(set) var player: PlayerApp?

    /// The identifier `player` was resolved from, so it is looked up once per player and not once
    /// per update.
    private var resolvedPlayerIdentifier: String?

    /// The track as it was when the current announcement started.
    ///
    /// A track change arrives as several updates in quick succession — title first, then artwork,
    /// then position — and rendering each one repaints the announcement while it is being read.
    /// Freezing it means a peek says one thing for its whole duration.
    fileprivate private(set) var peekSnapshot: NowPlaying?

    /// The moment the scrubber is drawn against.
    ///
    /// The system reports a position once per change rather than continuously, so a bar that is
    /// going to move has to be told what time it is. Only advances while something is playing:
    /// repainting a paused track twice a second is work nobody can see.
    fileprivate private(set) var now = Date()

    /// How far along the scrubber the pointer is, while a drag is in progress.
    ///
    /// The thumb follows the pointer rather than the player: a bar that only moves once the
    /// player has caught up feels stuck, and the player will not report anything at all until the
    /// drag ends.
    fileprivate var dragFraction: Double?

    /// Where playback was asked to go, held until the player agrees it went there.
    ///
    /// Without this the bar snaps back to the old position for the beat between letting go and the
    /// player's next update, which reads as the seek having failed.
    fileprivate private(set) var pendingSeek: TimeInterval?

    /// When that request went out, so an update that predates it is not mistaken for a reply.
    private var seekSentAt: Date?

    public init(settings: WidgetSettings) throws {
        placement = try settings.enumeration("placement", default: .expanded)
        showsArtwork = try settings.bool("artwork", default: true)
        artworkSize = try settings.length("artwork-size", default: PanelMetrics.artwork)
    }

    /// Media keeps working while hidden.
    ///
    /// It has to: a track change cannot be announced by something that is not watching, and
    /// opening the notch should show the current track rather than an empty panel. Measured, the
    /// helper idles at 0% CPU and 18MB — which is the bar this opt-in has to clear.
    public var runsWhileHidden: Bool { true }

    private var attention: (any NotchAttention)?
    private var lastAnnouncedTrack: String?

    public func attach(attention: any NotchAttention) {
        self.attention = attention
    }

    public func setVisible(_ visible: Bool) {
        if visible {
            // Straight away, so the bar is already at the right place in the first frame rather
            // than up to half a second stale.
            now = Date()
            startTicking()
        } else {
            ticker?.cancel()
            ticker = nil
            dragFraction = nil
        }
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

    /// Advance `now` while playback does, so the scrubber moves between reports.
    ///
    /// Twice a second: the bar is a few hundred points wide against a track of a few minutes, so a
    /// second is roughly a point, and half-second steps are already finer than the display can
    /// show.
    ///
    /// Started from `setVisible` rather than `activate`, which is the whole reason that hook
    /// exists. This widget stays active behind a closed notch to catch track changes, and a clock
    /// tied to activation would tick there all day for a bar nobody is looking at.
    private func startTicking() {
        guard ticker == nil else { return }

        ticker = Task { [weak self] in
            while !Task.isCancelled {
                if self?.playing?.isPlaying == true { self?.now = Date() }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    public func deactivate() {
        // The ticker goes immediately, whatever the source does below: it exists to move something
        // on screen, and there is no screen now.
        ticker?.cancel()
        ticker = nil
        seekSettleTask?.cancel()
        seekSettleTask = nil
        dragFraction = nil
        pendingSeek = nil
        seekSentAt = nil

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

    /// Media announces, so it has a peek: the track that just started, and nothing else.
    public var peekBody: AnyView? {
        AnyView(
            MediaPeekView(widget: self, showsArtwork: showsArtwork, artworkSize: artworkSize - 12))
    }

    /// Peek when the track changes, but not for every update.
    ///
    /// Playback sends updates constantly — position, pause, shuffle — and peeking at each would be
    /// intolerable. Only a change of track counts, identified by title and artist rather than by
    /// object identity, since the same track arrives repeatedly as separate values.
    private func announceIfTrackChanged(from previous: NowPlaying?, to current: NowPlaying?) {
        guard let current, current.isPresentable else {
            lastAnnouncedTrack = nil
            return
        }

        let identity = "\(current.bundleIdentifier)|\(current.title ?? "")|\(current.artist ?? "")"
        guard identity != lastAnnouncedTrack else { return }

        let isFirstTrackSeen = lastAnnouncedTrack == nil
        lastAnnouncedTrack = identity

        // Do not peek at whatever happened to be playing when perch launched — that is not news,
        // and announcing it on every start would be obnoxious.
        guard !isFirstTrackSeen, previous != nil else { return }
        peekSnapshot = current
        attention?.requestPeek(from: self)
    }

    fileprivate func send(_ command: MediaCommand) {
        source?.send(command)
    }

    /// Work out which app the artwork should lead to, when the track changes hands.
    ///
    /// Guarded on the identifier rather than run unconditionally: updates arrive several times a
    /// second during playback and all but a handful name the same app, so this is a Launch Services
    /// query per *player*, not per update.
    private func resolvePlayer(for bundleIdentifier: String?) {
        guard let bundleIdentifier else {
            player = nil
            resolvedPlayerIdentifier = nil
            return
        }

        guard bundleIdentifier != resolvedPlayerIdentifier else { return }
        resolvedPlayerIdentifier = bundleIdentifier
        player = PlayerApp.resolve(bundleIdentifier: bundleIdentifier)
    }

    /// Go to the player: the one thing the panel deliberately does not try to do itself.
    fileprivate func openPlayer() {
        player?.open()
    }

    /// Ask the player to jump to a fraction of the way along the track.
    fileprivate func seek(toFraction fraction: Double) {
        guard let target = playing?.seekTarget(fraction: fraction) else { return }

        source?.seek(to: target)
        pendingSeek = target
        seekSentAt = Date()

        // A player that ignores the request, or one that has gone away, must not leave the bar
        // frozen at a position playback never reached.
        seekSettleTask?.cancel()
        seekSettleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.forgetPendingSeek()
        }
    }

    private func forgetPendingSeek() {
        pendingSeek = nil
        seekSentAt = nil
        seekSettleTask?.cancel()
        seekSettleTask = nil
    }

    /// What the scrubber should say, which is not always what the player last said.
    ///
    /// A drag outranks a pending seek, and a pending seek outranks the player: each is a more
    /// recent statement of where playback is meant to be than the one below it.
    fileprivate var displayedElapsed: TimeInterval? {
        if let dragFraction, let target = playing?.seekTarget(fraction: dragFraction) {
            return target
        }
        if let pendingSeek { return pendingSeek }
        return playing?.elapsed(at: now)
    }

    /// How far along to draw the bar, 0...1, or nil when there is no length to be a fraction of.
    fileprivate var displayedProgress: Double? {
        guard let duration = playing?.duration, duration > 0, let elapsed = displayedElapsed else {
            return nil
        }
        return min(1, max(0, elapsed / duration))
    }

    private func apply(_ update: NowPlaying?) async {
        let previous = playing
        playing = update
        resolvePlayer(for: update?.bundleIdentifier)

        // Hand the bar back to the player once it has answered. Updates already in flight when the
        // seek went out still carry the old position, so anything that arrives immediately is not
        // an answer — it is the question being overtaken.
        if let sentAt = seekSentAt, Date().timeIntervalSince(sentAt) > 0.35 {
            forgetPendingSeek()
        }

        announceIfTrackChanged(from: previous, to: update)

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

    /// Whether the pointer is on the artwork, which is the only thing that says it leads anywhere.
    ///
    /// The panel has no room for a label and nothing else on it is a link, so the affordance has to
    /// be the cover itself reacting. Nothing is drawn over it until then: a badge sitting on every
    /// album cover permanently is a worse trade than a second of discovery.
    @State private var pointerIsOverArtwork = false

    var body: some View {
        if let playing = widget.playing, playing.isPresentable {
            // A band, then the bar under it. The artwork sets the band's height, so the text and
            // the controls are free inside it — and the scrubber spanning the full width below
            // gets a drag target the width of the panel rather than of whatever is left over.
            //
            // Nothing here is sized by its content: the text column is the remainder after the
            // artwork and the controls, which are both fixed. A long title changes what the panel
            // says and never where anything on it sits.
            VStack(spacing: PanelMetrics.rowGap) {
                HStack(spacing: PanelMetrics.columnGap) {
                    if showsArtwork { artworkView }
                    details(for: playing)
                    Spacer(minLength: PanelMetrics.columnGap)
                    controls
                }

                Scrubber(widget: widget)
            }

        } else {
            Text("Nothing playing")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The album art, which is also the door to the player it came from.
    ///
    /// A button only when there is somewhere to go: an identifier nothing on this Mac claims leaves
    /// the cover as a picture, because a control that does nothing when pressed is worse than no
    /// control — it is indistinguishable from a broken one.
    @ViewBuilder
    private var artworkView: some View {
        if let player = widget.player {
            Button {
                widget.openPlayer()
            } label: {
                artworkImage
            }
            .buttonStyle(.plain)
            .onHover { pointerIsOverArtwork = $0 }
            .help("Open \(player.name)")
            .accessibilityLabel("Open \(player.name)")
            .accessibilityIdentifier(artworkIdentifier)

        } else {
            artworkImage
                .accessibilityIdentifier(artworkIdentifier)
        }
    }

    /// Kept as one identifier for both cases so a probe can tell decoded art from a placeholder
    /// whether or not the cover happens to lead anywhere.
    private var artworkIdentifier: String {
        widget.artwork == nil ? "media.artwork.missing" : "media.artwork"
    }

    private var artworkImage: some View {
        Group {
            if let artwork = widget.artwork {
                Image(nsImage: artwork).resizable()
            } else {
                // A neutral placeholder rather than nothing, so the row does not resize the
                // instant artwork finishes decoding.
                RoundedRectangle(cornerRadius: PanelMetrics.artworkRadius)
                    .fill(.white.opacity(0.08))
            }
        }
        .frame(width: artworkSize, height: artworkSize)
        // Inside the clip, not over it: an overlay applied after `clipShape` would draw its own
        // square corners past the cover's rounded ones.
        .overlay { openPlayerHint }
        .clipShape(
            RoundedRectangle(cornerRadius: PanelMetrics.artworkRadius, style: .continuous)
        )
    }

    /// What the cover turns into under the pointer.
    ///
    /// Dimmed with an arrow over it — the same shorthand the rest of the system uses for "this goes
    /// somewhere else". Sized against the artwork rather than fixed, since `media-artwork-size` is
    /// configurable and a 14pt glyph on a 24pt cover is a blot.
    private var openPlayerHint: some View {
        ZStack {
            Color.black.opacity(pointerIsOverArtwork ? 0.45 : 0)

            Image(systemName: "arrow.up.forward")
                .font(.system(size: artworkSize * 0.36, weight: .semibold))
                .foregroundStyle(.white)
                .opacity(pointerIsOverArtwork ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.12), value: pointerIsOverArtwork)
        // The button underneath owns the click; this is decoration and must not intercept it.
        .allowsHitTesting(false)
    }

    private func details(for playing: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: PanelMetrics.textGap) {
            Text(playing.title ?? "")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("media.title")

            if let subtitle = subtitle(for: playing) {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .accessibilityIdentifier("media.artist")
            }
        }
        // The column is the panel's remainder, claimed rather than requested: `Text` would
        // otherwise ask for its full natural width and squeeze the controls off the right edge on
        // exactly the long titles this is here to handle.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Artist, then album if there is one — the system's own second line.
    private func subtitle(for playing: NowPlaying) -> String? {
        let parts = [playing.artist, playing.album]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    private var controls: some View {
        // Wider spacing than the buttons need, so the one in the middle is the one under the
        // pointer. Mis-hitting `next` when reaching for `pause` costs you the track.
        HStack(spacing: PanelMetrics.controlGap) {
            button("backward.fill", .previousTrack, size: 14)
            button(
                widget.playing?.isPlaying == true ? "pause.fill" : "play.fill",
                .togglePlayPause,
                size: 18
            )
            button("forward.fill", .nextTrack, size: 14)
        }
    }

    private func button(_ symbol: String, _ command: MediaCommand, size: CGFloat) -> some View {
        Button {
            widget.send(command)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size))
                .foregroundStyle(.white.opacity(0.9))
                // The hit area is deliberately larger than the glyph: a 22pt target on a panel
                // that closes when the pointer leaves it is a target you have to aim at.
                .frame(width: PanelMetrics.control, height: PanelMetrics.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Identifiers are how `make ui-probe` finds and presses these without touching a pixel.
        .accessibilityIdentifier(command.accessibilityIdentifier)
    }
}

/// The progress bar, and the two ends of the track it is a progress through.
///
/// Draggable, so it is a control rather than a readout. Hidden entirely when the player reports no
/// duration — live streams, and anything a browser is playing — because a bar with no end can only
/// lie about where you are.
private struct Scrubber: View {

    let widget: MediaWidget

    /// Height of the drawn bar.
    ///
    /// The gesture takes a taller slice than this; see `track`.
    private let barHeight = PanelMetrics.bar

    var body: some View {
        if let progress = widget.displayedProgress, let duration = widget.playing?.duration {
            // Times flank the bar rather than sitting under it. Underneath they read better, but
            // they cost a whole row of a panel that has none to spare, and beside it they double
            // as the bar's end stops.
            HStack(spacing: PanelMetrics.rowGap) {
                Text(TimeCode.text(widget.displayedElapsed ?? 0))
                    .accessibilityIdentifier("media.elapsed")

                track(progress: progress, duration: duration)

                Text(TimeCode.text(duration))
                    .accessibilityIdentifier("media.duration")
            }
            // Monospaced digits: without them the elapsed side re-lays out on every tick, and a
            // number that changes width drags the bar's edge with it.
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func track(progress: Double, duration: TimeInterval) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(height: barHeight)

                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: max(barHeight, width * progress), height: barHeight)
            }
            .frame(height: proxy.size.height, alignment: .center)
            // The whole slice takes the gesture, not just the 4pt bar: pointing at a 4pt target
            // is a game, and the panel is not a game.
            .contentShape(Rectangle())
            .gesture(
                // Zero minimum distance so a click seeks too, which is what a click on any other
                // progress bar does.
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        widget.dragFraction = fraction(at: value.location.x, width: width)
                    }
                    .onEnded { value in
                        let target = fraction(at: value.location.x, width: width)
                        widget.dragFraction = nil
                        widget.seek(toFraction: target)
                    }
            )
        }
        .frame(height: PanelMetrics.scrubberRow)
        .accessibilityIdentifier("media.scrubber")
    }

    private func fraction(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return min(1, max(0, Double(x / width)))
    }
}

/// The compact form shown while the notch is announcing a track change.
private struct MediaPeekView: View {

    let widget: MediaWidget
    let showsArtwork: Bool
    let artworkSize: CGFloat

    var body: some View {
        let track = widget.peekSnapshot ?? widget.playing

        return HStack(spacing: PanelMetrics.columnGap) {
            if showsArtwork {
                // The space is reserved whether or not the image has decoded yet. Showing nothing
                // and then inserting it shoves the text sideways mid-announcement.
                Group {
                    if let artwork = widget.artwork {
                        Image(nsImage: artwork).resizable()
                    } else {
                        RoundedRectangle(cornerRadius: PanelMetrics.unit * 1.5)
                            .fill(.white.opacity(0.08))
                    }
                }
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(
                    RoundedRectangle(cornerRadius: PanelMetrics.unit * 1.5, style: .continuous))
            }

            VStack(alignment: .leading, spacing: PanelMetrics.textGap / 2) {
                Text(track?.title ?? "")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .accessibilityIdentifier("media.peek.title")

                if let artist = track?.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
