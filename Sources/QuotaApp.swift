import SwiftUI
import WidgetKit
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    var reopen: (() -> Void)?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopen?()
        return true
    }
    func applyDockVisibility(hidden: Bool) {
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
        if let icon = ApplicationArtwork.image { NSApp.applicationIconImage = icon }
    }
}

enum ApplicationArtwork {
    static var image: NSImage? {
        guard let url = Bundle.main.url(forResource: "QuotaAppIcon-v6", withExtension: "icns") else { return nil }
        return NSImage(contentsOf: url)
    }
}

@MainActor
final class QuotaModel: ObservableObject {
    @Published var snapshot = SnapshotStore.read()
    @Published var busy = false
    @Published var message: String?
    @Published var resolvedPath: String?
    @Published var selectionError: String?
    private var refreshPending = false
    private let server = LocalQuotaServer()
    private var polling: Task<Void, Never>?
    func start() {
        if let icon = ApplicationArtwork.image { NSApp.applicationIconImage = icon }
        guard polling == nil else { return }
        do { try server.start(snapshot: snapshot) } catch { message = "无法启动本机同步服务：\(error.localizedDescription)" }
        polling = Task {
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(300)) } catch { break }
            }
        }
    }
    func refresh() async {
        guard !busy else { refreshPending = true; return }
        busy = true
        defer { busy = false }
        repeat {
            refreshPending = false
            do {
                let executable = try CodexClient.executable()
                resolvedPath = executable.path
                let value = try await Task.detached { try CodexClient.fetch(executable: executable) }.value
                snapshot = value
                message = value.error
            } catch {
                if (try? CodexClient.executable()) == nil { resolvedPath = nil }
                snapshot.error = error.localizedDescription
                message = error.localizedDescription
            }
            server.update(snapshot)
            do { try SnapshotStore.write(snapshot); WidgetCenter.shared.reloadAllTimelines() }
            catch { message = error.localizedDescription }
        } while refreshPending
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
            UserDefaults.standard.set(path, forKey: "codexPath")
            selectionError = nil
            Task { await refresh() }
        } catch { selectionError = error.localizedDescription }
    }
    func restoreAutomaticLocation() {
        UserDefaults.standard.removeObject(forKey: "codexPath")
        selectionError = nil
        Task { await refresh() }
    }

}
struct Dashboard: View {
    @ObservedObject var model: QuotaModel
    @AppStorage("codexPath") private var codexPath = ""
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    @AppStorage("hideMenuBarIcon") private var hideMenuBarIcon = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("每周，心中有数。").font(.title2.bold())
                    Text("Codex 周额度").foregroundStyle(.secondary)
                }
                Spacer()
                if let icon = ApplicationArtwork.image {
                    Image(nsImage: icon).resizable().interpolation(.high)
                        .frame(width: 48, height: 48)
                        .accessibilityLabel("Codex 周额度")
                }
            }
            QuotaView(snapshot: model.snapshot).padding(24)
                .background(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.clear, in: RoundedRectangle(cornerRadius: 26))
                .glassEffect(.regular, in: .rect(cornerRadius: 26))
            HStack {
                Button { Task { await model.refresh() } } label: {
                    Label(model.busy ? "正在同步…" : "立即同步", systemImage: "arrow.clockwise")
                }.buttonStyle(.glassProminent).disabled(model.busy)
                Spacer()
                Text("每 5 分钟自动同步").font(.caption).foregroundStyle(.secondary)
            }
            if let message = model.message { Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            Divider()
            Text("添加到桌面").font(.headline)
            Text("右键桌面 → 编辑小组件 → 搜索「Codex 周额度」。支持小号与中号，外观跟随系统的全彩、着色和透明模式。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 10) {
                Text("后台运行").font(.headline)
                Toggle("隐藏程序坞图标", isOn: $hideDockIcon)
                Toggle("隐藏顶部菜单栏图标", isOn: $hideMenuBarIcon)
                Text("隐藏图标后仍会同步。点击桌面小组件，或从访达重新打开应用，即可返回此窗口。设置会自动保存。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if hideDockIcon || hideMenuBarIcon {
                        Button("恢复全部图标") { hideDockIcon = false; hideMenuBarIcon = false }
                    }
                    Spacer()
                    Button("退出应用") { NSApp.terminate(nil) }
                }.controlSize(.small)
            }
            DisclosureGroup("连接设置") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(codexPath.isEmpty ? "自动查找" : "手动选择").font(.caption.bold())
                    if !codexPath.isEmpty {
                        Text("已选：" + codexPath).font(.caption).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("选择应用…") { model.selectLocation(application: true) }
                        Button("选择可执行文件…") { model.selectLocation(application: false) }
                    }.controlSize(.small)
                    Button("恢复自动查找") { model.restoreAutomaticLocation() }
                        .controlSize(.small).disabled(codexPath.isEmpty)
                    if let path = model.resolvedPath {
                        Text("使用中：" + path).font(.caption).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(model.busy ? "正在同步…" : (model.message == nil && model.snapshot.error == nil ? "连接正常" : "同步失败"))
                        .font(.caption)
                    if let date = model.snapshot.fetchedAt {
                        Text("最近成功：" + date.formatted(date: .abbreviated, time: .standard)).font(.caption)
                    }
                    if let error = model.selectionError {
                        Text(error).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("使用本机 Codex 已登录的账号。配套应用需保持运行；退出后小组件显示上次同步数据。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
        }.padding(28).frame(width: 410)
        }.frame(width: 410, height: min(760, (NSScreen.main?.visibleFrame.height ?? 860) - 100))
    }
}
struct DashboardRoot: View {
    @ObservedObject var model: QuotaModel
    let delegate: ApplicationDelegate
    @Environment(\.openWindow) private var openWindow
    @AppStorage("hideDockIcon") private var hideDockIcon = false
    var body: some View {
        Dashboard(model: model)
            .onAppear {
                delegate.reopen = {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .task { model.start() }
            .onChange(of: hideDockIcon, initial: true) { _, hidden in
                delegate.applyDockVisibility(hidden: hidden)
            }
            .onOpenURL { url in
                guard url.scheme == "codexquota" else { return }
                delegate.reopen?()
                Task { await model.refresh() }
            }
    }
}

@main
struct QuotaApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var delegate
    @StateObject private var model = QuotaModel()
    @AppStorage("hideMenuBarIcon") private var hideMenuBarIcon = false
    var body: some Scene {
        Window("Codex 周额度", id: "dashboard") {
            DashboardRoot(model: model, delegate: delegate)
        }.windowResizability(.contentSize)
        MenuBarExtra("Codex 周额度", systemImage: "chart.pie", isInserted: Binding(
            get: { !hideMenuBarIcon }, set: { hideMenuBarIcon = !$0 }
        )) {
            Button("立即同步") { Task { await model.refresh() } }
            Button("显示窗口") { delegate.reopen?() }
            Divider()
            Button("退出") { NSApp.terminate(nil) }
        }
    }
}
