import Foundation

/// JSON persistence for `TaskList`. A corrupt file is moved aside, never overwritten silently.
public struct TaskPersistence {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func defaultURL(appName: String = "DailyWorkspace") throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tasks.json")
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public func load() throws -> TaskList {
        guard FileManager.default.fileExists(atPath: url.path) else { return TaskList() }
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(TaskList.self, from: data)
        } catch {
            let aside = url.deletingLastPathComponent().appendingPathComponent(
                "tasks.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return TaskList()
        }
    }

    public func save(_ list: TaskList) throws {
        let data = try encoder.encode(list)
        try data.write(to: url, options: .atomic)
    }
}
