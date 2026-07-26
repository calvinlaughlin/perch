import Foundation
import PerchCore

/// Turns the adapter's JSON-lines output into `NowPlaying` values.
///
/// The adapter emits one JSON object per line. Some carry a complete payload; others set
/// `diff: true` and carry only the fields that changed, which is how a pause or a seek arrives
/// without re-sending several hundred kilobytes of artwork. Merging those into the last known
/// state is this type's job, and it is why the decoder is stateful.
///
/// Nothing here talks to a process, so the whole protocol can be tested against recorded output.
public struct MediaStreamDecoder: Sendable {

    /// The most recent complete picture, or nil before anything has arrived.
    public private(set) var current: NowPlaying?

    public init() {}

    /// What a decoded line meant.
    public enum Event: Equatable, Sendable {
        /// Playback state changed.
        case updated(NowPlaying)

        /// Nothing is playing any more, or nothing ever was.
        case cleared

        /// The line was understood but changed nothing worth redrawing for.
        case unchanged

        /// The line could not be understood. Reported rather than thrown: one malformed line
        /// must not tear down a stream that is otherwise fine.
        case malformed(String)
    }

    /// Decode one line.
    public mutating func decode(line: String) -> Event {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unchanged }

        guard
            let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .malformed("not JSON: \(trimmed.prefix(120))")
        }

        guard let payload = object["payload"] as? [String: Any] else {
            return .malformed("no payload: \(trimmed.prefix(120))")
        }

        // An empty payload is the adapter saying nothing is playing. It arrives as the first line
        // of every stream, before any player has been found.
        if payload.isEmpty {
            let wasPlaying = current != nil
            current = nil
            return wasPlaying ? .cleared : .unchanged
        }

        let isDiff = object["diff"] as? Bool ?? false
        let base = isDiff ? current : nil

        guard let updated = Self.merge(payload, into: base) else {
            return .malformed("payload has no bundleIdentifier and no prior state to merge into")
        }

        guard updated != current else { return .unchanged }
        current = updated
        return .updated(updated)
    }

    /// Apply a payload on top of whatever we already knew.
    ///
    /// - Parameters:
    ///   - payload: the fields this line carried.
    ///   - base: the previous state for a diff, or nil for a full payload.
    /// - Returns: the merged state, or nil if the payload names no app and there is none to
    ///   inherit.
    private static func merge(_ payload: [String: Any], into base: NowPlaying?) -> NowPlaying? {
        guard
            let bundleIdentifier = payload["bundleIdentifier"] as? String ?? base?.bundleIdentifier
        else { return nil }

        // A diff for a *different* app is not a diff at all — the player changed, and carrying the
        // old track's artwork and title forward would show one app's metadata under another's name.
        let previous = base?.bundleIdentifier == bundleIdentifier ? base : nil

        func string(_ key: String, _ fallback: String?) -> String? {
            payload[key] as? String ?? fallback
        }
        func number(_ key: String, _ fallback: TimeInterval?) -> TimeInterval? {
            (payload[key] as? NSNumber)?.doubleValue ?? fallback
        }

        var artworkData = previous?.artworkData
        if let encoded = payload["artworkData"] as? String {
            artworkData = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
        }

        return NowPlaying(
            bundleIdentifier: bundleIdentifier,
            title: string("title", previous?.title),
            artist: string("artist", previous?.artist),
            album: string("album", previous?.album),
            isPlaying: payload["playing"] as? Bool ?? previous?.isPlaying ?? false,
            duration: number("duration", previous?.duration),
            elapsedTime: number("elapsedTime", previous?.elapsedTime),
            timestamp: Self.date(payload["timestamp"]) ?? previous?.timestamp,
            artworkData: artworkData,
            artworkMimeType: string("artworkMimeType", previous?.artworkMimeType)
        )
    }

    /// The adapter writes ISO-8601 with a `Z` suffix.
    ///
    /// Uses `ISO8601FormatStyle` rather than `ISO8601DateFormatter`: the latter is a class and not
    /// `Sendable`, so a shared static of one will not compile under Swift 6 strict concurrency —
    /// and creating one per line, for a type this hot, is not the answer either.
    ///
    /// Both precisions are tried because some players report sub-second timestamps and a parser
    /// configured for one rejects the other outright.
    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return (try? whole.parse(text)) ?? (try? fractional.parse(text))
    }

    private static let whole = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
}
