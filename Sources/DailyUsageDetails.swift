import SwiftUI

struct DailyUsageDetails: View {
    let usage: DailyUsage?
    var refreshing = false
    var date = Date()
    private var today: DailyUsage? { usage.flatMap { $0.isToday(date) ? $0 : nil } }
    private func exact(_ value: Int64?) -> String { value?.formatted(.number) ?? "—" }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本机今日").font(.headline)
                Spacer()
                if refreshing { ProgressView().controlSize(.small) }
            }
            LabeledContent("总 token", value: exact(today?.totalTokens))
            HStack(spacing: 14) {
                detail("输入", today?.inputTokens)
                detail("输出", today?.outputTokens)
                detail("缓存输入", today?.cachedInputTokens)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 14) {
                detailText("今日平均", speedText(today?.averageOutputTokensPerSecond))
                detailText("最近速度", speedText(today?.latestOutputTokensPerSecond))
                detailText("有效样本", today?.speedSampleCount.map(String.init) ?? "—")
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let daily = today {
                if let error = daily.error { Text(error).foregroundStyle(.orange) }
                if daily.stale(at: date) { Text("数据较旧 · 点击立即同步").foregroundStyle(.secondary) }
                if let updated = daily.updatedAt {
                    Text("更新 \(updated.formatted(date: .omitted, time: .standard)) · \(daily.timeZone)")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(refreshing ? "正在读取本机用量…" : "今日统计待更新").foregroundStyle(.secondary)
            }
            Text("输入＋输出；缓存已包含在输入中。缓存率＝缓存输入÷输入。按 Mac 当前时区统计所选目录内的记录，不代表跨设备账号总量，也不按账号拆分。")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("速度按同一会话中相邻 token 事件计算，间隔超过 5 分钟不计入。")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.font(.caption).monospacedDigit().textSelection(.enabled)
    }
    private func detail(_ label: String, _ count: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).foregroundStyle(.secondary)
            Text(exact(count)).fontWeight(.medium).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func detailText(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).foregroundStyle(.secondary)
            Text(value).fontWeight(.medium).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func speedText(_ value: Double?) -> String {
        guard value != nil else { return "—" }
        return TokenFormat.speed(value) + " tok/s"
    }
}
