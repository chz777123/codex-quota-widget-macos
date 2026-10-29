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
    private var cacheText: String { today?.cacheHitRate.map { String(format: "%.1f%%", $0) } ?? "—" }
    private var speedText: String {
        guard let speed = today?.latestOutputTokensPerSecond, speed.isFinite, speed > 0 else { return "—" }
        return TokenFormat.speed(speed) + " tok/s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 8) {
            brandBar
            if compact { smallLayout } else { mediumLayout }
            statusBar
        }
        .privacySensitive()
    }

    private var brandBar: some View {
        HStack(spacing: 5) {
            Image(systemName: "terminal.fill").widgetAccentable()
            Text("Codex").fontWeight(.semibold)
            Spacer(minLength: 0)
            Image(systemName: warning == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(warning == nil ? Color.secondary : Color.orange)
            Text(compact ? "周额度" : "用量概览").foregroundStyle(.secondary)
        }
        .font(.system(size: compact ? 11 : 12))
        .lineLimit(1)
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                quotaNumber(size: 34)
                Spacer(minLength: 0)
                Text("本周剩余").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            progress
            Divider().opacity(0.45)
            Text("本机今日").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 7) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(TokenFormat.compact(today?.totalTokens))
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    Text("今日 token").font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    compactMetric(value: cacheText, label: "缓存率")
                    compactMetric(value: speedText, label: "输出速度")
                }
            }
        }
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 15) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本周剩余").font(.system(size: 10)).foregroundStyle(.secondary)
                    quotaNumber(size: 43)
                    progress
                    if let reset = snapshot.weekly?.reset {
                        Text(reset, format: .dateTime.month().day().hour().minute())
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle().fill(.primary.opacity(0.10)).frame(width: 1, height: 84)

                VStack(alignment: .leading, spacing: 5) {
                    Text("本机今日").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(TokenFormat.compact(today?.totalTokens))
                            .font(.system(size: 23, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("token").font(.system(size: 9)).foregroundStyle(.secondary)
                    }.lineLimit(1).minimumScaleFactor(0.65)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(cacheText).font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("缓存率").font(.system(size: 9)).foregroundStyle(.secondary)
                    }.lineLimit(1).minimumScaleFactor(0.7)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(speedText).font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit()
                        Text("最近").font(.system(size: 9)).foregroundStyle(.secondary)
                    }.lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 3) {
            if let warning {
                Image(systemName: "exclamationmark.circle")
                Text(warning)
            } else if compact, let reset = snapshot.weekly?.reset {
                Text(reset, format: .dateTime.month().day())
                Text("重置")
            } else {
                Text("已同步")
            }
            if !compact, let updated = today?.updatedAt {
                Spacer(minLength: 2)
                Text("更新 \(updated.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.system(size: compact ? 9 : 10))
        .foregroundStyle(warning == nil ? Color.secondary : Color.orange)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private func quotaNumber(size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(remaining.map { String(format: "%.0f", $0) } ?? "—")
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if remaining != nil {
                Text("%").font(.system(size: compact ? 15 : 19)).foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .widgetAccentable()
        .accessibilityLabel(remaining.map { "本周剩余百分之\(Int($0))" } ?? "额度未知")
    }

    private var progress: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.10))
                Capsule().fill(tint).frame(width: geometry.size.width * (remaining ?? 0) / 100).widgetAccentable()
            }
        }
        .frame(height: compact ? 3 : 4)
        .accessibilityHidden(true)
    }

    private func compactMetric(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
