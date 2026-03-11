import Foundation

enum PiDebugLog {
    private static let queue = DispatchQueue(label: "TodoPi.PiDebugLog")
    private static let formatter = ISO8601DateFormatter()
    private static let logURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("pi-todo.log", isDirectory: false)

    static func write(_ message: String, source: String = "app") {
        let line = "\(formatter.string(from: Date())) [\(source)] \(message)\n"
        queue.async {
            append(line)
        }
    }

    private static func append(_ line: String) {
        let data = Data(line.utf8)

        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: data)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else {
            return
        }

        defer {
            try? handle.close()
        }

        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }
}
