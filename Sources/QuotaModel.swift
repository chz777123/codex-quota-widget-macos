import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WidgetKit

@MainActor
final class QuotaModel: ObservableObject {
    @Published var snapshot: Snapshot
    @Published var weeklyBusy = false
    @Published var dailyBusy = false
    var busy: Bool { weeklyBusy || dailyBusy }
    @Published var message: String?
    @Published var resolvedPath: String?
    @Published var selectionError: String?
    private var weeklyPending = false
    private var dailyPending = false
    private let server = LocalQuotaServer()
    private let reader: UsageReader
    private let defaults: UserDefaults
    private let weeklyFetch: @Sendable () throws -> Snapshot
    private let persist: (Snapshot) throws -> Void
    private var weeklyPolling: Task<Void, Never>?
    private var dailyPolling: Task<Void, Never>?

    init(snapshot: Snapshot = SnapshotStore.read(), defaults: UserDefaults = .standard,
         reader: UsageReader? = nil,
         weeklyFetch: @escaping @Sendable () throws -> Snapshot = { try CodexClient.fetch() },
         persist: @escaping (Snapshot) throws -> Void = { try SnapshotStore.write($0); WidgetCenter.shared.reloadAllTimelines() }) {
        self.snapshot = snapshot
        self.defaults = defaults
        self.weeklyFetch = weeklyFetch
        self.persist = persist
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.reader = reader ?? UsageReader(cacheURL: base.appendingPathComponent("CodexQuota/usage-index.json"))
    }
    func start() {
        guard weeklyPolling == nil else { return }
        do { try server.start(snapshot: snapshot) } catch { message = "无法启动本机同步服务：\(error.localizedDescription)" }
        weeklyPolling = Task {
            while !Task.isCancelled {
                await refreshWeekly()
                do { try await Task.sleep(for: .seconds(300)) } catch { break }
            }
        }
        dailyPolling = Task {
            while !Task.isCancelled {
                await refreshDaily()
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
            }
        }
    }
    func refresh() async {
        async let weekly: Void = refreshWeekly()
        async let daily: Void = refreshDaily()
        _ = await (weekly, daily)
    }
    private func publish() {
        server.update(snapshot)
        do { try persist(snapshot) } catch { message = "无法保存同步数据：\(error.localizedDescription)" }
    }
    func refreshWeekly() async {
        guard !weeklyBusy else { weeklyPending = true; return }
        weeklyBusy = true
        defer { weeklyBusy = false }
        repeat {
            weeklyPending = false
            resolvedPath = try? CodexLocation.executable(custom: defaults.string(forKey: "codexPath") ?? "").path
            do {
                let fetch = weeklyFetch
                let value = try await Task.detached { try fetch() }.value
                // Merge only weekly fields. A concurrent daily read must never be overwritten.
                snapshot.weekly = value.weekly
                snapshot.fetchedAt = value.fetchedAt
                snapshot.error = value.error
                message = value.error
            } catch {
                snapshot.error = error.localizedDescription
                message = error.localizedDescription
            }
            publish()
        } while weeklyPending
    }
    func refreshDaily() async {
        guard !dailyBusy else { dailyPending = true; return }
        dailyBusy = true
        defer { dailyBusy = false }
        repeat {
            dailyPending = false
            let root = UsageReader.root(custom: defaults.string(forKey: "codexDataPath") ?? "")
            let result = await reader.read(root: root)
            // Changing directories while scanning queues a new scan; don't publish data from the old root.
            guard root == UsageReader.root(custom: defaults.string(forKey: "codexDataPath") ?? "") else {
                dailyPending = true; continue
            }
            if result.totalTokens == nil, let old = snapshot.dailyUsage, old.isToday(Date()) {
                snapshot.dailyUsage = old
                snapshot.dailyUsage?.isComplete = false
                snapshot.dailyUsage?.error = result.error
            } else { snapshot.dailyUsage = result }
            publish()
        } while dailyPending
    }
    func selectLocation(application: Bool) {
        let panel = NSOpenPanel()
        panel.title = application ? "选择 ChatGPT 或 Codex 应用" : "选择 codex 可执行文件"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = !application
        if application { panel.allowedContentTypes = [.applicationBundle] }
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.saveLocation(url.path) }
        }
    }
    func saveLocation(_ path: String) {
        do {
            _ = try CodexLocation.executable(custom: path)
            defaults.set(path, forKey: "codexPath")
            selectionError = nil
            Task { await refreshWeekly() }
        } catch { selectionError = error.localizedDescription }
    }
    func restoreAutomaticLocation() {
        defaults.removeObject(forKey: "codexPath")
        selectionError = nil
        Task { await refreshWeekly() }
    }
    func selectDataDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择 Codex 数据目录"
        panel.message = "选择含 sessions 或 archived_sessions 的文件夹（通常是 ~/.codex）。"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = UsageReader.root(custom: defaults.string(forKey: "codexDataPath") ?? "")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.saveDataDirectory(url) }
        }
    }
    func saveDataDirectory(_ url: URL) {
        do {
            try UsageReader.validateRoot(url)
            defaults.set(url.path, forKey: "codexDataPath")
            selectionError = nil
            snapshot.dailyUsage = nil
            publish()
            Task { await refreshDaily() }
        } catch { selectionError = error.localizedDescription }
    }
    func restoreDataDirectory() {
        defaults.removeObject(forKey: "codexDataPath")
        selectionError = nil
        snapshot.dailyUsage = nil
        publish()
        Task { await refreshDaily() }
    }
}
