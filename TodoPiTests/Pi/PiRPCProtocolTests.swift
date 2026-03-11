import XCTest
@testable import TodoPi

final class PiRPCProtocolTests: XCTestCase {
    func testFramerParsesMultipleMessagesAcrossChunks() throws {
        var framer = PiJSONLFramer()

        let firstChunk = Data("{\"id\":\"1\",\"type\":\"response\",\"command\":\"get_commands\",\"success\":true}\n{\"type\":\"agent_start\"".utf8)
        let secondChunk = Data("}\n".utf8)

        let firstMessages = try framer.append(firstChunk)
        let secondMessages = try framer.append(secondChunk)

        XCTAssertEqual(firstMessages, [
            .response(PiRPCResponse(id: "1", command: "get_commands", success: true, error: nil, data: nil))
        ])
        XCTAssertEqual(secondMessages, [
            .event(.agentStart)
        ])
    }

    func testFramerAcceptsCRLFRecords() throws {
        var framer = PiJSONLFramer()

        let messages = try framer.append(Data("{\"type\":\"turn_start\"}\r\n".utf8))

        XCTAssertEqual(messages, [.event(.turnStart)])
    }

    func testParseReturnsUnknownEventForUnsupportedType() throws {
        let message = try PiRPCProtocol.parse(line: Data("{\"type\":\"mystery_event\"}".utf8))

        XCTAssertEqual(message, .event(.unknown("mystery_event")))
    }

    func testParseReturnsAssistantTextDeltaEvent() throws {
        let line = Data("{\"type\":\"message_update\",\"assistantMessageEvent\":{\"type\":\"text_delta\",\"delta\":\"Hello\"}}".utf8)

        let message = try PiRPCProtocol.parse(line: line)

        XCTAssertEqual(message, .event(.messageUpdate(.textDelta("Hello"))))
    }

    func testParseExtractsAssistantTextFromMessageEnd() throws {
        let line = Data("{\"type\":\"message_end\",\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"Hello\"},{\"type\":\"text\",\"text\":\" world\"}]}}".utf8)

        let message = try PiRPCProtocol.parse(line: line)

        XCTAssertEqual(message, .event(.messageEnd(role: "assistant", text: "Hello world")))
    }
}
