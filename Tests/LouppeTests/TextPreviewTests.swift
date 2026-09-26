import AppKit
import SwiftUI
import XCTest
@testable import Louppe

final class TextPreviewTests: XCTestCase {
    private func fixture(_ files: [String: Data]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LouppeText-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        for (name, bytes) in files { try bytes.write(to: root.appendingPathComponent(name)) }
        return root
    }

    func testScanKeepsTextSeparateFromPhotosAndSidecars() throws {
        let root = try fixture([
            "shot.NEF": Data(), "shot.JPG": Data(), "shot.md": Data("note".utf8),
            "readme.TXT": Data(), "data.XML": Data(), "rows.csv": Data(),
            "shot.xmp": Data(), ".louppe_session.json": Data(),
        ])
        let items = try FolderScanner.scan(root, pairingMode: .together) { _ in }
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items.filter(\.isText).count, 4)
        XCTAssertEqual(items.filter { $0.pairedURL != nil }.count, 1)
        XCTAssertTrue(items.filter(\.isText).allSatisfy { $0.isSupported && !$0.hasVisualPreview && !$0.isPlayableMedia })
        var filter = PhotoFilter()
        filter.excludedMediaKinds = [.text]
        XCTAssertEqual(items.filter { PreparedPhotoFilter(filter).matches($0) }.count, 1)
        XCTAssertEqual(PhotoSelectionSummary(items: items).textCount, 4)
    }

    func testPlainTextAndXMLRemainLiteral() async throws {
        let source = "<note>**Literal** &amp; [link](https://example.com)</note>\nSecond line"
        let root = try fixture(["note.xml": Data(source.utf8)])
        let item = try XCTUnwrap(FolderScanner.scan(root) { _ in }.first)
        let text = try await TextPreviewLoader.shared.load(item: item)
        XCTAssertEqual(String(text.characters), source)
        XCTAssertEqual(try Data(contentsOf: item.primaryURL), Data(source.utf8))
        XCTAssertEqual(try FileOperationJournal.captureIdentity(at: item.primaryURL), item.primaryFile.scannedIdentity)
        let thumbnail = await ImagePipeline.shared.thumbnail(for: item)
        let fullImage = await ImagePipeline.shared.fullImage(for: item)
        XCTAssertNil(thumbnail)
        XCTAssertNil(fullImage)
        XCTAssertTrue(text.runs.allSatisfy { $0.link == nil && $0.inlinePresentationIntent == nil })
    }

    @MainActor
    func testMarkdownRendersSerifBoldLinksAndBlockBoundaries() async throws {
        let root = try fixture(["note.md": Data("# Heading\n\nA **bold** and *italic* [link](https://example.com).\n\n- First\n- Second\n\n```xml\n<literal>**not bold**</literal>\n```".utf8)])
        let item = try XCTUnwrap(FolderScanner.scan(root) { _ in }.first)
        let text = try await TextPreviewLoader.shared.load(item: item)
        let rendered = NativeTextPreview.render(text)
        XCTAssertTrue(rendered.string.hasPrefix("Heading\nA bold and italic link."))
        XCTAssertTrue(rendered.string.contains("•  First\n•  Second"))
        XCTAssertTrue(rendered.string.contains("<literal>**not bold**</literal>"))
        let boldOffset = (rendered.string as NSString).range(of: "bold").location
        let font = try XCTUnwrap(rendered.attribute(.font, at: boldOffset, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
        XCTAssertTrue(["New York", "Georgia"].contains(font.familyName ?? ""))
        let linkOffset = (rendered.string as NSString).range(of: "link").location
        XCTAssertEqual(rendered.attribute(.link, at: linkOffset, effectiveRange: nil) as? URL, URL(string: "https://example.com"))
    }

    @MainActor
    func testReaderIsReadOnlySelectableAndScrollable() throws {
        let host = NSHostingView(rootView: NativeTextPreview(text: AttributedString(String(repeating: "Text line\n", count: 100)), filename: "note.txt"))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func findText(_ view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.lazy.compactMap(findText).first
        }
        let view = try XCTUnwrap(findText(host))
        XCTAssertFalse(view.isEditable)
        XCTAssertTrue(view.isSelectable)
        XCTAssertTrue(view.enclosingScrollView?.hasVerticalScroller == true)
        XCTAssertEqual(view.string.components(separatedBy: "\n").count, 101)
        view.layoutManager?.ensureLayout(for: try XCTUnwrap(view.textContainer))
        XCTAssertGreaterThan(view.intrinsicContentSize.height > 0 ? view.intrinsicContentSize.height : view.frame.height, 400)
    }

    func testUnicodeAndInvalidEncoding() throws {
        XCTAssertEqual(try TextPreviewLoader.decode(Data([0xEF, 0xBB, 0xBF]) + Data("héllo".utf8)), "héllo")
        XCTAssertEqual(try TextPreviewLoader.decode(Data([0xFF, 0xFE]) + XCTUnwrap("héllo".data(using: .utf16LittleEndian))), "héllo")
        XCTAssertEqual(try TextPreviewLoader.decode(Data()), "")
        XCTAssertThrowsError(try TextPreviewLoader.decode(Data([0xFF, 0x00, 0x01])))
        XCTAssertThrowsError(try TextPreviewLoader.decode(Data([0x00])))
    }

    func testLargeAndChangedFilesFailVisibly() async throws {
        let root = try fixture(["large.txt": Data(repeating: 65, count: TextPreviewLoader.maximumBytes + 1), "changed.txt": Data("old".utf8)])
        let items = try FolderScanner.scan(root) { _ in }
        let large = try XCTUnwrap(items.first { $0.displayName == "large.txt" })
        do {
            _ = try await TextPreviewLoader.shared.load(item: large)
            XCTFail("Oversized file should fail")
        } catch TextPreviewLoader.PreviewError.tooLarge { }
        let changed = try XCTUnwrap(items.first { $0.displayName == "changed.txt" })
        try Data("new content".utf8).write(to: changed.primaryURL, options: .atomic)
        do {
            _ = try await TextPreviewLoader.shared.load(item: changed)
            XCTFail("Replaced file should require rescan")
        } catch TextPreviewLoader.PreviewError.changed { }
        let rescanned = try XCTUnwrap(FolderScanner.scan(root) { _ in }.first { $0.displayName == "changed.txt" })
        let fresh = try await TextPreviewLoader.shared.load(item: rescanned)
        XCTAssertEqual(String(fresh.characters), "new content")
    }
}
