import PerchAgents
import PerchCore
import SwiftUI

/// Shows running Claude Code sessions, and announces when one finishes or needs you.
@MainActor
@Observable
public final class ClaudeWidget: NotchWidget {

    public static let kind = "claude"

    public static let summary = "Shows running Claude Code sessions, and announces when one stops."

    public static let settings: [WidgetSetting] = [
        WidgetSetting(
            name: "placement", syntax: "leading | trailing | expanded", defaultValue: "trailing",
            documentation: "Where the widget draws. The strips need collapsed-bleed to have room."),
        WidgetSetting(
            name: "announce", syntax: "all | finished | waiting | never", defaultValue: "all",
            documentation:
                "Which changes make the notch announce: a session finishing, one blocking on you,"
                + " both, or neither."),
        WidgetSetting(
            name: "idle", syntax: "true | false", defaultValue: "true",
            documentation: "Show a dot for sessions that are sitting at the prompt."),
        WidgetSetting(
            name: "limit", syntax: "count", defaultValue: "5",
            documentation: "How many dots to draw before collapsing the rest into a count."),
    ]

    public let placement: Placement

    private let showsIdle: Bool
    private let limit: Int
    private let announcePolicy: AgentAnnouncePolicy

    private var source: (any AgentSessionSource)?
    private var listener: Task<Void, Never>?
    private var monitor: AgentSessionMonitor

    private var attention: (any NotchAttention)?

    /// Every live session, oldest first.
    fileprivate private(set) var sessions: [AgentSession] = []

    /// What the current announcement is about.
    ///
    /// Frozen for the length of the peek rather than read live, for the same reason the media
    /// widget freezes a track: the session it names carries on changing — a finished session is
    /// very often given more work a second later — and a peek that rewrites itself while you are
    /// reading it has told you nothing.
    fileprivate private(set) var announcement: AgentAnnouncement?

    public init(settings: WidgetSettings) throws {
        placement = try settings.enumeration("placement", default: .trailing)
        showsIdle = try settings.bool("idle", default: true)
        announcePolicy = try settings.enumeration("announce", default: .all)
        limit = try Self.limit(from: settings)
        monitor = AgentSessionMonitor(policy: announcePolicy)
    }

    private static func limit(from settings: WidgetSettings) throws -> Int {
        let raw = try settings.length("limit", default: 5)
        guard raw >= 1 else {
            throw ConfigValueError("claude-limit: expected a count of at least 1")
        }
        return Int(raw)
    }

    /// Claude keeps working while hidden.
    ///
    /// It has to: a session finishing while the notch is collapsed is the entire feature, and
    /// nothing can announce a change it was not watching for. The cost this opt-in promises is
    /// genuinely negligible — a handful of `kqueue` descriptors, woken by the kernel when a session
    /// file changes and costing nothing between times. There is no timer and no polling.
    public var runsWhileHidden: Bool { true }

    public func attach(attention: any NotchAttention) {
        self.attention = attention
    }

    public func activate() {
        guard listener == nil else { return }

        // Rebuilt rather than resumed, which resets its baseline so the first snapshot after waking
        // announces nothing. Otherwise opening the lid would replay every session that finished
        // while the display was asleep — a queue of announcements about work that is long over.
        monitor = AgentSessionMonitor(policy: announcePolicy)

        let source = source ?? ClaudeSessionSource()
        self.source = source
        source.start()

        listener = Task { [weak self] in
            for await sessions in source.updates {
                guard !Task.isCancelled else { return }
                self?.apply(sessions)
            }
        }
    }

    public func deactivate() {
        listener?.cancel()
        listener = nil
        source?.stop()
        source = nil
        announcement = nil

        // Unlike media there is no lingering: restarting costs one directory read, and there is no
        // subprocess to keep warm.
    }

    public var body: AnyView {
        switch placement {
        case .leading, .trailing: AnyView(ClaudeStripView(widget: self, limit: limit))
        case .expanded: AnyView(ClaudePanelView(widget: self))
        }
    }

    public var peekBody: AnyView {
        AnyView(ClaudePeekView(widget: self))
    }

    /// Sessions worth drawing a dot for.
    fileprivate var visibleSessions: [AgentSession] {
        showsIdle ? sessions : sessions.filter { $0.status != .idle }
    }

    private func apply(_ sessions: [AgentSession]) {
        self.sessions = sessions

        guard let next = monitor.observe(sessions).first else { return }
        announcement = next
        attention?.requestPeek(from: self)
    }

    /// Swap in a different source.
    ///
    /// Tests only, so a widget can be driven without a real session directory.
    func use(source: any AgentSessionSource) {
        self.source = source
    }
}

// MARK: - Appearance

extension AgentStatus {

    /// The dot's fill, or `nil` for an outline.
    fileprivate var fill: Color? {
        switch self {
        case .busy, .shell: .white.opacity(0.9)
        case .waiting: Color(red: 1.0, green: 0.72, blue: 0.25)
        case .idle, .unknown: nil
        }
    }

    fileprivate var stroke: Color {
        switch self {
        case .busy, .shell: .clear
        case .waiting: Color(red: 1.0, green: 0.72, blue: 0.25).opacity(0.45)
        case .idle: .white.opacity(0.35)
        case .unknown: .white.opacity(0.18)
        }
    }

    /// How the status reads in a sentence.
    fileprivate var phrase: String {
        switch self {
        case .busy: "working"
        case .shell: "running a command"
        case .waiting: "waiting on you"
        case .idle: "done"
        case .unknown: "—"
        }
    }
}

/// One session, as a dot.
///
/// Fill carries "is it doing something", the halo carries "is it blocked on you". Colour alone
/// would have been enough to tell busy from waiting on most displays and no use at all on the rest,
/// so the two states differ in shape as well as hue.
private struct SessionDot: View {

    let session: AgentSession

    private let diameter: CGFloat = 6

    var body: some View {
        ZStack {
            if session.status == .waiting {
                Circle()
                    .stroke(session.status.stroke, lineWidth: 1)
                    .frame(width: diameter + 4, height: diameter + 4)
            }

            Circle()
                .fill(session.status.fill ?? .clear)
                .overlay(
                    Circle().stroke(
                        session.status.fill == nil ? session.status.stroke : .clear, lineWidth: 1)
                )
                .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter + 4, height: diameter + 4)
        // Made an element explicitly. A `Circle` carries no text, so without this it is decoration
        // as far as the accessibility tree is concerned and `ui-probe` has nothing to assert on —
        // which would leave the one thing that is always on screen the one thing never checked.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("claude.dot.\(session.status.rawValue)")
        .accessibilityLabel(Text("\(session.label) \(session.status.phrase)"))
    }
}

/// The collapsed strip: one dot per session.
///
/// Deliberately still. A pulsing dot would read well and would also repaint the notch continuously
/// for as long as anything was running, which is the one thing perch promises not to do.
private struct ClaudeStripView: View {

    let widget: ClaudeWidget
    let limit: Int

    var body: some View {
        let sessions = widget.visibleSessions
        let shown = sessions.prefix(limit)
        let hidden = sessions.count - shown.count

        return HStack(spacing: 1) {
            ForEach(shown) { SessionDot(session: $0) }

            if hidden > 0 {
                Text("+\(hidden)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("claude.sessions")
        .accessibilityLabel(Text(summary(of: sessions)))
    }

    /// What the row of dots would say if it could talk, for the accessibility tree and `ui-probe`.
    private func summary(of sessions: [AgentSession]) -> String {
        guard !sessions.isEmpty else { return "no sessions" }

        let working = sessions.filter(\.status.isWorking).count
        let waiting = sessions.filter { $0.status == .waiting }.count
        let done = sessions.count - working - waiting

        return [
            working > 0 ? "\(working) working" : nil,
            waiting > 0 ? "\(waiting) waiting" : nil,
            done > 0 ? "\(done) done" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

/// The open panel: every session, named.
private struct ClaudePanelView: View {

    let widget: ClaudeWidget

    var body: some View {
        let sessions = widget.visibleSessions

        return Group {
            if sessions.isEmpty {
                Text("No sessions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sessions) { row(for: $0) }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
        }
        .accessibilityIdentifier("claude.panel")
    }

    private func row(for session: AgentSession) -> some View {
        HStack(spacing: 8) {
            SessionDot(session: session)

            Text(session.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(session.waitingFor ?? session.status.phrase)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .accessibilityIdentifier("claude.session.\(session.id)")
    }
}

/// The announcement: one session, one line about what it did.
private struct ClaudePeekView: View {

    let widget: ClaudeWidget

    var body: some View {
        HStack(spacing: 10) {
            if let announcement = widget.announcement {
                Image(systemName: symbol(for: announcement.kind))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint(for: announcement.kind))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(announcement.session.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .accessibilityIdentifier("claude.peek.label")

                    Text(detail(for: announcement))
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .accessibilityIdentifier("claude.peek.detail")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private func symbol(for kind: AgentAnnouncement.Kind) -> String {
        switch kind {
        case .finished: "checkmark.circle.fill"
        case .needsYou: "exclamationmark.circle.fill"
        }
    }

    private func tint(for kind: AgentAnnouncement.Kind) -> Color {
        switch kind {
        case .finished: .white.opacity(0.85)
        case .needsYou: Color(red: 1.0, green: 0.72, blue: 0.25)
        }
    }

    private func detail(for announcement: AgentAnnouncement) -> String {
        switch announcement.kind {
        case .finished:
            // The directory, not the word "finished" — the label already says which session, and
            // where it was working is the thing you need in order to go and look at it.
            announcement.session.directory.map(abbreviate) ?? "finished"
        case .needsYou:
            announcement.session.waitingFor ?? "needs you"
        }
    }

    /// A path with the home directory abbreviated.
    private func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
