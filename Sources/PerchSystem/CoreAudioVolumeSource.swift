import CoreAudio
import Foundation

/// Reads the output volume from CoreAudio.
///
/// All public API and no permissions — unlike now-playing, which needs an entitled helper. The
/// only real subtlety is that the *device* can change underneath us: plugging in AirPods swaps the
/// default output, and listeners registered against the old device stop firing. So there are two
/// layers of listener, one on the system for "which device is default" and one on whichever device
/// that currently is.
public final class CoreAudioVolumeSource: VolumeSource, @unchecked Sendable {

    public let updates: AsyncStream<VolumeState>
    private let continuation: AsyncStream<VolumeState>.Continuation

    /// Serialises listener registration against the callbacks CoreAudio makes on its own threads.
    private let lock = NSLock()

    private var isRunning = false
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] =
        []
    private var systemListener: AudioObjectPropertyListenerBlock?

    public init() {
        (updates, continuation) = AsyncStream.makeStream(of: VolumeState.self)
    }

    deinit { stop() }

    public func start() {
        lock.lock()
        guard !isRunning else { return lock.unlock() }
        isRunning = true
        lock.unlock()

        observeDefaultDeviceChanges()
        rebindToDefaultDevice()
    }

    public func stop() {
        lock.lock()
        guard isRunning else { return lock.unlock() }
        isRunning = false
        lock.unlock()

        unbindDevice()

        if let systemListener {
            var address = Self.defaultOutputDeviceAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, nil, systemListener)
            self.systemListener = nil
        }

        continuation.finish()
    }

    // MARK: - Listeners

    /// Notice when the user switches output, so the volume keys keep tracking the right device.
    private func observeDefaultDeviceChanges() {
        var address = Self.defaultOutputDeviceAddress
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.rebindToDefaultDevice()
        }
        systemListener = listener
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, nil, listener)
    }

    /// Point the volume and mute listeners at whatever the default output device is now.
    private func rebindToDefaultDevice() {
        unbindDevice()

        guard let current = Self.defaultOutputDevice() else { return }

        lock.lock()
        device = current
        lock.unlock()

        for address in Self.deviceAddresses {
            var address = address
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.emit()
            }
            if AudioObjectAddPropertyListenerBlock(current, &address, nil, listener) == noErr {
                lock.lock()
                deviceListeners.append((address, listener))
                lock.unlock()
            }
        }

        emit()
    }

    private func unbindDevice() {
        lock.lock()
        let listeners = deviceListeners
        let current = device
        deviceListeners = []
        device = AudioObjectID(kAudioObjectUnknown)
        lock.unlock()

        guard current != AudioObjectID(kAudioObjectUnknown) else { return }
        for (address, listener) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(current, &address, nil, listener)
        }
    }

    private func emit() {
        lock.lock()
        let current = device
        let running = isRunning
        lock.unlock()

        guard running, current != AudioObjectID(kAudioObjectUnknown) else { return }
        continuation.yield(
            VolumeState(
                level: Self.level(of: current),
                isMuted: Self.isMuted(current),
                deviceName: Self.name(of: current)
            )
        )
    }

    // MARK: - Reading CoreAudio

    private static let defaultOutputDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    /// Volume and mute, both on the output scope.
    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    private static var deviceAddresses: [AudioObjectPropertyAddress] {
        [volumeAddress, muteAddress]
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = defaultOutputDeviceAddress
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)

        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }

    /// The output level, preferring the device's main element.
    ///
    /// Not every device implements a main-element volume — some only expose per-channel scalars,
    /// and reading the main element on those fails rather than returning zero. Falling back to the
    /// first two channels covers them; a device with neither reports 0, which draws as silent
    /// rather than as a crash.
    private static func level(of device: AudioObjectID) -> Double {
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

    private static func isMuted(_ device: AudioObjectID) -> Bool {
        var address = muteAddress
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)

        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    private static func name(of device: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        // `Unmanaged`, not a bare `CFString`: CoreAudio writes a +1 reference into this buffer, and
        // taking a raw pointer to a managed reference is both unsound and a warning-as-error here.
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { return "" }
        return name.takeRetainedValue() as String
    }
}
