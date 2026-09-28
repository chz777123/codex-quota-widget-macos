import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot
}
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: Date(), snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(QuotaEntry(date: Date(), snapshot: context.isPreview ? .preview : SnapshotStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        Task {
        var snapshot = SnapshotStore.read()
        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:52743/quota")!)
            request.timeoutInterval = 4
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 16384 else { throw URLError(.badServerResponse) }
            snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
            try? SnapshotStore.write(snapshot)
        } catch { snapshot.error = "打开配套应用以同步" }
        let now = Date()
        var dates = [now, now.addingTimeInterval(1801)]
        if let reset = snapshot.weekly?.reset, reset > now { dates.append(reset) }
        let entries = dates.sorted().map { QuotaEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
        }
    }
}
struct WidgetContent: View {
    let entry: QuotaEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        QuotaView(snapshot: entry.snapshot, date: entry.date, compact: family == .systemSmall)
            .containerBackground(.background, for: .widget)
            .widgetURL(URL(string: "codexquota://refresh"))
    }
}
@main
struct QuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CodexWeeklyQuota", provider: Provider()) { entry in WidgetContent(entry: entry) }
            .configurationDisplayName("Codex 周额度")
            .description("查看每周剩余额度与重置时间。打开配套应用以保持同步。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
