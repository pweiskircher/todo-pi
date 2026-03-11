import Foundation

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    init(any value: Any) throws {
        switch value {
        case let value as String:
            self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else {
                self = .number(value.doubleValue)
            }
        case let value as [String: Any]:
            self = .object(try value.mapValues(JSONValue.init(any:)))
        case let value as [Any]:
            self = .array(try value.map(JSONValue.init(any:)))
        default:
            self = .null
        }
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case let .number(value) = self else { return nil }
        return Int(exactly: value)
    }

    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }
}

enum PiRPCCommand {
    static func getCommands(id: String) -> [String: Any] {
        [
            "id": id,
            "type": "get_commands"
        ]
    }

    static func prompt(id: String, message: String) -> [String: Any] {
        [
            "id": id,
            "type": "prompt",
            "message": message
        ]
    }
}

struct PiRPCResponse: Equatable {
    let id: String?
    let command: String
    let success: Bool
    let error: String?
    let data: JSONValue?
}

enum PiAssistantMessageEvent: Equatable {
    case start
    case textStart
    case textDelta(String)
    case textEnd(String?)
    case thinkingStart
    case thinkingDelta(String)
    case thinkingEnd(String?)
    case toolCallStart(String?)
    case toolCallDelta(String)
    case toolCallEnd(String?)
    case done(String?)
    case error(String?)
}

enum PiRPCEvent: Equatable {
    case agentStart
    case agentEnd
    case turnStart
    case turnEnd(role: String?, text: String?)
    case messageStart(role: String?)
    case messageUpdate(PiAssistantMessageEvent)
    case messageEnd(role: String?, text: String?)
    case toolExecutionStart(String)
    case toolExecutionEnd(String, isError: Bool)
    case extensionError(String)
    case unknown(String)
}

enum PiRPCMessage: Equatable {
    case response(PiRPCResponse)
    case event(PiRPCEvent)
}

enum PiRPCProtocolError: LocalizedError, Equatable {
    case invalidUTF8
    case missingType
    case invalidResponse(String)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .invalidUTF8:
            return "RPC stream contained invalid UTF-8."
        case .missingType:
            return "RPC message is missing a type field."
        case let .invalidResponse(reason):
            return "Invalid RPC response: \(reason)"
        case let .invalidJSON(reason):
            return "Invalid RPC JSON: \(reason)"
        }
    }
}

struct PiJSONLFramer {
    private var buffer = Data()

    mutating func append(_ data: Data) throws -> [PiRPCMessage] {
        buffer.append(data)

        var messages: [PiRPCMessage] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var line = buffer[..<newlineIndex]
            buffer.removeSubrange(...newlineIndex)

            if line.last == 0x0D {
                line = line.dropLast()
            }

            guard !line.isEmpty else {
                continue
            }

            messages.append(try PiRPCProtocol.parse(line: Data(line)))
        }

        return messages
    }
}

enum PiRPCProtocol {
    static func parse(line: Data) throws -> PiRPCMessage {
        guard let text = String(data: line, encoding: .utf8) else {
            throw PiRPCProtocolError.invalidUTF8
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: line)
        } catch {
            throw PiRPCProtocolError.invalidJSON(error.localizedDescription)
        }

        guard let object = jsonObject as? [String: Any] else {
            throw PiRPCProtocolError.invalidJSON("Top-level JSON must be an object")
        }

        guard let type = object["type"] as? String else {
            throw PiRPCProtocolError.missingType
        }

        if type == "response" {
            guard let command = object["command"] as? String else {
                throw PiRPCProtocolError.invalidResponse("missing command")
            }
            guard let success = object["success"] as? Bool else {
                throw PiRPCProtocolError.invalidResponse("missing success flag")
            }
            let dataValue = try (object["data"].map(JSONValue.init(any:)))
            return .response(
                PiRPCResponse(
                    id: object["id"] as? String,
                    command: command,
                    success: success,
                    error: object["error"] as? String,
                    data: dataValue
                )
            )
        }

        switch type {
        case "agent_start":
            return .event(.agentStart)
        case "agent_end":
            return .event(.agentEnd)
        case "turn_start":
            return .event(.turnStart)
        case "turn_end":
            return .event(.turnEnd(role: extractMessageRole(from: object["message"]), text: extractMessageText(from: object["message"])))
        case "message_start":
            return .event(.messageStart(role: extractMessageRole(from: object["message"])))
        case "message_update":
            guard let assistantMessageEvent = object["assistantMessageEvent"] as? [String: Any],
                  let eventType = assistantMessageEvent["type"] as? String else {
                return .event(.unknown("message_update"))
            }
            return .event(.messageUpdate(parseAssistantMessageEvent(type: eventType, payload: assistantMessageEvent)))
        case "message_end":
            return .event(.messageEnd(role: extractMessageRole(from: object["message"]), text: extractMessageText(from: object["message"])))
        case "tool_execution_start":
            return .event(.toolExecutionStart(object["toolName"] as? String ?? "unknown"))
        case "tool_execution_end":
            return .event(.toolExecutionEnd(object["toolName"] as? String ?? "unknown", isError: object["isError"] as? Bool ?? false))
        case "extension_error":
            return .event(.extensionError(object["error"] as? String ?? text))
        default:
            return .event(.unknown(type))
        }
    }

    private static func parseAssistantMessageEvent(type: String, payload: [String: Any]) -> PiAssistantMessageEvent {
        switch type {
        case "start":
            return .start
        case "text_start":
            return .textStart
        case "text_delta":
            return .textDelta(payload["delta"] as? String ?? "")
        case "text_end":
            return .textEnd(payload["content"] as? String)
        case "thinking_start":
            return .thinkingStart
        case "thinking_delta":
            return .thinkingDelta(payload["delta"] as? String ?? "")
        case "thinking_end":
            return .thinkingEnd(payload["content"] as? String)
        case "toolcall_start":
            let toolName = (payload["partial"] as? [String: Any])?["name"] as? String
            return .toolCallStart(toolName)
        case "toolcall_delta":
            return .toolCallDelta(payload["delta"] as? String ?? "")
        case "toolcall_end":
            let toolName = (payload["toolCall"] as? [String: Any])?["name"] as? String
            return .toolCallEnd(toolName)
        case "done":
            return .done(payload["reason"] as? String)
        case "error":
            return .error(payload["reason"] as? String ?? payload["error"] as? String)
        default:
            return .error(type)
        }
    }

    private static func extractMessageRole(from value: Any?) -> String? {
        (value as? [String: Any])?["role"] as? String
    }

    private static func extractMessageText(from value: Any?) -> String? {
        guard let message = value as? [String: Any], let content = message["content"] else {
            return nil
        }

        if let content = content as? String {
            return content
        }

        guard let blocks = content as? [[String: Any]] else {
            return nil
        }

        let text = blocks.compactMap { block -> String? in
            guard let type = block["type"] as? String, type == "text" else {
                return nil
            }
            return block["text"] as? String
        }.joined()

        return text.isEmpty ? nil : text
    }
}
