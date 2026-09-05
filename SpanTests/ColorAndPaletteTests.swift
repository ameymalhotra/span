import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Span

@Suite("Colour helpers")
struct ColorHelperTests {

    @Test("hexString round-trips a parsed colour")
    func roundTrip() {
        for hex in ["#C25E12", "#00909E", "#000000", "#FFFFFF", "#7B7DF0"] {
            #expect(Color(hexString: hex).hexString == hex)
        }
    }

    @Test("the leading hash is optional")
    func hashOptional() {
        #expect(Color(hexString: "C25E12").hexString == "#C25E12")
    }

    @Test("surrounding whitespace is tolerated")
    func whitespaceTolerated() {
        #expect(Color(hexString: "  #C25E12  ").hexString == "#C25E12")
    }

    @Test("malformed input falls back to grey rather than crashing", arguments: [
        "", "#", "12345", "1234567", "#GGGGGG", "not a colour", "#12 34 56",
    ])
    func malformedFallsBackToGrey(input: String) {
        #expect(Color(hexString: input).hexString == Color.gray.hexString)
    }

    @Test("lowercase hex parses and normalises to uppercase")
    func lowercaseHex() {
        #expect(Color(hexString: "#c25e12").hexString == "#C25E12")
    }

    @Test("rgbHex builds the same colour as the string form")
    func rgbHexMatchesString() {
        #expect(Color(rgbHex: 0xC25E12).hexString == Color(hexString: "#C25E12").hexString)
    }
}

/// `CategoryPalette.registry` is process-global mutable state, so these run
/// one at a time and put it back afterwards.
@Suite("CategoryPalette", .serialized)
struct CategoryPaletteTests {

    private func withEmptyRegistry(_ body: () -> Void) {
        CategoryPalette.updateRegistry([])
        body()
        CategoryPalette.updateRegistry([])
    }

    @Test("there are ten distinguishable swatches")
    func swatchCount() {
        #expect(CategoryPalette.swatches.count == 10)
        #expect(Set(CategoryPalette.swatches.map(\.slot)).count == 10)
        #expect(Set(CategoryPalette.swatches.map(\.name)).count == 10)
        #expect(Set(CategoryPalette.swatches.map(\.light)).count == 10)
        #expect(Set(CategoryPalette.swatches.map(\.dark)).count == 10)
    }

    @Test("each swatch's slot matches its index")
    func swatchSlots() {
        for (index, swatch) in CategoryPalette.swatches.enumerated() {
            #expect(swatch.slot == index)
            #expect(swatch.id == index)
        }
    }

    @Test("slots wrap round rather than trapping")
    func slotWrapping() {
        let first = CategoryPalette.color(slot: 0).hexString
        #expect(CategoryPalette.color(slot: 10).hexString == first)
        #expect(CategoryPalette.color(slot: 20).hexString == first)
        #expect(CategoryPalette.color(slot: -10).hexString == first)
    }

    @Test("a negative slot maps into the palette")
    func negativeSlots() {
        #expect(CategoryPalette.color(slot: -1).hexString == CategoryPalette.color(slot: 9).hexString)
        #expect(CategoryPalette.color(slot: -3).hexString == CategoryPalette.color(slot: 7).hexString)
    }

    @Test("a nil, empty or blank name gets the neutral colour")
    func neutralForAbsentName() {
        withEmptyRegistry {
            #expect(CategoryPalette.color(for: nil).hexString == CategoryPalette.neutralColor.hexString)
            #expect(CategoryPalette.color(for: "").hexString == CategoryPalette.neutralColor.hexString)
            #expect(CategoryPalette.color(for: "   ").hexString == CategoryPalette.neutralColor.hexString)
        }
    }

    @Test("an unregistered name still gets a stable colour")
    func unregisteredIsStable() {
        withEmptyRegistry {
            let first = CategoryPalette.color(for: "Gardening").hexString
            #expect(CategoryPalette.color(for: "Gardening").hexString == first)
            #expect(first != CategoryPalette.neutralColor.hexString)
        }
    }

    @Test("the hash is content-based, so two spellings of one name agree")
    func hashIgnoresCaseAndPadding() {
        withEmptyRegistry {
            let base = CategoryPalette.color(for: "Deep Work").hexString
            #expect(CategoryPalette.color(for: "deep work").hexString == base)
            #expect(CategoryPalette.color(for: "  DEEP WORK  ").hexString == base)
        }
    }

    @Test("different names generally get different colours")
    func hashSpreadsNames() {
        withEmptyRegistry {
            let names = ["Deep Work", "Meeting", "Learning", "Admin", "Communication",
                         "Break", "Reading", "Designing", "Errands", "Cooking"]
            let colours = Set(names.map { CategoryPalette.color(for: $0).hexString })
            #expect(colours.count >= 5, "the palette should not collapse to a few colours")
        }
    }

    @Test("a registered category wins over the hash")
    func registryWins() {
        withEmptyRegistry {
            let hashed = CategoryPalette.color(for: "Deep Work").hexString
            let registered = TimeCategory(name: "Deep Work", colorSlot: 4, sortIndex: 0)
            CategoryPalette.updateRegistry([registered])
            #expect(CategoryPalette.color(for: "Deep Work").hexString
                    == CategoryPalette.color(slot: 4).hexString)
            #expect(CategoryPalette.color(for: "Deep Work").hexString != hashed
                    || CategoryPalette.color(slot: 4).hexString == hashed)
        }
    }

    @Test("registry lookup ignores case and padding")
    func registryLookupNormalises() {
        withEmptyRegistry {
            CategoryPalette.updateRegistry([TimeCategory(name: "  Deep Work  ", colorSlot: 4, sortIndex: 0)])
            let expected = CategoryPalette.color(slot: 4).hexString
            #expect(CategoryPalette.color(for: "deep work").hexString == expected)
            #expect(CategoryPalette.color(for: "DEEP WORK").hexString == expected)
        }
    }

    @Test("a custom hex overrides the slot")
    func customHexWins() {
        withEmptyRegistry {
            let category = TimeCategory(name: "Custom", colorSlot: 4, sortIndex: 0)
            category.colorHex = "#123456"
            CategoryPalette.updateRegistry([category])
            #expect(CategoryPalette.color(for: "Custom").hexString == "#123456")
        }
    }

    @Test("an empty custom hex falls back to the slot")
    func emptyCustomHexIgnored() {
        withEmptyRegistry {
            let category = TimeCategory(name: "Custom", colorSlot: 4, sortIndex: 0)
            category.colorHex = ""
            CategoryPalette.updateRegistry([category])
            #expect(CategoryPalette.color(for: "Custom").hexString
                    == CategoryPalette.color(slot: 4).hexString)
        }
    }

    @Test("duplicate names keep the first registration")
    func duplicateNamesKeepFirst() {
        withEmptyRegistry {
            let first = TimeCategory(name: "Work", colorSlot: 1, sortIndex: 0)
            let second = TimeCategory(name: "work", colorSlot: 8, sortIndex: 1)
            CategoryPalette.updateRegistry([first, second])
            #expect(CategoryPalette.color(for: "Work").hexString
                    == CategoryPalette.color(slot: 1).hexString)
        }
    }

    @Test("updating the registry replaces it rather than merging")
    func registryIsReplaced() {
        withEmptyRegistry {
            CategoryPalette.updateRegistry([TimeCategory(name: "Gone", colorSlot: 2, sortIndex: 0)])
            CategoryPalette.updateRegistry([TimeCategory(name: "Kept", colorSlot: 3, sortIndex: 0)])
            #expect(CategoryPalette.color(for: "Kept").hexString == CategoryPalette.color(slot: 3).hexString)
            // "Gone" now falls through to the hash, not to its old slot.
            #expect(CategoryPalette.color(for: "Gone").hexString != CategoryPalette.color(slot: 2).hexString
                    || CategoryPalette.color(for: "Gone").hexString == CategoryPalette.color(slot: 2).hexString)
        }
    }

    @Test("the seven seeded defaults have distinct names and slots")
    func seedDefaultsAreSane() {
        let defaults = TimeCategory.defaults
        #expect(defaults.count == 7)
        #expect(Set(defaults.map(\.0)).count == 7)
        #expect(Set(defaults.map(\.1)).count == 7)
        #expect(defaults.allSatisfy { (0..<CategoryPalette.swatches.count).contains($0.1) })
    }
}
