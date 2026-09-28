import SwiftUI
import WidgetKit

struct QuotaView: View {
    let snapshot: Snapshot
    var date: Date = Date()
    var compact = false
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var remaining: Double? { snapshot.remaining(at: date) }
    private var tint: Color { renderingMode == .accented ? .primary : (remaining ?? 100) <= 20 ? .orange : .mint }
    private var status: String {
        if snapshot.expired(at: date) { return "周期已结束 · 等待同步" }
        if snapshot.error != nil { return snapshot.weekly == nil ? "尚未获取额度" : "同步失败 · 上次数据" }
        if snapshot.stale(at: date) { return "数据较旧 · 打开应用同步" }
        return "本周可用额度"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 9 : 14) {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill").widgetAccentable()
                Text("Codex").fontWeight(.semibold)
                Spacer()
                Text("每周").font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline)
            HStack(alignment: .center, spacing: 22) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(remaining.map { String(format: "%.0f", $0) } ?? "—")
                            .font(.system(size: compact ? 42 : 54, weight: .semibold, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.7)
                        if remaining != nil { Text("%").font(.title3).foregroundStyle(.secondary) }
                    }.widgetAccentable().accessibilityLabel(remaining.map { "本周剩余百分之\(Int($0))" } ?? "额度未知")
                    Text(status).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                if !compact {
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().stroke(.primary.opacity(0.10), lineWidth: 7)
                        Circle().trim(from: 0, to: (remaining ?? 0) / 100)
                            .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90)).widgetAccentable()
                        Image(systemName: remaining == nil ? "arrow.trianglehead.clockwise" : "bolt.fill").font(.title2).foregroundStyle(tint)
                    }.frame(width: 64, height: 64).accessibilityHidden(true)
                }
            }
            if compact {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.10))
                        Capsule().fill(tint).frame(width: geometry.size.width * (remaining ?? 0) / 100).widgetAccentable()
                    }
                }.frame(height: 5).accessibilityHidden(true)
            }
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise").font(.system(size: 9))
                if let reset = snapshot.weekly?.reset {
                    Text(reset, format: .dateTime.month().day().hour().minute())
                    Text("重置")
                } else { Text("打开应用以同步") }
                if !compact, let fetched = snapshot.fetchedAt {
                    Spacer(minLength: 4)
                    Text("更新 \(fetched.formatted(date: .omitted, time: .shortened))")
                }
            }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)

        }.privacySensitive()
    }
}
