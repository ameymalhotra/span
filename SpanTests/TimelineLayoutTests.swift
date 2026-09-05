import Foundation
import Testing
@testable import Span

@Suite("TimelineLayout")
struct TimelineLayoutTests {

    private let geometry = TimelineGeometry(dayStart: Clock.dayStart, hourHeight: 60)

    private func block(_ name: String, _ from: Double, _ to: Double) -> TimelineBlock {
        Fixture.block(name, from: Clock.at(hour: from), to: Clock.at(hour: to))
    }

    private func lane(_ laid: [LaidOutBlock], _ title: String) -> LaidOutBlock? {
        laid.first { $0.block.title == title }
    }

    // MARK: - lanes

    @Test("no blocks, no lanes")
    func lanesEmpty() {
        #expect(TimelineLayout.lanes(for: []).isEmpty)
    }

    @Test("a lone block takes the only column")
    func lanesSingle() {
        let laid = TimelineLayout.lanes(for: [block("A", 9, 10)])
        #expect(laid.count == 1)
        #expect(laid[0].lane == 0)
        #expect(laid[0].laneCount == 1)
    }

    @Test("blocks that do not overlap each take the full width")
    func lanesDisjoint() {
        let laid = TimelineLayout.lanes(for: [block("A", 9, 10), block("B", 11, 12)])
        #expect(laid.allSatisfy { $0.lane == 0 })
        #expect(laid.allSatisfy { $0.laneCount == 1 })
    }

    @Test("blocks that merely touch do not overlap")
    func lanesTouching() {
        let laid = TimelineLayout.lanes(for: [block("A", 9, 10), block("B", 10, 11)])
        #expect(laid.allSatisfy { $0.laneCount == 1 })
    }

    @Test("two overlapping blocks split into two columns")
    func lanesOverlapping() {
        let laid = TimelineLayout.lanes(for: [block("A", 9, 11), block("B", 10, 12)])
        #expect(Set(laid.map(\.lane)) == [0, 1])
        #expect(laid.allSatisfy { $0.laneCount == 2 })
    }

    @Test("a transitive chain forms one cluster")
    func lanesTransitiveChain() {
        // A-B overlap, B-C overlap, A-C do not; all three share a cluster.
        let laid = TimelineLayout.lanes(for: [block("A", 9, 10.5), block("B", 10, 11.5), block("C", 11, 12)])
        #expect(laid.allSatisfy { $0.laneCount == 2 })
        #expect(lane(laid, "A")?.lane == 0)
        #expect(lane(laid, "B")?.lane == 1)
        #expect(lane(laid, "C")?.lane == 0)
    }

    @Test("a busy hour does not narrow the rest of the day")
    func lanesClusterIsolation() {
        let busy = [block("A", 9, 10), block("B", 9, 10), block("C", 9, 10), block("D", 9, 10)]
        let quiet = [block("Later", 14, 15)]
        let laid = TimelineLayout.lanes(for: busy + quiet)
        #expect(lane(laid, "A")?.laneCount == 4)
        #expect(lane(laid, "Later")?.laneCount == 1)
    }

    @Test("blocks starting together are ordered longest first")
    func lanesSameStart() {
        let laid = TimelineLayout.lanes(for: [block("Short", 9, 9.5), block("Long", 9, 11)])
        #expect(lane(laid, "Long")?.lane == 0)
        #expect(lane(laid, "Short")?.lane == 1)
    }

    @Test("every input block comes back exactly once")
    func lanesPreservesInput() {
        let blocks = [block("A", 9, 11), block("B", 10, 12), block("C", 13, 14), block("D", 13.5, 15)]
        let laid = TimelineLayout.lanes(for: blocks)
        #expect(laid.count == blocks.count)
        #expect(Set(laid.map(\.block.id)) == Set(blocks.map(\.id)))
    }

    @Test("a zero-length block still gets a lane")
    func lanesZeroLength() {
        let moment = Clock.at(hour: 9)
        let point = Fixture.block("Point", from: moment, to: moment)
        let laid = TimelineLayout.lanes(for: [block("A", 9, 10), point])
        #expect(laid.count == 2)
    }

    @Test("a block nested inside a longer one does not free that column")
    func lanesNestedBlock() {
        // Long runs 9-12. Short runs 9:30-10 beside it. Overlap runs 10:30-11:30
        // and still overlaps Long, so it must not be packed into Long's column
        // even though Short — the last block written to column 1 — ended at 10.
        let laid = TimelineLayout.lanes(for: [
            block("Long", 9, 12), block("Short", 9.5, 10), block("Overlap", 10.5, 11.5),
        ])
        let longLane = lane(laid, "Long")!
        #expect(lane(laid, "Overlap")?.lane != longLane.lane)
        #expect(laid.allSatisfy { $0.laneCount == 2 })
    }

    @Test("no two blocks in one column ever overlap in time")
    func lanesColumnsAreCollisionFree() {
        let blocks = [
            block("A", 9, 12), block("B", 9.5, 10), block("C", 10.5, 11.5),
            block("D", 9.25, 13), block("E", 12.5, 14), block("F", 13.5, 15),
            block("G", 9, 9.1), block("H", 11, 11.2),
        ]
        let laid = TimelineLayout.lanes(for: blocks)
        for column in Set(laid.map(\.lane)) {
            let inColumn = laid.filter { $0.lane == column }.map(\.block)
            for a in inColumn {
                for b in inColumn where a.id != b.id {
                    #expect(!(a.start < b.end && b.start < a.end),
                            "\(a.title) and \(b.title) share column \(column)")
                }
            }
        }
    }

    @Test("laneCount is wide enough for every block in the cluster")
    func lanesCountCoversCluster() {
        let laid = TimelineLayout.lanes(for: [
            block("A", 9, 12), block("B", 9.5, 11), block("C", 10, 10.5),
        ])
        #expect(laid.allSatisfy { $0.laneCount == 3 })
        #expect(Set(laid.map(\.lane)) == [0, 1, 2])
    }

    // MARK: - place

    @Test("place positions blocks at their true time when there is room")
    func placeNatural() {
        let placed = TimelineLayout.place(
            [block("A", 9, 10), block("B", 11, 12)], in: geometry, minimumHeight: 24)
        let a = placed.first { $0.block.title == "A" }!
        let b = placed.first { $0.block.title == "B" }!
        #expect(a.y == 540, "a.y=\(a.y) height=\(a.height) lane=\(a.lane)/\(a.laneCount)")
        #expect(a.height == 60)
        #expect(b.y == 660, "b.y=\(b.y) placedCount=\(placed.count) titles=\(placed.map(\.block.title))")
    }

    @Test("place gives a short block a legible minimum height")
    func placeMinimumHeight() {
        let short = Fixture.block("Short", from: Clock.at(hour: 9),
                                  to: Clock.at(hour: 9).addingTimeInterval(120))
        let placed = TimelineLayout.place([short], in: geometry, minimumHeight: 24)
        #expect(placed[0].height == 24)
    }

    @Test("place cascades blocks that would collide once padded out")
    func placeCascades() {
        // Two 5-minute blocks 6 minutes apart do not overlap in time, but at
        // 24pt each they would be drawn over one another.
        let first = Fixture.block("First", from: Clock.at(hour: 9),
                                  to: Clock.at(hour: 9).addingTimeInterval(300))
        let second = Fixture.block("Second", from: Clock.at(hour: 9).addingTimeInterval(360),
                                   to: Clock.at(hour: 9).addingTimeInterval(660))
        let placed = TimelineLayout.place([first, second], in: geometry, minimumHeight: 24, spacing: 2)
        let a = placed.first { $0.block.title == "First" }!
        let b = placed.first { $0.block.title == "Second" }!
        #expect(b.y == a.y + a.height + 2)
        #expect(b.y > b.block.start.timeIntervalSince(Clock.dayStart) / 3600 * 60)
    }

    @Test("place cascades each column independently")
    func placeCascadesPerLane() {
        let placed = TimelineLayout.place(
            [block("A", 9, 11), block("B", 9, 11)], in: geometry, minimumHeight: 24)
        #expect(Set(placed.map(\.lane)) == [0, 1])
        #expect(placed.allSatisfy { $0.y == 540 })
    }

    @Test("place returns one entry per input block")
    func placePreservesCount() {
        let blocks = (0..<10).map { block("B\($0)", Double($0), Double($0) + 0.5) }
        #expect(TimelineLayout.place(blocks, in: geometry, minimumHeight: 24).count == 10)
    }

    @Test("place keeps blocks in start order within a column")
    func placeOrdering() {
        let blocks = [block("C", 13, 14), block("A", 9, 10), block("B", 11, 12)]
        let placed = TimelineLayout.place(blocks, in: geometry, minimumHeight: 24)
        let byLane = placed.filter { $0.lane == 0 }.sorted { $0.y < $1.y }
        #expect(byLane.map(\.block.title) == ["A", "B", "C"])
    }

    @Test("place never draws a block above the top of the day")
    func placeNeverNegative() {
        let early = Fixture.block("Early", from: Clock.dayStart.addingTimeInterval(-3600),
                                  to: Clock.dayStart.addingTimeInterval(600))
        let placed = TimelineLayout.place([early], in: geometry, minimumHeight: 24)
        #expect(placed[0].y >= 0)
    }

    @Test("place handles an empty day")
    func placeEmpty() {
        #expect(TimelineLayout.place([], in: geometry, minimumHeight: 24).isEmpty)
    }
}
