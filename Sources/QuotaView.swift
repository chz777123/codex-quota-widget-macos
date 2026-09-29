import SwiftUI
import WidgetKit

struct QuotaView: View {
    let snapshot: Snapshot
    var date: Date = Date()
    var compact = false
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var remaining: Double? { snapshot.remaining(at: date) }
    private var today: DailyUsage? { snapshot.dailyUsage.flatMap { $0.isToday(date) ? $0 : nil } }
    private var tint: Color { renderingMode == .accented ? .primary : (remaining ?? 100) <= 20 ? .orange : .mint }
    private var warning: String? {
        if snapshot.expired(at: date) { return "周期已结束 · 待同步" }
        if snapshot.error != nil { return "额度同步失败" }
        if snapshot.stale(at: date) { return "额度数据较旧" }
        if let daily = snapshot.dailyUsage, !daily.isToday(date) { return "今日统计待更新" }
        if let today {
            if today.error != nil || !today.isComplete { return "部分统计 · 打开应用" }
            if today.stale(at: date) { return "今日统计较旧" }
        }
        return nil
    }
    private var cacheText: String {
        today?.cacheHitRate.map { String(format: "%.1f%%", $0) } ?? "—"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 5) {
                Image(systemName: "terminal.fill").widgetAccentable()
                Text("Codex").fontWeight(.semibold)
                Spacer(minLength: 0)
                Text(compact ? "周额度" : "用量概览").foregroundStyle(.secondary)
            }.font(.system(size: compact ? 11 : 12))
            if compact {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    quotaNumber(size: 34)
                    Spacer(minLength: 0)
                    Text("剩余").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                progress
                Text("本机今日").font(.system(size: 9)).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 8) {
                    metric("今日 token", value: TokenFormat.compact(today?.totalTokens), size: 16)
                    Spacer(minLength: 0)
                    metric("缓存率", value: cacheText, size: 16)
                }
            } else {
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("本周剩余").font(.system(size: 11)).foregroundStyle(.secondary)
                        quotaNumber(size: 46)
                        progress
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(.primary.opacity(0.10)).frame(width: 1, height: 83)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("本机今日").font(.system(size: 10)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(TokenFormat.compact(today?.totalTokens)).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text("token").font(.system(size: 10)).foregroundStyle(.secondary)
                        }.lineLimit(1).minimumScaleFactor(0.7)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(cacheText).font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
                            Text("缓存率").font(.system(size: 10)).foregroundStyle(.secondary)
                        }.lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 3) {
                if let warning {
                    Image(systemName: "exclamationmark.circle")
                    Text(warning)
                } else if let reset = snapshot.weekly?.reset {
                    Text(reset, format: compact ? .dateTime.month().day() : .dateTime.month().day().hour().minute())
                    Text("重置")
                } else { Text("打开应用以同步") }
                if !compact, let updated = today?.updatedAt {
                    Spacer(minLength: 2)
                    Text("更新 \(updated.formatted(date: .omitted, time: .shortened))")
                }
            }.font(.system(size: compact ? 9 : 10)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }.privacySensitive()
    }
    private func quotaNumber(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(remaining.map { String(format: "%.0f", $0) } ?? "—")
                .font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
            if remaining != nil { Text("%").font(.system(size: compact ? 16 : 20)).foregroundStyle(.secondary) }
        }.lineLimit(1).minimumScaleFactor(0.7).widgetAccentable()
            .accessibilityLabel(remaining.map { "本周剩余百分之\(Int($0))" } ?? "额度未知")
    }
    private var progress: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.10))
                Capsule().fill(tint).frame(width: geometry.size.width * (remaining ?? 0) / 100).widgetAccentable()
            }
        }.frame(height: compact ? 3 : 4).accessibilityHidden(true)
    }
    private func metric(_ title: String, value: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }.lineLimit(1).minimumScaleFactor(0.75).accessibilityElement(children: .combine)
    }
}
