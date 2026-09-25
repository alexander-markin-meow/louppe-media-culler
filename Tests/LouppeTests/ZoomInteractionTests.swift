import AppKit
import XCTest
@testable import Louppe

@MainActor
final class ZoomInteractionTests: XCTestCase {
    func testNativeFitRecognizerEndsOnceAndCancelledPinchCanRestart() {
        _ = NSApplication.shared
        let window = makeWindow(size: CGSize(width: 400, height: 200))
        let fitted = FittedImageDoubleClickView(frame: window.contentView!.bounds)
        window.contentView = fitted
        var reports: [(factor: CGFloat, ended: Bool)] = []
        fitted.onMagnify = { _, factor, _, ended in
            reports.append((factor, ended))
        }
        let recognizer = SimulatedMagnificationRecognizer()
        recognizer.reportedLocation = CGPoint(x: 100, y: 50)

        recognizer.reportedState = .began
        recognizer.reportedMagnification = 0
        fitted.handleMagnification(recognizer)
        recognizer.reportedState = .changed
        recognizer.reportedMagnification = 0.35
        fitted.handleMagnification(recognizer)
        recognizer.reportedState = .ended
        recognizer.reportedMagnification = 0.5
        fitted.handleMagnification(recognizer)

        XCTAssertEqual(reports.filter { $0.ended }.count, 1)
        XCTAssertEqual(reports.last?.factor ?? -1, 1.5, accuracy: 0.001)
        XCTAssertTrue(reports.last?.ended == true)
        let countAfterEnd = reports.count
        fitted.handleMagnification(recognizer)
        XCTAssertEqual(reports.count, countAfterEnd, "A duplicate native end must not hand off twice")

        recognizer.reportedState = .began
        recognizer.reportedMagnification = 0
        fitted.handleMagnification(recognizer)
        recognizer.reportedState = .changed
        recognizer.reportedMagnification = 0.25
        fitted.handleMagnification(recognizer)
        recognizer.reportedState = .cancelled
        fitted.handleMagnification(recognizer)
        XCTAssertEqual(reports.filter { $0.ended }.count, 1)
        XCTAssertEqual(reports.last?.factor ?? -1, 1, accuracy: 0.001)
        let countAfterCancel = reports.count
        fitted.handleMagnification(recognizer)
        XCTAssertEqual(reports.count, countAfterCancel)

        recognizer.reportedState = .began
        recognizer.reportedMagnification = 0
        fitted.handleMagnification(recognizer)
        recognizer.reportedState = .ended
        recognizer.reportedMagnification = 0.2
        fitted.handleMagnification(recognizer)
        XCTAssertEqual(reports.filter { $0.ended }.count, 2)
        XCTAssertEqual(reports.last?.factor ?? -1, 1.2, accuracy: 0.001)
    }

    func testNativeScrollPinchEndReleasesConfigurationGuardOnce() {
        _ = NSApplication.shared
        let window = makeWindow(size: CGSize(width: 320, height: 240))
        let scrollView = ActualSizeScrollView(frame: window.contentView!.bounds)
        window.contentView = scrollView
        defer { scrollView.prepareForRemoval() }
        let item = makeItem("PENDING.JPG")
        let viewport = ActualSizeViewport()
        var endings = 0
        func configure(_ scale: CGFloat) {
            scrollView.configure(
                item: item,
                preview: nil,
                showsClippingWarnings: false,
                viewport: viewport,
                onLoading: { _ in },
                zoomScale: scale,
                onZoomScaleChanged: { _, ended in
                    if ended { endings += 1 }
                }
            )
        }

        configure(0.5)
        XCTAssertEqual(scrollView.magnification, 0.5, accuracy: 0.001)
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveMagnifyNotification,
            object: scrollView
        )
        configure(1.5)
        XCTAssertEqual(scrollView.magnification, 0.5, accuracy: 0.001)
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )
        XCTAssertEqual(endings, 1)
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )
        XCTAssertEqual(endings, 1)
        configure(1.5)
        XCTAssertEqual(scrollView.magnification, 1.5, accuracy: 0.001)
    }

    func testCanvasDragPansAtHalfAndOneAndHalfZoomAndClamps() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("louppe-zoom-pan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("PAN.JPG")
        // Leave room for the first unconstrained drag even at 50% on Retina.
        try writeJPEG(width: 3000, height: 2400, to: url)

        let window = makeWindow(size: CGSize(width: 320, height: 240))
        let scrollView = ActualSizeScrollView(frame: window.contentView!.bounds)
        window.contentView = scrollView
        defer { scrollView.prepareForRemoval() }
        let item = makeItem("PAN.JPG", url: url)
        let viewport = ActualSizeViewport()

        for scale in [CGFloat(0.5), 1.5] {
            scrollView.configure(
                item: item,
                preview: nil,
                showsClippingWarnings: false,
                viewport: viewport,
                onLoading: { _ in },
                zoomScale: scale
            )
            try await waitForScrollableDocument(in: scrollView)
            XCTAssertEqual(scrollView.magnification, scale, accuracy: 0.001)
            let canvas = try XCTUnwrap(scrollView.documentView)
            scrollView.contentView.scroll(to: CGPoint(x: 100, y: 100))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            let start = scrollView.contentView.bounds.origin
            let startPoint = CGPoint(x: 160, y: 120)
            let draggedPoint = CGPoint(x: 200, y: 150)

            canvas.mouseDown(with: try mouseEvent(
                .leftMouseDown, in: window, at: startPoint, number: 1
            ))
            canvas.mouseDragged(with: try mouseEvent(
                .leftMouseDragged, in: window, at: draggedPoint, number: 2
            ))
            let moved = scrollView.contentView.bounds.origin
            XCTAssertEqual(moved.x, start.x - 40 / scale, accuracy: 1)
            XCTAssertEqual(moved.y, start.y + 30 / scale, accuracy: 1)

            let farPoint = CGPoint(x: 10000, y: 10000)
            canvas.mouseDragged(with: try mouseEvent(
                .leftMouseDragged, in: window, at: farPoint, number: 3
            ))
            let clamped = scrollView.contentView.bounds.origin
            let maximumY = max(0, canvas.frame.height - scrollView.contentView.bounds.height)
            XCTAssertEqual(clamped.x, 0, accuracy: 1)
            XCTAssertEqual(clamped.y, maximumY, accuracy: 1)
            canvas.mouseUp(with: try mouseEvent(
                .leftMouseUp, in: window, at: farPoint, number: 4
            ))
            scrollView.movePhotoPan(to: startPoint)
            XCTAssertEqual(scrollView.contentView.bounds.origin.x, clamped.x, accuracy: 1)
            XCTAssertEqual(scrollView.contentView.bounds.origin.y, clamped.y, accuracy: 1)
        }
    }

    private func makeWindow(size: CGSize) -> NSWindow {
        NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
    }

    private func makeItem(_ id: String, url: URL? = nil) -> PhotoItem {
        PhotoItem(primaryFile: PhotoFile(
            id: id,
            url: url ?? URL(fileURLWithPath: "/tmp/\(id)"),
            captureDate: nil,
            cameraModel: nil,
            lensModel: nil,
            fileSize: 1
        ))
    }

    private func writeJPEG(width: Int, height: Int, to url: URL) throws {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let data = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: 0.2]
        ) else {
            throw NSError(domain: "ZoomInteractionTests", code: 1)
        }
        try data.write(to: url, options: .atomic)
    }

    private func waitForScrollableDocument(
        in scrollView: ActualSizeScrollView
    ) async throws {
        for _ in 0..<200 {
            scrollView.layoutSubtreeIfNeeded()
            let size = scrollView.documentView?.frame.size ?? .zero
            if size.width > scrollView.contentView.bounds.width + 1,
               size.height > scrollView.contentView.bounds.height + 1 {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Photo canvas did not become scrollable")
        throw NSError(domain: "ZoomInteractionTests", code: 2)
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        in window: NSWindow,
        at point: CGPoint,
        number: Int
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: number,
            clickCount: 1,
            pressure: 1
        ))
    }
}

private final class SimulatedMagnificationRecognizer: NSMagnificationGestureRecognizer {
    var reportedState: NSGestureRecognizer.State = .possible
    var reportedLocation: CGPoint = .zero
    var reportedMagnification: CGFloat = 0

    override var state: NSGestureRecognizer.State {
        get { reportedState }
        set { reportedState = newValue }
    }

    override func location(in view: NSView?) -> NSPoint {
        reportedLocation
    }

    override var magnification: CGFloat {
        get { reportedMagnification }
        set { reportedMagnification = newValue }
    }
}
