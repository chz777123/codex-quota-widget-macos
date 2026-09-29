import Foundation
@main struct CheckLocalUsage {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass a temporary index cache path") }
        let reader = UsageReader(cacheURL: URL(fileURLWithPath: CommandLine.arguments[1]))
        let now = Date()
        let start = Date()
        let usage = await reader.read(root: UsageReader.defaultRoot, now: now)
        print(String(data: try JSONEncoder().encode(usage), encoding: .utf8)!)
        print("Initial read seconds:", Date().timeIntervalSince(start), "bytes:", await reader.bytesRead)
        let next = Date()
        let second = await reader.read(root: UsageReader.defaultRoot, now: now)
        print("Incremental seconds:", Date().timeIntervalSince(next), "bytes:", await reader.bytesRead)
        precondition(usage.totalTokens == second.totalTokens)
    }
}
