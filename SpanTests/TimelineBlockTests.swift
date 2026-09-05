import Foundation
import SwiftData
import Testing
@testable import Span

@MainActor
@Suite("TimelineBlock")
struct TimelineBlockTests {

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try TestStore.inMemory()
    }

    // MARK: - Kind

    @Test("activity and idle draw as ribbons, sessions and entries as cards")
    func ribbonKinds() {
        #expect(TimelineBlock.Kind.activity.isRibbon)
        #expect(TimelineBlock.Kind.idle.isRibbon)
        #expect(!TimelineBlock.Kind.session.isRibbon)
        #expect(!TimelineBlock.Kind.entry.isRibbon)
    }

    @Test("duration is never negative")
    func durationFloor() {
        let backwards = Fixture.block(from: Clock.at(hour: 10), to: Clock.at(hour: 9))
        #expect(backwards.duration == 0)
    }

    // MARK: - Sessions

    @Test("a session with no segments draws as one spanning block")
    func legacySessionSpans() {
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 9), endedAt: Clock.at(hour: 11))
        let blocks = TimelineBlock.blocks(for: session, now: Clock.at(hour: 15))
        #expect(blocks.count == 1)
        #expect(blocks[0].start == Clock.at(hour: 9))
        #expect(blocks[0].end == Clock.at(hour: 11))
        #expect(blocks[0].kind == .session)
    }

    @Test("a segment-less session still running ends at now")
    func legacySessionRunning() {
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 9), status: .active)
        let blocks = TimelineBlock.blocks(for: session, now: Clock.at(hour: 10.5))
        #expect(blocks[0].end == Clock.at(hour: 10.5))
    }

    @Test("one segment gives one block")
    func singleSegment() {
        let session = Fixture.session(
            in: context, startedAt: Clock.at(hour: 9),
            segments: [(Clock.at(hour: 9), Clock.at(hour: 10))])
        let blocks = TimelineBlock.blocks(for: session, now: Clock.at(hour: 15))
        #expect(blocks.count == 1)
        #expect(blocks[0].start == Clock.at(hour: 9))
        #expect(blocks[0].end == Clock.at(hour: 10))
    }

    @Test("a running session draws through to when it is due to end")
    func openSegmentShowsRemainingTime() {
        // 60 planned minutes, 45 elapsed: the block runs to 10:00, not to now,
        // so the remaining quarter hour is visible and draggable.
        let session = Fixture.session(
            in: context, plannedMinutes: 60, startedAt: Clock.at(hour: 9), status: .active,
            segments: [(Clock.at(hour: 9), nil)])
        let blocks = TimelineBlock.blocks(for: session, now: Clock.at(hour: 9.75))
        #expect(blocks[0].end == Clock.at(hour: 10))
    }

    @Test("a running session that is over its planned time stops at now")
    func openSegmentPastPlannedTime() {
        let session = Fixture.session(
            in: context, plannedMinutes: 30, startedAt: Clock.at(hour: 9), status: .active,
            segments: [(Clock.at(hour: 9), nil)])
        let blocks = TimelineBlock.blocks(for: session, now: Clock.at(hour: 10))
        #expect(blocks[0].end == Clock.at(hour: 10))
    }

    @Test("a paused session's open segment stops at now, not at its planned end")
    func openSegmentWhilePaused() {
        let session = Fixture.session(
            in: context, plannedMinutes: 60, startedAt: Clock.at(hour: 9),
            pausedAt: Clock.at(hour: 9.5), status: .paused,
            segments: [(Clock.at(hour: 9), nil)])
        let blocks = TimelineBlock.blocks(for: session, now: Clock.at(hour: 9.75))
        #expect(blocks[0].end == Clock.at(hour: 9.75))
    }

    @Test("a short pause reads as one block, not two identical cards")
    func shortPauseMerges() {
        let session = Fixture.session(in: context, segments: [
            (Clock.at(hour: 9), Clock.at(hour: 10)),
            (Clock.at(hour: 10.08), Clock.at(hour: 11)),   // a 5-minute break
        ])
        let blocks = TimelineBlock.blocks(for: session, now: Clock.at(hour: 15))
        #expect(blocks.count == 1)
        #expect(blocks[0].start == Clock.at(hour: 9))
        #expect(blocks[0].end == Clock.at(hour: 11))
    }

    @Test("a long pause draws as a real gap")
    func longPauseSplits() {
        let session = Fixture.session(in: context, segments: [
            (Clock.at(hour: 9), Clock.at(hour: 10)),
            (Clock.at(hour: 10.25), Clock.at(hour: 11)),   // a 15-minute break
        ])
        let blocks = TimelineBlock.blocks(for: session, now: Clock.at(hour: 15))
        #expect(blocks.count == 2)
        #expect(blocks[0].end == Clock.at(hour: 10))
        #expect(blocks[1].start == Clock.at(hour: 10.25))
    }

    @Test("a pause exactly at the merge threshold still merges")
    func mergeGapBoundary() {
        let session = Fixture.session(in: context, segments: [
            (Clock.at(hour: 9), Clock.at(hour: 10)),
            (Clock.at(hour: 10).addingTimeInterval(600), Clock.at(hour: 11)),
        ])
        #expect(TimelineBlock.blocks(for: session, now: Clock.at(hour: 15)).count == 1)
    }

    @Test("segments are sorted before merging")
    func segmentsAreSorted() {
        let session = Fixture.session(in: context, segments: [
            (Clock.at(hour: 14), Clock.at(hour: 15)),
            (Clock.at(hour: 9), Clock.at(hour: 10)),
        ])
        let blocks = TimelineBlock.blocks(for: session, now: Clock.at(hour: 16))
        #expect(blocks.count == 2)
        #expect(blocks[0].start == Clock.at(hour: 9))
        #expect(blocks[1].start == Clock.at(hour: 14))
    }

    @Test("block ids are unique across a session's runs")
    func blockIdsUnique() {
        let session = Fixture.session(in: context, segments: [
            (Clock.at(hour: 9), Clock.at(hour: 10)),
            (Clock.at(hour: 12), Clock.at(hour: 13)),
            (Clock.at(hour: 15), Clock.at(hour: 16)),
        ])
        let blocks = TimelineBlock.blocks(for: session, now: Clock.at(hour: 17))
        #expect(Set(blocks.map(\.id)).count == 3)
    }

    @Test("an empty category becomes no category rather than an empty label")
    func emptyCategoryIsNil() {
        let session = Fixture.session(in: context, category: "",
                                      segments: [(Clock.at(hour: 9), Clock.at(hour: 10))])
        let block = TimelineBlock.blocks(for: session, now: Clock.at(hour: 11))[0]
        #expect(block.category == nil)
        #expect(block.subtitle == nil)
    }

    @Test("the focus rating carries onto every run of the session")
    func focusRatingCarries() {
        let session = Fixture.session(in: context, segments: [
            (Clock.at(hour: 9), Clock.at(hour: 10)),
            (Clock.at(hour: 12), Clock.at(hour: 13)),
        ], focusRating: 4)
        let blocks = TimelineBlock.blocks(for: session, now: Clock.at(hour: 14))
        #expect(blocks.allSatisfy { $0.focusRating == 4 })
    }

    // MARK: - Entries

    @Test("an entry maps straight onto a block")
    func entryMapping() {
        let entry = Fixture.entry(in: context, title: "Standup", category: "Meeting",
                                  from: Clock.at(hour: 9), to: Clock.at(hour: 9.25))
        let block = TimelineBlock.block(for: entry)
        #expect(block.kind == .entry)
        #expect(block.title == "Standup")
        #expect(block.category == "Meeting")
        #expect(block.subtitle == "Meeting")
        #expect(block.start == Clock.at(hour: 9))
        #expect(block.end == Clock.at(hour: 9.25))
        #expect(block.focusRating == nil)
        #expect(block.id == "entry-\(entry.id)")
    }

    @Test("an uncategorised entry has no category")
    func entryWithoutCategory() {
        let entry = Fixture.entry(in: context, category: "")
        let block = TimelineBlock.block(for: entry)
        #expect(block.category == nil)
        #expect(block.subtitle == nil)
    }

    // MARK: - Activity

    @Test("an activity record maps onto a block")
    func activityMapping() {
        let record = Fixture.activity(in: context, appName: "Xcode",
                                      windowTitle: "ModelStack.swift",
                                      from: Clock.at(hour: 9), to: Clock.at(hour: 9.5))
        let block = TimelineBlock.block(for: record)
        #expect(block.kind == .activity)
        #expect(block.title == "Xcode")
        #expect(block.subtitle == "ModelStack.swift")
        #expect(block.category == "Building")
    }

    @Test("an idle record is titled Away")
    func idleMapping() {
        let record = Fixture.activity(in: context, appName: "Away", bundleIdentifier: nil,
                                      isIdle: true)
        let block = TimelineBlock.block(for: record)
        #expect(block.kind == .idle)
        #expect(block.title == "Away")
    }

    @Test("the subtitle prefers a window title, then a URL")
    func subtitlePreference() {
        let titled = Fixture.activity(in: context, windowTitle: "Doc", url: "https://example.com")
        #expect(TimelineBlock.block(for: titled).subtitle == "Doc")

        let urlOnly = Fixture.activity(in: context, windowTitle: nil, url: "https://example.com")
        #expect(TimelineBlock.block(for: urlOnly).subtitle == "https://example.com")

        let bare = Fixture.activity(in: context, windowTitle: nil, url: nil)
        #expect(TimelineBlock.block(for: bare).subtitle == nil)
    }

    @Test("a record with no category falls back to the app name")
    func activityCategoryFallback() {
        let record = Fixture.activity(in: context, appName: "Ledger", categoryName: nil)
        #expect(TimelineBlock.block(for: record).category == "Ledger")
    }

    // MARK: - mergedActivityBlocks

    @Test("merging nothing yields nothing")
    func mergeEmpty() {
        #expect(TimelineBlock.mergedActivityBlocks([]).isEmpty)
    }

    @Test("consecutive records for one app become one band")
    func mergeConsecutive() {
        let records = [
            Fixture.activity(in: context, from: Clock.at(hour: 9), to: Clock.at(hour: 9.25)),
            Fixture.activity(in: context, from: Clock.at(hour: 9.25), to: Clock.at(hour: 9.5)),
            Fixture.activity(in: context, from: Clock.at(hour: 9.5), to: Clock.at(hour: 10)),
        ]
        let merged = TimelineBlock.mergedActivityBlocks(records)
        #expect(merged.count == 1)
        #expect(merged[0].start == Clock.at(hour: 9))
        #expect(merged[0].end == Clock.at(hour: 10))
    }

    @Test("a gap wider than the tolerance splits the band")
    func mergeRespectsGapTolerance() {
        let records = [
            Fixture.activity(in: context, from: Clock.at(hour: 9), to: Clock.at(hour: 9.25)),
            Fixture.activity(in: context, from: Clock.at(hour: 9.25).addingTimeInterval(120),
                             to: Clock.at(hour: 9.5)),
        ]
        #expect(TimelineBlock.mergedActivityBlocks(records, gapTolerance: 90).count == 2)
        #expect(TimelineBlock.mergedActivityBlocks(records, gapTolerance: 180).count == 1)
    }

    @Test("apps in different categories are never merged")
    func mergeDistinguishesCategories() {
        let records = [
            Fixture.activity(in: context, appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
                             from: Clock.at(hour: 9), to: Clock.at(hour: 9.5)),
            Fixture.activity(in: context, appName: "Safari", bundleIdentifier: "com.apple.Safari",
                             from: Clock.at(hour: 9.5), to: Clock.at(hour: 10)),
        ]
        let merged = TimelineBlock.mergedActivityBlocks(records)
        #expect(merged.count == 2)
        #expect(merged.map(\.title) == ["Building", "Browsing"])
    }

    @Test("by category, two apps in one category merge into a single band")
    func mergeGroupsByCategory() {
        let records = [
            Fixture.activity(in: context, appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
                             from: Clock.at(hour: 9), to: Clock.at(hour: 9.5)),
            Fixture.activity(in: context, appName: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty",
                             from: Clock.at(hour: 9.5), to: Clock.at(hour: 10)),
        ]
        let merged = TimelineBlock.mergedActivityBlocks(records, grouping: .category)
        #expect(merged.count == 1)
        #expect(merged[0].title == "Building")
        #expect(merged[0].end == Clock.at(hour: 10))
    }

    @Test("by app, the same two records stay separate")
    func mergeGroupsByApp() {
        let records = [
            Fixture.activity(in: context, appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
                             from: Clock.at(hour: 9), to: Clock.at(hour: 9.5)),
            Fixture.activity(in: context, appName: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty",
                             from: Clock.at(hour: 9.5), to: Clock.at(hour: 10)),
        ]
        let merged = TimelineBlock.mergedActivityBlocks(records, grouping: .app)
        #expect(merged.count == 2)
        #expect(merged.map(\.title) == ["Xcode", "Ghostty"])
    }

    @Test("by category, the band still names the app underneath it")
    func mergedSubtitleNamesTheApp() {
        let record = Fixture.activity(in: context, appName: "Xcode",
                                      bundleIdentifier: "com.apple.dt.Xcode",
                                      windowTitle: "ModelStack.swift",
                                      from: Clock.at(hour: 9), to: Clock.at(hour: 10))
        let merged = TimelineBlock.mergedActivityBlocks([record], grouping: .category)
        #expect(merged[0].subtitle == "Xcode · ModelStack.swift")

        let byApp = TimelineBlock.mergedActivityBlocks([record], grouping: .app)
        #expect(byApp[0].subtitle == "ModelStack.swift")
    }

    @Test("an idle band is titled Away under either grouping")
    func mergedIdleTitle() {
        let record = Fixture.activity(in: context, appName: "Xcode",
                                      from: Clock.at(hour: 9), to: Clock.at(hour: 10), isIdle: true)
        #expect(TimelineBlock.mergedActivityBlocks([record], grouping: .category)[0].title == "Away")
        #expect(TimelineBlock.mergedActivityBlocks([record], grouping: .app)[0].title == "Away")
    }

    @Test("idle is never merged into work in the same app")
    func mergeSeparatesIdle() {
        let records = [
            Fixture.activity(in: context, appName: "Away",
                             from: Clock.at(hour: 9), to: Clock.at(hour: 9.5), isIdle: false),
            Fixture.activity(in: context, appName: "Away",
                             from: Clock.at(hour: 9.5), to: Clock.at(hour: 10), isIdle: true),
        ]
        let merged = TimelineBlock.mergedActivityBlocks(records)
        #expect(merged.count == 2)
        #expect(merged.map(\.kind) == [TimelineBlock.Kind.activity, .idle])
    }

    @Test("records are sorted before merging")
    func mergeSortsInput() {
        let later = Fixture.activity(in: context, from: Clock.at(hour: 9.5), to: Clock.at(hour: 10))
        let earlier = Fixture.activity(in: context, from: Clock.at(hour: 9), to: Clock.at(hour: 9.5))
        let merged = TimelineBlock.mergedActivityBlocks([later, earlier])
        #expect(merged.count == 1)
        #expect(merged[0].start == Clock.at(hour: 9))
    }

    @Test("overlapping records extend rather than truncate the band")
    func mergeOverlapping() {
        let records = [
            Fixture.activity(in: context, from: Clock.at(hour: 9), to: Clock.at(hour: 10)),
            Fixture.activity(in: context, from: Clock.at(hour: 9.5), to: Clock.at(hour: 9.75)),
        ]
        let merged = TimelineBlock.mergedActivityBlocks(records)
        #expect(merged.count == 1)
        #expect(merged[0].end == Clock.at(hour: 10))
    }

    @Test("a merged band keeps a stable, unique id")
    func mergedIdsAreUnique() {
        let records = [
            Fixture.activity(in: context, appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
                             from: Clock.at(hour: 9), to: Clock.at(hour: 9.5)),
            Fixture.activity(in: context, appName: "Safari", bundleIdentifier: "com.apple.Safari",
                             from: Clock.at(hour: 9.5), to: Clock.at(hour: 10)),
            Fixture.activity(in: context, appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode",
                             from: Clock.at(hour: 10), to: Clock.at(hour: 11)),
        ]
        let merged = TimelineBlock.mergedActivityBlocks(records)
        #expect(Set(merged.map(\.id)).count == merged.count)
    }

    @Test("a single record survives merging unchanged")
    func mergeSingle() {
        let record = Fixture.activity(in: context, from: Clock.at(hour: 9), to: Clock.at(hour: 10))
        let merged = TimelineBlock.mergedActivityBlocks([record])
        #expect(merged.count == 1)
        #expect(merged[0].start == record.startedAt)
        #expect(merged[0].end == record.endedAt)
    }
}
