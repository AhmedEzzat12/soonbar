import Testing
@testable import SoonbarCore

struct CustomDurationTests {
    @Test func wholeMinutesReadAsMinutes() {
        #expect(CustomDuration.split(120) == (2, .minutes))
        #expect(CustomDuration.split(90) == (90, .seconds))
        #expect(CustomDuration.split(45) == (45, .seconds))
    }

    @Test func minutesOnlyWhenSecondsArentOffered() {
        #expect(CustomDuration.split(420, allowed: [.minutes]) == (7, .minutes))
    }

    @Test func typedValuesStayInRange() {
        #expect(CustomDuration.seconds(3, .minutes, within: 5...3600) == 180)
        #expect(CustomDuration.seconds(2, .seconds, within: 5...3600) == 5)
        #expect(CustomDuration.seconds(90, .minutes, within: 5...3600) == 3600)
    }

    @Test func labels() {
        #expect(CustomDuration.label(45) == "45 seconds")
        #expect(CustomDuration.label(60) == "1 minute")
        #expect(CustomDuration.label(1) == "1 second")
        #expect(CustomDuration.label(180) == "3 minutes")
    }
}
