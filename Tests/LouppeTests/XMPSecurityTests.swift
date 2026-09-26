import Foundation
import XCTest
@testable import Louppe

final class XMPSecurityTests: XCTestCase {
    private let metadata = XMPPublicationMetadata(
        decision: .yes, stars: .three, colorLabel: .purple, profile: .universal
    )

    private func packet(_ contents: String) -> String {
        """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:t="https://example.invalid/test/">
        \(contents)
        </rdf:Description></rdf:RDF></x:xmpmeta>
        """
    }

    func testDeepPacketsFailWithoutCrashingAndNextPacketStillWorks() throws {
        let xml = packet(String(repeating: "<t:n>", count: 100_000)
            + String(repeating: "</t:n>", count: 100_000))
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
            let data = try XCTUnwrap(xml.data(using: encoding))
            XCTAssertThrowsError(try XMPFieldMapping.merge(packet: data, metadata: metadata)) { error in
                XCTAssertTrue(error.localizedDescription.contains("too complex"), "\(error)")
            }
            let valid = try XMPFieldMapping.merge(packet: nil, metadata: metadata)
            try XMPFieldMapping.verify(packet: valid, metadata: metadata)
        }
    }

    func testWideTreeAndExcessiveAttributesAreBounded() {
        for body in [
            "<t:list><rdf:Bag>" + String(repeating: "<rdf:li>x</rdf:li>", count: 130_000) + "</rdf:Bag></t:list>",
            "<t:value " + (0..<1025).map { "t:a\($0)=\"x\"" }.joined(separator: " ") + "/>"
        ] {
            XCTAssertThrowsError(try XMPFieldMapping.merge(packet: Data(packet(body).utf8), metadata: metadata)) { error in
                XCTAssertTrue(error.localizedDescription.contains("too complex"), "\(error)")
            }
        }
    }

    func testNormalUnicodeAndLargeKeywordListsRemainReadable() throws {
        let body = "<t:list><rdf:Bag>" + (0..<5000).map {
            "<rdf:li>Photo \($0) — København 📷 &amp; family</rdf:li>"
        }.joined() + "</rdf:Bag></t:list>"
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
            let data = try XCTUnwrap(packet(body).data(using: encoding))
            let merged = try XMPFieldMapping.merge(packet: data, metadata: metadata)
            try XMPFieldMapping.verify(packet: merged, metadata: metadata)
            XCTAssertTrue(String(decoding: merged, as: UTF8.self).contains("København"))
        }
    }

    func testDoctypeAndMalformedUTF16FailWithoutPoisoningParser() throws {
        let hostile = "<!DOCTYPE x [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]>" + packet("<t:value>&secret;</t:value>")
        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
            XCTAssertThrowsError(try XMPFieldMapping.merge(packet: hostile.data(using: encoding), metadata: metadata))
        }
        var malformed = Data([0xff, 0xfe])
        malformed.append(packet("<t:value>ok</t:value>").data(using: .utf16LittleEndian)!)
        malformed.append(0x00)
        XCTAssertThrowsError(try XMPFieldMapping.merge(packet: malformed, metadata: metadata))
        try XMPFieldMapping.verify(packet: XMPFieldMapping.merge(packet: nil, metadata: metadata), metadata: metadata)
    }
}
