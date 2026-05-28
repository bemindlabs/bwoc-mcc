import Foundation

public enum BwocCliError: Error, CustomStringConvertible {
    case binaryNotFound
    case nonZeroExit(code: Int32, stderr: String)
    case decodeFailed(String)

    public var description: String {
        switch self {
        case .binaryNotFound:
            return "`bwoc` binary not found on PATH"
        case .nonZeroExit(let code, let stderr):
            return "bwoc exited \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .decodeFailed(let msg):
            return "decode failed: \(msg)"
        }
    }
}

public actor BwocCli {
    public static let shared = BwocCli()

    private static let candidatePaths: [String] = [
        "/opt/homebrew/bin/bwoc",
        "/usr/local/bin/bwoc",
        NSString(string: "~/.local/bin/bwoc").expandingTildeInPath,
        NSString(string: "~/.cargo/bin/bwoc").expandingTildeInPath
    ]

    private let binaryURL: URL?

    public init() {
        self.binaryURL = Self.candidatePaths
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public func list() async throws -> FleetSnapshot {
        let data = try await runJson(args: ["list", "--json"])
        do {
            return try JSONDecoder().decode(FleetSnapshot.self, from: data)
        } catch {
            throw BwocCliError.decodeFailed(String(describing: error))
        }
    }

    private func runJson(args: [String]) async throws -> Data {
        guard let binaryURL else { throw BwocCliError.binaryNotFound }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = args
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            throw BwocCliError.nonZeroExit(code: process.terminationStatus, stderr: errStr)
        }

        return stdout.fileHandleForReading.readDataToEndOfFile()
    }
}
