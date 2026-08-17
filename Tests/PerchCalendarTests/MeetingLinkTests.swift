import Foundation
import Testing

@testable import PerchCalendar

/// Finding the link you would actually click.
///
/// The rule under test is the restrictive half: a join button that opens a spreadsheet is worse than
/// no join button, because it is indistinguishable from a broken one.
@Suite("Meeting links")
struct MeetingLinkTests {

    @Test("The event's own URL is used when it is a meeting")
    func urlFieldWins() {
        let url = URL(string: "https://acme.zoom.us/j/123456789")

        let found = MeetingLink.find(
            url: url, location: "https://meet.google.com/abc-defg-hij", notes: nil)

        #expect(found == url)
    }

    @Test("A corporate subdomain still counts")
    func subdomainsMatch() {
        // Every company's Zoom lives on its own subdomain, so a list of exact hosts would match
        // almost nobody's actual meetings.
        #expect(
            MeetingLink.isMeeting(
                URL(string: "https://acme.zoom.us/j/1") ?? .init(fileURLWithPath: "/")))
        #expect(
            MeetingLink.isMeeting(URL(string: "https://zoom.us/j/1") ?? .init(fileURLWithPath: "/"))
        )
    }

    @Test("A host that merely ends in the same letters does not")
    func lookalikeHostsDoNotMatch() {
        let impostor = URL(string: "https://notzoom.us/j/1") ?? .init(fileURLWithPath: "/")

        #expect(!MeetingLink.isMeeting(impostor))
    }

    @Test("A link in the location is found")
    func locationIsSearched() {
        let found = MeetingLink.find(
            url: nil, location: "https://meet.google.com/abc-defg-hij", notes: nil)

        #expect(found?.host() == "meet.google.com")
    }

    @Test("A link buried in the notes is found")
    func notesAreSearched() {
        // Where most invitations actually put it, wrapped in a paragraph of dial-in numbers.
        let notes = """
            Hi all — agenda attached.

            Join Zoom Meeting: https://acme.zoom.us/j/987654321?pwd=abc
            One tap mobile: +14155551212
            """

        #expect(
            MeetingLink.find(url: nil, location: "Room 4", notes: notes)?.host() == "acme.zoom.us")
    }

    @Test("A link that is not a meeting is not offered")
    func documentsAreNotMeetings() {
        let doc = URL(string: "https://docs.google.com/document/d/1")

        #expect(MeetingLink.find(url: doc, location: "Room 4", notes: "see the doc") == nil)
    }

    @Test("An event with nothing to join has nothing to press")
    func nothingIsFoundInNothing() {
        #expect(MeetingLink.find(url: nil, location: nil, notes: nil) == nil)
        #expect(MeetingLink.find(url: nil, location: "", notes: "") == nil)
    }
}
