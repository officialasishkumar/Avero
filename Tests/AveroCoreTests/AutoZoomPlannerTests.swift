import AveroCore
import CoreGraphics
import Testing

struct AutoZoomPlannerTests {
    @Test
    func plannerReturnsDefaultSnapshotWithoutInteractions() {
        let planner = AutoZoomPlanner(
            duration: 8,
            sourceSize: CGSize(width: 1728, height: 1117),
            interactions: [],
            configuration: AutoZoomConfiguration()
        )

        let snapshot = planner.snapshot(at: 4)

        #expect(snapshot == .default)
    }

    @Test
    func plannerMovesFocusToInteractionPoint() {
        let planner = AutoZoomPlanner(
            duration: 8,
            sourceSize: CGSize(width: 1728, height: 1117),
            interactions: [
                InteractionEvent(timestamp: 2, location: NormalizedPoint(x: 0.2, y: 0.8)),
            ],
            configuration: AutoZoomConfiguration(zoomScale: 2, preRoll: 0.2, holdDuration: 1, releaseDuration: 0.25)
        )

        let snapshot = planner.snapshot(at: 2)

        #expect(snapshot.center == NormalizedPoint(x: 0.2, y: 0.8))
        #expect(snapshot.zoomScale == 2)
    }

    @Test
    func cropRectStaysInsideSourceBounds() {
        let planner = AutoZoomPlanner(
            duration: 8,
            sourceSize: CGSize(width: 1440, height: 900),
            interactions: [
                InteractionEvent(timestamp: 3, location: NormalizedPoint(x: 0.98, y: 0.98)),
            ],
            configuration: AutoZoomConfiguration(zoomScale: 2.2, preRoll: 0.1, holdDuration: 1, releaseDuration: 0.3)
        )

        let rect = planner.cropRect(at: 3)

        #expect(rect.minX >= 0)
        #expect(rect.minY >= 0)
        #expect(rect.maxX <= 1440)
        #expect(rect.maxY <= 900)
    }
}
