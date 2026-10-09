import Testing
@testable import SoonbarCore

struct SwipeToDismissTests {
    let width = 340.0

    @Test func aLongDragDismisses() {
        #expect(SwipeToDismiss.shouldDismiss(offset: 120, velocity: 0, width: width))
        #expect(SwipeToDismiss.shouldDismiss(offset: 300, velocity: 0, width: width))
    }

    @Test func aShortSlowDragSpringsBack() {
        #expect(!SwipeToDismiss.shouldDismiss(offset: 100, velocity: 200, width: width))
        #expect(!SwipeToDismiss.shouldDismiss(offset: 0, velocity: 0, width: width))
    }

    @Test func aFastFlickDismissesFromAShortDistance() {
        #expect(SwipeToDismiss.shouldDismiss(offset: 40, velocity: 900, width: width))
    }

    @Test func aTwitchOrAFlickToTheLeftDoesNot() {
        #expect(!SwipeToDismiss.shouldDismiss(offset: 8, velocity: 2000, width: width))
        #expect(!SwipeToDismiss.shouldDismiss(offset: -60, velocity: -900, width: width))
    }

    @Test func followsToTheRightOnly() {
        #expect(SwipeToDismiss.position(for: 50) == 50)
        #expect(SwipeToDismiss.position(for: -50) == 0)
    }

    @Test func fadesAsItMovesAway() {
        #expect(SwipeToDismiss.opacity(offset: 0, width: width) == 1)
        #expect(SwipeToDismiss.opacity(offset: -40, width: width) == 1)
        #expect(abs(SwipeToDismiss.opacity(offset: 170, width: width) - 0.65) < 0.0001)
        #expect(abs(SwipeToDismiss.opacity(offset: 1000, width: width) - 0.3) < 0.0001)
    }
}
