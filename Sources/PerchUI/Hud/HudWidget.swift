import Foundation
import PerchCore
import PerchSystem
import SwiftUI

/// Shows the output volume, replacing the macOS overlay.
///
/// macOS draws volume changes as a large square in the middle of whatever you were looking at.
/// This puts them in the notch instead, which is where your eyes already are when you press the
/// key and is the whole reason notch apps exist.
///
/// It is the second widget that ever announces anything, and the first that needed peeks to be
/// attributed — see ``AttributedAttention``. Before that, a volume change would have shown you the
/// current track, because `MediaWidget.peekBody` is non-nil whenever there is one.
@MainActor
@Observable
public final class HudWidget: NotchWidget {

    public static let kind = "hud"

    public static let summary = "Shows volume changes in the notch instead of on screen."

    public static let settings: [WidgetSetting] = [
        WidgetSetting(
            name: "take-keys", syntax: "true | false", defaultValue: "true",
            documentation: """
                Handle the volume keys directly, so macOS never draws its own overlay. Needs \
                Accessibility. Without it perch still shows the level, alongside the system \
                overlay rather than instead of it.
                """),
        WidgetSetting(
            name: "show-device", syntax: "true | false", defaultValue: "false",
            documentation: "Name the output device in the announcement, e.g. AirPods Pro."),
    ]

    public let placement: Placement = .expanded

    private let takesKeys: Bool
    private let showsDevice: Bool

    private var keyTap: VolumeKeyTap?

    /// Injectable so tests can drive the widget without a sound card.
    private var source: (any VolumeSource)?
    private var listener: Task<Void, Never>?
    private var attention: (any NotchAttention)?

    /// What was last read, whether or not it was worth announcing.
    private(set) var state: VolumeState?

    /// Whether an announcement is currently live.
    ///
    /// Gates `peekBody`, so this widget contributes to a peek only when it caused one. Media's is
    /// unconditional; this is the safer shape and the one a third announcing widget should copy.
    private var isAnnouncing = false

    public init(settings: WidgetSettings) throws {
        takesKeys = try settings.bool("take-keys", default: true)
        showsDevice = try settings.bool("show-device", default: false)
    }

    /// For tests: build against a supplied source, and never touch the real keyboard.
    init(source: any VolumeSource, showsDevice: Bool = false) {
        self.source = source
        self.takesKeys = false
        self.showsDevice = showsDevice
    }

    /// Keeps working while hidden, of necessity.
    ///
    /// A volume change cannot be announced by something that is not watching for it, and the notch
    /// is collapsed at the moment the key is pressed — which is every time.
    ///
    /// The cost of the promise this makes is two CoreAudio listener blocks. Nothing polls, nothing
    /// wakes on a timer, and no subprocess is spawned.
    public var runsWhileHidden: Bool { true }

    public func attach(attention: any NotchAttention) {
        self.attention = attention
    }

    public func activate() {
        guard listener == nil else { return }

        if takesKeys { startKeyTap() }

        let source = source ?? CoreAudioVolumeSource()
        self.source = source
        source.start()

        listener = Task { [weak self] in
            for await next in source.updates {
                guard let self else { return }
                self.receive(next)
            }
        }
    }

    public func deactivate() {
        listener?.cancel()
        listener = nil
        source?.stop()
        source = nil
        state = nil
        isAnnouncing = false
        announcementExpiry?.cancel()
        announcementExpiry = nil

        // The rule from CLAUDE.md: deactivate releases everything the widget owns. The volume keys
        // are owned here for as long as this widget is active, and a config reload that removes
        // `widget = hud` has to give them back — otherwise perch keeps swallowing them while no
        // longer showing anything, and the volume keys appear to be broken.
        keyTap?.stop()
        keyTap = nil
    }

    /// Take over the volume keys, if allowed to.
    ///
    /// Being denied is an ordinary outcome, not a failure: perch carries on watching the volume
    /// instead of owning it. The HUD still appears — the macOS overlay appears too, which is the
    /// thing the permission buys. Said once, at activation, rather than on every keypress.
    private func startKeyTap() {
        let tap = VolumeKeyTap()
        tap.onKey = { [weak self] key, fine in
            switch key {
            case .up: VolumeControl.adjust(by: .up, fine: fine)
            case .down: VolumeControl.adjust(by: .down, fine: fine)
            case .mute: VolumeControl.toggleMute()
            }
            // No announcement here. Changing the volume makes CoreAudio tell us, the same way it
            // would if the change came from anywhere else, and `receive` decides from there — so
            // there is exactly one path to an announcement rather than two that can disagree.
            _ = self
        }

        tap.onStarted = {
            Log.widget.info("hud: volume keys taken over; macOS will not draw its own overlay")
        }

        // Asks for Accessibility if it is missing, and takes the keys the moment it is granted —
        // no relaunch. Held either way: the tap keeps watching for the grant, and dropping it here
        // would mean the answer arrives with nobody listening.
        keyTap = tap
        tap.startAskingIfNeeded()
    }

    /// Take a reading, and decide whether it is worth interrupting anyone over.
    private func receive(_ next: VolumeState) {
        let announce = next.isAnnouncable(comparedTo: state)
        state = next

        guard announce else { return }
        isAnnouncing = true
        attention?.requestPeek()

        // Outlive the peek slightly. `peekBody` is read while the panel animates shut, and
        // dropping the content mid-collapse makes the notch appear to empty before it closes.
        announcementExpiry?.cancel()
        announcementExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.isAnnouncing = false
        }
    }

    private var announcementExpiry: Task<Void, Never>?

    public var body: AnyView {
        AnyView(HudWidgetView(widget: self, showsDevice: showsDevice, isPeek: false))
    }

    public var peekBody: AnyView? {
        guard isAnnouncing else { return nil }
        return AnyView(HudWidgetView(widget: self, showsDevice: showsDevice, isPeek: true))
    }
}
