import PerchCore
import Testing

@testable import PerchUI

@Suite("An endless deck of cards")
struct DeckTests {

    @Test("Slots map onto the widgets in order")
    func slotsMapInOrder() {
        #expect(NotchModel.card(at: 0, of: 3) == 0)
        #expect(NotchModel.card(at: 1, of: 3) == 1)
        #expect(NotchModel.card(at: 2, of: 3) == 2)
    }

    @Test("Past the last card comes the first, going on downwards")
    func repeatsForever() {
        // The point of the whole thing: slot 3 is the first widget again, reached by carrying on
        // rather than by turning round.
        #expect(NotchModel.card(at: 3, of: 3) == 0)
        #expect(NotchModel.card(at: 4, of: 3) == 1)
        #expect(NotchModel.card(at: 30, of: 3) == 0)
    }

    @Test("Slots above where the deck started are the last cards")
    func negativeSlotsWrapBackwards() {
        // The one a single `%` gets wrong. Swift's remainder keeps the sign of its left operand, so
        // this would be -1 — and unlike the old bounded version, nothing clamps it any more. It goes
        // straight into the array and traps, one scroll up from where the panel opens.
        #expect(NotchModel.card(at: -1, of: 3) == 2)
        #expect(NotchModel.card(at: -2, of: 3) == 1)
        #expect(NotchModel.card(at: -3, of: 3) == 0)
        #expect(NotchModel.card(at: -30, of: 3) == 0)
    }

    @Test("Every slot lands inside the widget list", arguments: [1, 2, 3, 4, 7])
    func alwaysInRange(count: Int) {
        for slot in -50...50 {
            let card = NotchModel.card(at: slot, of: count)
            #expect(card >= 0 && card < count)
        }
    }

    @Test("A deck of one card is always that card")
    func singleCard() {
        #expect(NotchModel.card(at: 5, of: 1) == 0)
        #expect(NotchModel.card(at: -5, of: 1) == 0)
    }

    @Test("An empty deck does not divide by zero")
    func toleratesNoCards() {
        // Note what this does *not* say. Zero is the only answer available for a deck with no
        // cards, and it is a valid array index for every deck except that one — which is why
        // nothing may map slots through here without first knowing there is a card to find.
        #expect(NotchModel.card(at: 3, of: 0) == 0)
    }
}

@Suite("Which cards are on screen")
struct DeckWindowTests {

    @Test("Nothing to deal means no slots")
    func emptyDeckDealsNothing() {
        // The regression this suite exists for. A config naming only widgets that do not exist
        // leaves the expanded panel with none, and the deck used to ask for the card at each slot
        // anyway — getting 0 back and reading it out of an empty array, which is a trap, which is
        // the whole app gone. An empty deck offers no slot to fill.
        #expect(NotchModel.window(around: 0, of: 0).isEmpty)
        #expect(NotchModel.window(around: -7, of: 0).isEmpty)
    }

    @Test("Every slot offered names a card that exists", arguments: [1, 2, 3, 5])
    func slotsAreAlwaysSafeToIndex(count: Int) {
        for slot in -20...20 {
            for offered in NotchModel.window(around: slot, of: count) {
                #expect(offered.card >= 0 && offered.card < count)
            }
        }
    }

    @Test("The card either side is built before it is needed")
    func buildsTheNeighbours() {
        // Three slots, centred on the one facing the reader. Building only the current card leaves
        // the space it slides into empty for the whole movement.
        let window = NotchModel.window(around: 4, of: 3)

        #expect(window.map(\.offset) == [3, 4, 5])
        #expect(window.map(\.card) == [0, 1, 2])
    }

    @Test("Slots keep their own identity as the deck moves")
    func slotIsIdentifiedByPosition() {
        // Identity is the position in the run, not the widget on it. Keyed by widget instead,
        // SwiftUI would see the card leaving one end reappear at the other and animate it
        // travelling right across the panel to get there.
        #expect(NotchModel.window(around: 0, of: 2).map(\.id) == [-1, 0, 1])
    }
}

@Suite("Where scrolling stops")
struct ExpandedScrollTests {

    @Test("Endless is the default")
    func endlessByDefault() {
        // A panel showing one widget at a time cannot afford a dead scroll: being refused at an end
        // looks identical to being broken, because nothing on screen says there is an end there.
        #expect(Config().expandedScroll == .endless)
    }

    @Test("Both behaviours are reachable from the config file")
    func bothParse() {
        #expect(
            ConfigLoader.load(source: "expanded-scroll = rewind").config.expandedScroll == .rewind)
        #expect(
            ConfigLoader.load(source: "expanded-scroll = endless").config.expandedScroll == .endless
        )
    }

    @Test("A misspelling is a warning, not a failure")
    func badValueIsADiagnostic() {
        let result = ConfigLoader.load(source: "expanded-scroll = wibble")

        #expect(result.config.expandedScroll == .endless)
        #expect(result.diagnostics.count == 1)
    }

    @Test("Rewind folds the index back into the widget list")
    func rewindStaysInRange() {
        // What the controller does for `rewind`: the index is a choice among the widgets, so it has
        // to land on one. Endless does not call this at all — its index runs free.
        for start in 0..<3 {
            for step in [-1, 1] {
                let next = NotchModel.card(at: start + step, of: 3)
                #expect(next >= 0 && next < 3)
            }
        }
        #expect(NotchModel.card(at: 3, of: 3) == 0)
        #expect(NotchModel.card(at: -1, of: 3) == 2)
    }
}
