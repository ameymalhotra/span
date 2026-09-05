import Foundation
import Testing
@testable import Span

@Suite("TimelineGeometry")
struct TimelineGeometryTests {

    private let hourHeight: CGFloat = 60
    private var geometry: TimelineGeometry {
        TimelineGeometry(dayStart: Clock.dayStart, hourHeight: hourHeight)
    }

    // MARK: - Day length

    @Test("an ordinary day is 24 hours")
    func ordinaryDay() {
        #expect(geometry.hourCount == 24)
        #expect(geometry.totalHeight == 24 * hourHeight)
    }

    @Test("the spring-forward day is 23 hours")
    func springForward() {
        let day = TimelineGeometry(dayStart: Clock.date(2025, 3, 9), hourHeight: hourHeight)
        #expect(day.hourCount == 23)
        #expect(day.totalHeight == 23 * hourHeight)
    }

    @Test("the fall-back day is 25 hours")
    func fallBack() {
        let day = TimelineGeometry(dayStart: Clock.date(2025, 11, 2), hourHeight: hourHeight)
        #expect(day.hourCount == 25)
        #expect(day.totalHeight == 25 * hourHeight)
    }

    // MARK: - y(for:)

    @Test("y maps the day onto the track")
    func yMapping() {
        #expect(geometry.y(for: Clock.dayStart) == 0)
        #expect(geometry.y(for: Clock.at(hour: 1)) == hourHeight)
        #expect(geometry.y(for: Clock.at(hour: 12)) == 12 * hourHeight)
        #expect(geometry.y(for: Clock.at(hour: 23.5)) == 23.5 * hourHeight)
    }

    @Test("y clamps outside the day")
    func yClamps() {
        #expect(geometry.y(for: Clock.dayStart.addingTimeInterval(-7200)) == 0)
        #expect(geometry.y(for: Clock.at(hour: 30)) == geometry.totalHeight)
    }

    @Test("y scales with the hour height")
    func yScales() {
        let tall = TimelineGeometry(dayStart: Clock.dayStart, hourHeight: 140)
        #expect(tall.y(for: Clock.at(hour: 3)) == 420)
    }

    // MARK: - date(for:)

    @Test("date is the inverse of y inside the day")
    func dateInvertsY() {
        for hour in stride(from: 0.0, through: 23.0, by: 0.5) {
            let moment = Clock.at(hour: hour)
            #expect(geometry.date(for: geometry.y(for: moment)) == moment)
        }
    }

    @Test("date clamps to the day")
    func dateClamps() {
        #expect(geometry.date(for: -100) == Clock.dayStart)
        #expect(geometry.date(for: 99_999) == Clock.dayStart.addingTimeInterval(24 * 3600))
    }

    // MARK: - Rows and their labels

    @Test("on an ordinary day the row index is the hour")
    func rowsMatchHoursNormally() {
        for hour in 0..<24 {
            #expect(geometry.hour(atRow: hour) == hour)
        }
    }

    @Test("after a fall-back transition the rows stay in step with the clock")
    func rowLabelsFollowTheClockInAutumn() {
        let dayStart = Clock.date(2025, 11, 2)
        let day = TimelineGeometry(dayStart: dayStart, hourHeight: hourHeight)

        // 1 AM happens twice, so the two rows either side of the change both
        // read 1 AM and everything after it stays honest.
        #expect(day.hour(atRow: 1) == 1)
        #expect(day.hour(atRow: 2) == 1)
        #expect(day.hour(atRow: 14) == 13)

        // A 1 PM block sits at row 14, and row 14 is the one labelled 1 PM.
        let onePM = Clock.date(2025, 11, 2, 13, 0)
        #expect(day.y(for: onePM) == 14 * hourHeight)
        #expect(day.hour(atRow: 14) == Calendar.current.component(.hour, from: onePM))
    }

    @Test("after a spring-forward transition the rows stay in step too")
    func rowLabelsFollowTheClockInSpring() {
        let day = TimelineGeometry(dayStart: Clock.date(2025, 3, 9), hourHeight: hourHeight)

        // 2 AM never happens, so row 2 is 3 AM.
        #expect(day.hour(atRow: 1) == 1)
        #expect(day.hour(atRow: 2) == 3)

        let onePM = Clock.date(2025, 3, 9, 13, 0)
        #expect(day.y(for: onePM) == 12 * hourHeight)
        #expect(day.hour(atRow: 12) == Calendar.current.component(.hour, from: onePM))
    }

    @Test("every row on a DST day is labelled with the time actually at it")
    func everyRowLabelIsHonest() {
        for dayStart in [Clock.date(2025, 3, 9), Clock.date(2025, 11, 2), Clock.dayStart] {
            let day = TimelineGeometry(dayStart: dayStart, hourHeight: hourHeight)
            for row in 0..<day.hourCount {
                let at = day.date(for: CGFloat(row) * hourHeight)
                #expect(day.hour(atRow: row) == Calendar.current.component(.hour, from: at))
            }
        }
    }

    @Test("row(for:) is the inverse of hour(atRow:)")
    func rowRoundTrips() {
        for dayStart in [Clock.date(2025, 3, 9), Clock.date(2025, 11, 2), Clock.dayStart] {
            let day = TimelineGeometry(dayStart: dayStart, hourHeight: hourHeight)
            for row in 0..<day.hourCount {
                let at = day.date(for: CGFloat(row) * hourHeight)
                #expect(day.row(for: at) == row)
            }
        }
    }

    @Test("row(for:) clamps sensibly before the day starts")
    func rowBeforeDayStart() {
        #expect(geometry.row(for: Clock.dayStart) == 0)
        #expect(geometry.row(for: Clock.at(hour: 9.9)) == 9)
    }

    // MARK: - snapped

    @Test("snapped rounds to the nearest five minutes")
    func snapping() {
        let base = Clock.dayStart
        #expect(geometry.snapped(base.addingTimeInterval(Clock.minutes(12))) == base.addingTimeInterval(Clock.minutes(10)))
        #expect(geometry.snapped(base.addingTimeInterval(Clock.minutes(13))) == base.addingTimeInterval(Clock.minutes(15)))
        #expect(geometry.snapped(base.addingTimeInterval(Clock.minutes(15))) == base.addingTimeInterval(Clock.minutes(15)))
    }

    @Test("snapped rounds a half step away from zero")
    func snappingHalfStep() {
        let base = Clock.dayStart
        #expect(geometry.snapped(base.addingTimeInterval(Clock.minutes(2.5))) == base.addingTimeInterval(Clock.minutes(5)))
    }

    @Test("snapped honours a custom step")
    func snappingCustomStep() {
        let base = Clock.dayStart
        #expect(geometry.snapped(base.addingTimeInterval(Clock.minutes(23)), minutes: 15)
                == base.addingTimeInterval(Clock.minutes(30)))
        #expect(geometry.snapped(base.addingTimeInterval(Clock.minutes(21)), minutes: 15)
                == base.addingTimeInterval(Clock.minutes(15)))
        #expect(geometry.snapped(base.addingTimeInterval(Clock.minutes(23)), minutes: 1)
                == base.addingTimeInterval(Clock.minutes(23)))
    }

    @Test("snapped works before the day start")
    func snappingNegative() {
        let before = Clock.dayStart.addingTimeInterval(-Clock.minutes(12))
        #expect(geometry.snapped(before) == Clock.dayStart.addingTimeInterval(-Clock.minutes(10)))
    }

    // MARK: - extent

    @Test("extent measures a block against the track")
    func extent() {
        let block = Fixture.block(from: Clock.at(hour: 9), to: Clock.at(hour: 10.5))
        let (y, height) = geometry.extent(for: block)
        #expect(y == 9 * hourHeight)
        #expect(height == 1.5 * hourHeight)
    }

    @Test("extent gives a very short block a floor so it stays clickable")
    func extentMinimum() {
        let block = Fixture.block(from: Clock.at(hour: 9), to: Clock.at(hour: 9).addingTimeInterval(30))
        #expect(geometry.extent(for: block).height == 3)
        #expect(geometry.extent(for: block, minimumHeight: 24).height == 24)
    }

    @Test("extent handles a zero-length block")
    func extentZeroLength() {
        let moment = Clock.at(hour: 9)
        let block = Fixture.block(from: moment, to: moment)
        let (y, height) = geometry.extent(for: block)
        #expect(y == 9 * hourHeight)
        #expect(height == 3)
    }

    @Test("extent clips a block that runs past midnight")
    func extentClipsOverflow() {
        let block = Fixture.block(from: Clock.at(hour: 23), to: Clock.at(hour: 26))
        let (y, height) = geometry.extent(for: block)
        #expect(y == 23 * hourHeight)
        #expect(height == hourHeight)
    }
}
