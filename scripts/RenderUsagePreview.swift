import SwiftUI
import WidgetKit
import AppKit

@main struct RenderUsagePreview {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass a PNG output path") }
        _ = NSApplication.shared
        let now = Date()
        var normal = Snapshot.preview
        normal.dailyUsage = DailyUsage(day: DailyUsage.dayKey(now), timeZone: TimeZone.current.identifier,
            inputTokens: 2_350_000, outputTokens: 130_000, cachedInputTokens: 1_950_500,
            updatedAt: now, isComplete: true,
            averageOutputTokensPerSecond: 87.4, latestOutputTokensPerSecond: 124.8, speedSampleCount: 18)
        var long = normal
        long.weekly = LimitWindow(usedPercent: 94, windowDurationMins: 10080, resetsAt: now.addingTimeInterval(86400).timeIntervalSince1970)
        long.dailyUsage?.inputTokens = 12_350_000_000
        long.dailyUsage?.cachedInputTokens = 12_349_000_000
        long.dailyUsage?.averageOutputTokensPerSecond = 1_250.0
        long.dailyUsage?.latestOutputTokensPerSecond = 8_420.0
        long.dailyUsage?.speedSampleCount = 120
        var missing = normal
        missing.dailyUsage = nil
        var partial = normal
        partial.dailyUsage?.cachedInputTokens = nil
        partial.dailyUsage?.averageOutputTokensPerSecond = nil
        partial.dailyUsage?.latestOutputTokensPerSecond = nil
        partial.dailyUsage?.speedSampleCount = 0
        partial.dailyUsage?.isComplete = false
        partial.dailyUsage?.error = "部分统计 · 有记录缺失或不可读"
        let content = VStack(alignment: .leading, spacing: 22) {
            Text("Codex · 极简仪表盘布局检查").font(.title2.bold())
            Text("全部为示例数据 · 离屏预览；实际液态玻璃材质由 macOS 桌面渲染").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    row("正常 / 浅色", normal, .light)
                    row("长数字、低额度 / 深色", long, .dark)
                    row("统计缺失", missing, .light)
                    row("缓存缺失、部分统计 / 着色", partial, .dark, mode: .accented)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("主窗口数据区域 · 示例").font(.caption)
                    VStack(alignment: .leading, spacing: 24) {
                        Text("每周，心中有数。").font(.title2.bold())
                        QuotaView(snapshot: normal).padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26))
                        DailyUsageDetails(usage: normal.dailyUsage)
                        Button("立即同步") {}.buttonStyle(.borderedProminent)
                    }.padding(28).frame(width: 410).background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 24))
                }
            }
        }.padding(28).background(Color(nsColor: .controlBackgroundColor)).environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage else { fatalError("Cannot render SwiftUI preview") }
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
    @MainActor static func row(_ title: String, _ snapshot: Snapshot, _ scheme: ColorScheme, mode: WidgetRenderingMode = .fullColor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption)
            HStack(spacing: 12) {
                card(snapshot, compact: true, scheme: scheme, mode: mode)
                card(snapshot, compact: false, scheme: scheme, mode: mode)
            }
        }
    }
    @MainActor static func card(_ snapshot: Snapshot, compact: Bool, scheme: ColorScheme, mode: WidgetRenderingMode) -> some View {
        QuotaView(snapshot: snapshot, compact: compact)
            .padding(16).frame(width: compact ? 170 : 354, height: 170)
            .background(scheme == .dark ? Color(white: 0.12) : .white, in: RoundedRectangle(cornerRadius: 24))
            .environment(\.colorScheme, scheme).environment(\.widgetRenderingMode, mode)
    }
}
