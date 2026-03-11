import Foundation

struct TodoRepositoryLoadResult: Equatable {
    let document: TodoDocument
    let recoveryIssue: TodoRepositoryRecoveryIssue?
}

enum TodoRepositoryRecoveryIssue: LocalizedError, Equatable {
    case invalidJSON(path: String)

    var errorDescription: String? {
        switch self {
        case let .invalidJSON(path):
            return "The todo file at \(path) could not be parsed."
        }
    }
}

enum TodoRepositoryError: LocalizedError {
    case failedToCreateDirectory(URL, underlying: Error)
    case failedToRead(URL, underlying: Error)
    case failedToEncode(underlying: Error)
    case failedToSave(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case let .failedToCreateDirectory(url, underlying):
            return "Failed to create parent directory for \(url.path): \(underlying.localizedDescription)"
        case let .failedToRead(url, underlying):
            return "Failed to read todo document at \(url.path): \(underlying.localizedDescription)"
        case let .failedToEncode(underlying):
            return "Failed to encode todo document: \(underlying.localizedDescription)"
        case let .failedToSave(url, underlying):
            return "Failed to save todo document at \(url.path): \(underlying.localizedDescription)"
        }
    }
}

protocol TodoRepository {
    var fileURL: URL { get }

    func load() throws -> TodoRepositoryLoadResult
    func save(_ document: TodoDocument) throws
}

struct JSONTodoRepository: TodoRepository {
    let fileURL: URL
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        fileURL: URL = JSONTodoRepository.defaultFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    func load() throws -> TodoRepositoryLoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return TodoRepositoryLoadResult(document: .empty(), recoveryIssue: nil)
        }

        do {
            let data = try Data(contentsOf: fileURL)
            do {
                let document = try decoder.decode(TodoDocument.self, from: data)
                return TodoRepositoryLoadResult(document: document, recoveryIssue: nil)
            } catch {
                return TodoRepositoryLoadResult(
                    document: .empty(),
                    recoveryIssue: .invalidJSON(path: fileURL.path)
                )
            }
        } catch {
            throw TodoRepositoryError.failedToRead(fileURL, underlying: error)
        }
    }

    func save(_ document: TodoDocument) throws {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw TodoRepositoryError.failedToCreateDirectory(
                fileURL.deletingLastPathComponent(),
                underlying: error
            )
        }

        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw TodoRepositoryError.failedToEncode(underlying: error)
        }

        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw TodoRepositoryError.failedToSave(fileURL, underlying: error)
        }
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport
            .appendingPathComponent("TodoPi", isDirectory: true)
            .appendingPathComponent("todos.json", isDirectory: false)
    }
}
