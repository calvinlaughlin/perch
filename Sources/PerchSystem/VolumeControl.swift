import CoreAudio
import Foundation

/// Changes the output volume.
///
/// Needed because perch's HUD works by *taking over* the volume keys rather than watching them:
/// the key is consumed before macOS sees it, so macOS never draws its overlay — and never applies
/// the change either. Whoever swallows the key inherits the job of doing what it asked for.
public enum VolumeControl {

    /// One press of a volume key.
    ///
    /// macOS moves in sixteenths. Matching that matters more than it sounds: a HUD that moved in
    /// different steps to the rest of the system would disagree with every other volume readout
    /// on the machine, including the menu bar's.
    public static let step = 1.0 / 16.0

    /// The finer step macOS uses when Shift and Option are held.
    public static let fineStep = 1.0 / 64.0

    /// Raise or lower the default output device by one step.
    ///
    /// - Parameters:
    ///   - direction: which way to move.
    ///   - fine: use the quarter-sized step, for Shift-Option.
    /// - Returns: the level actually set, or nil if there is no controllable device.
    @discardableResult
    public static func adjust(by direction: Direction, fine: Bool = false) -> Double? {
        guard let device = defaultOutputDevice() else { return nil }

        // Unmuting is part of turning it up. Pressing volume-up on a muted Mac makes sound come
        // out; it does not raise a level you still cannot hear.
        if direction == .up, isMuted(device) { setMuted(false, on: device) }

        let delta = (fine ? fineStep : step) * (direction == .up ? 1 : -1)
        let target = min(max(currentLevel(device) + delta, 0), 1)

        setLevel(target, on: device)
        return target
    }

    /// Flip the mute state of the default output device.
    ///
    /// - Returns: whether it is now muted, or nil if there is no controllable device.
    @discardableResult
    public static func toggleMute() -> Bool? {
        guard let device = defaultOutputDevice() else { return nil }
        let next = !isMuted(device)
        setMuted(next, on: device)
        return next
    }

    public enum Direction: Sendable { case up, down }

    // MARK: - CoreAudio

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }

    private static func currentLevel(_ device: AudioObjectID) -> Double {
        var address = volumeAddress
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)

        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
            return Double(value)
        }

        var channels: [Double] = []
        for channel in UInt32(1)...2 {
            var channelAddress = volumeAddress
            channelAddress.mElement = channel
            var channelValue = Float32(0)
            var channelSize = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(
                device, &channelAddress, 0, nil, &channelSize, &channelValue) == noErr
            {
                channels.append(Double(channelValue))
            }
        }
        guard !channels.isEmpty else { return 0 }
        return channels.reduce(0, +) / Double(channels.count)
    }

    /// Set the level, falling back to per-channel on devices with no main element.
    private static func setLevel(_ level: Double, on device: AudioObjectID) {
        var address = volumeAddress
        var value = Float32(level)
        let size = UInt32(MemoryLayout<Float32>.size)

        if AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr { return }

        for channel in UInt32(1)...2 {
            var channelAddress = volumeAddress
            channelAddress.mElement = channel
            var channelValue = Float32(level)
            AudioObjectSetPropertyData(device, &channelAddress, 0, nil, size, &channelValue)
        }
    }

    private static func isMuted(_ device: AudioObjectID) -> Bool {
        var address = muteAddress
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    private static func setMuted(_ muted: Bool, on device: AudioObjectID) {
        var address = muteAddress
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}
