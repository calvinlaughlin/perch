import Foundation

/// Finds the link you would actually click at one minute to the hour.
///
/// An invitation carries its meeting link in whichever field the sender's software felt like using:
/// the event's own URL, the location, or somewhere in the notes. All three are searched, in that
/// order of trustworthiness.
///
/// **Only recognised hosts count.** An event whose URL is a ticket page or a shared document is not
/// something to join, and offering a join button that opens a spreadsheet is worse than offering
/// nothing — it is indistinguishable from a broken one, which is the same rule that leaves media's
/// artwork as a picture when nothing can open it.
public enum MeetingLink {

    /// Hosts that mean "a meeting happens here", matched on the host's suffix.
    ///
    /// Suffix rather than equality: video services put the tenant in front of the domain
    /// (`acme.zoom.us`), and a list of exact hosts would miss every corporate account.
    private static let hosts = [
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
        "webex.com",
        "whereby.com",
        "bluejeans.com",
        "gotomeeting.com",
        "chime.aws",
        "meet.jit.si",
        "around.co",
        "pop.com",
        "tuple.app",
    ]

    /// The link to join, or nil if none of these fields hold one.
    public static func find(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isMeeting(url) { return url }

        for text in [location, notes] {
            guard let text, !text.isEmpty else { continue }
            if let found = firstMeetingURL(in: text) { return found }
        }
        return nil
    }

    /// Whether a URL points at somewhere you join a meeting.
    public static func isMeeting(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    /// The first meeting link in a block of text.
    ///
    /// Uses the system's link detector rather than a hand-written pattern: invitation notes are
    /// full of URLs wrapped by mail clients, followed by punctuation, or written without a scheme,
    /// and matching those correctly is exactly the job `NSDataDetector` already does.
    private static func firstMeetingURL(in text: String) -> URL? {
        guard
            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var found: URL?

        detector.enumerateMatches(in: text, range: range) { match, _, stop in
            guard let url = match?.url, isMeeting(url) else { return }
            found = url
            stop.pointee = true
        }

        return found
    }
}
