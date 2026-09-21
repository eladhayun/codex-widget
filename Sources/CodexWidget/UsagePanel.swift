import AppKit
import SwiftUI
#if canImport(UsageCore)
import UsageCore
#endif

enum PanelTab: String, CaseIterable { case status = "Status", usage = "Usage", stats = "Stats" }

private struct TerminalStyle {
    let dark: Bool
    let increasedContrast: Bool
    var background: Color { dark ? Color(red: 0.09, green: 0.09, blue: 0.12) : Color(red: 0.97, green: 0.97, blue: 0.99) }
    var text: Color { dark ? Color(white: 0.94) : Color(white: 0.12) }
    var muted: Color { increasedContrast ? text : dark ? Color(white: 0.70) : Color(white: 0.36) }
    var lavender: Color { dark ? Color(red: 0.73, green: 0.73, blue: 0.96) : Color(red: 0.39, green: 0.30, blue: 0.68) }
    var track: Color { dark ? Color(red: 0.29, green: 0.29, blue: 0.38) : Color(red: 0.83, green: 0.81, blue: 0.90) }
    var orange: Color { dark ? Color(red: 0.95, green: 0.65, blue: 0.48) : Color(red: 0.65, green: 0.28, blue: 0.12) }
    var success: Color { dark ? Color(red: 0.40, green: 0.85, blue: 0.48) : Color(red: 0.13, green: 0.44, blue: 0.23) }
    var selectedText: Color { dark ? Color(white: 0.09) : .white }
}

struct UsagePanel: View {
    @ObservedObject var store: UsageStore
    @State private var tab: PanelTab
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var style: TerminalStyle {
        TerminalStyle(dark: (store.appearance.colorScheme ?? systemScheme) == .dark,
                      increasedContrast: contrast == .increased)
    }

    init(store: UsageStore, initialTab: PanelTab = .usage) {
        self.store = store
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(style.lavender).frame(height: 2)
            HStack(spacing: 14) {
                Text("Codex").fontWeight(.bold).foregroundStyle(style.lavender)
                ForEach(PanelTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        Text(item.rawValue).fontWeight(tab == item ? .bold : .regular)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .foregroundStyle(tab == item ? style.selectedText : style.text)
                            .background(tab == item ? style.lavender : .clear)
                    }
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }.font(.system(size: 13, design: .monospaced)).padding(.bottom, 23).padding(.top, 18)

            if let error = store.error {
                Text(error).foregroundStyle(style.orange).padding(.bottom, 16)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Keep every tab in layout so the tallest one determines panel height.
            // Inactive tabs must not receive clicks, keyboard focus, or VoiceOver.
            ZStack(alignment: .topLeading) {
                ForEach(PanelTab.allCases, id: \.self) { item in
                    Group {
                        switch item {
                        case .status: statusContent
                        case .usage: usageContent
                        case .stats: statsContent
                        }
                    }
                    .opacity(tab == item ? 1 : 0)
                    .allowsHitTesting(tab == item)
                    .disabled(tab != item)
                    .accessibilityHidden(tab != item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)

            HStack(spacing: 14) {
                Button { Task { await store.refresh() } } label: {
                    Text(store.refreshing ? "Refreshing…" : "↻ Refresh")
                }.disabled(store.refreshing)
                SettingsLink { Text("Settings") }
                Spacer()
                if store.stale { Text("Stale").foregroundStyle(style.orange) }
                Button("Quit") { NSApp.terminate(nil) }
            }.font(.system(size: 11, design: .monospaced)).foregroundStyle(style.muted)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 18)
        .frame(width: 440)
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(style.text)
        .background {
            let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
            if reduceTransparency || contrast == .increased {
                shape.fill(style.background)
            } else {
                shape.fill(.regularMaterial)
                    .overlay { shape.fill(style.background.opacity(0.88)) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style.text.opacity(contrast == .increased ? 0.4 : 0.10), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .buttonStyle(.plain)
        .preferredColorScheme(store.appearance.colorScheme)
        .task { await store.refreshIfNeeded() }
    }

    private var appVersion: String {
        // Test runners have their own version; only read metadata from our app.
        guard Bundle.main.bundleIdentifier == "com.eladhayun.codex-widget" else { return "Development" }
        return Bundle.main.object(forInfoDictionaryKey: "CodexReleaseTag") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }

    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            field("Version:", appVersion)
            field("Connection:", store.refreshing ? "Refreshing…" : store.stale ? "Waiting for update" : "Connected", color: store.stale ? style.orange : style.success)
            field("Login method:", store.account?.type == "chatgpt" ? "ChatGPT account" : store.account?.type ?? "Not signed in")
            field("Plan:", store.account?.planType?.capitalized ?? "Unavailable")
            field("Email:", store.account?.email ?? "Unavailable")
            field("Updated:", store.updatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not yet")
            field("Refresh:", "Every \(store.refreshInterval.label)")
            Text("Account-wide Codex usage").foregroundStyle(style.lavender).padding(.top, 16)
            Text("Session details belong to individual Codex conversations.")
                .foregroundStyle(style.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var usageContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                heading("Account usage")
                field(store.usesLocalFallback ? "Last 24h:" : "Today's tokens:", store.usesLocalFallback ? UsageFormatting.tokens(store.localUsage?.tokens) : store.usage?.todayDisplay() ?? "Unavailable", color: style.muted)
                field("Total tokens:", UsageFormatting.tokens(store.usage?.summary.lifetimeTokens), color: style.muted)
                Text(store.usesLocalFallback ? "This Mac · all local Codex sessions" : "Daily totals use UTC")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(style.muted)
                if store.usesLocalFallback, store.localUsage?.partial == true {
                    Text("Partial total · some local records were unreadable")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(style.orange)
                }
                if let usage = store.usage, usage.todayTokens() == nil, let latest = usage.latestReportedDate {
                    Text("Latest daily report: \(latest)")
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(style.muted)
                }
            }
            if let rows = store.limits?.rows, !rows.isEmpty {
                if rows.count > 3 {
                    ScrollView { quotas(rows) }.frame(height: 252)
                } else { quotas(rows) }
            } else {
                Text(store.refreshing ? "Loading quota windows…" : "Quota information unavailable")
                    .foregroundStyle(style.muted)
            }
            if let message = store.tokenMessage { Text(message).foregroundStyle(style.muted) }
        }
    }

    private func quotas(_ rows: [QuotaRow]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 5) {
                    heading(quotaTitle(row))
                    HStack(spacing: 9) {
                        GeometryReader { geometry in
                            Rectangle().fill(style.track)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(style.lavender)
                                        .frame(width: geometry.size.width * (100 - row.window.remaining) / 100)
                                }
                        }.frame(height: 14)
                            .accessibilityLabel("\(quotaTitle(row)) usage")
                            .accessibilityValue("\(Int(100 - row.window.remaining)) percent used")
                        Text("\(Int(100 - row.window.remaining))% used")
                            .fontWeight(.semibold).frame(width: 72, alignment: .trailing)
                    }
                    Text(resetTime(row.window)).foregroundStyle(style.muted)
                        .font(.system(size: 10, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                    if row.window.windowDurationMins == 10080 {
                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            if let fraction = row.window.timeRemainingFraction(now: timeline.date) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Time until reset").foregroundStyle(style.muted)
                                    HStack(spacing: 9) {
                                        GeometryReader { geometry in
                                            Rectangle().fill(style.track)
                                                .overlay(alignment: .leading) {
                                                    Rectangle().fill(style.lavender.opacity(0.65))
                                                        .frame(width: geometry.size.width * fraction)
                                                }
                                        }.frame(height: 14)
                                            .accessibilityLabel("Weekly window time remaining")
                                            .accessibilityValue("\(Int(fraction * 100)) percent")
                                        Text("\(Int(fraction * 100))% left")
                                            .frame(width: 72, alignment: .trailing)
                                    }
                                    Text(row.window.resetLabel(now: timeline.date)).foregroundStyle(style.muted)
                                }
                                .font(.system(size: 10, design: .monospaced))
                                .padding(.top, 9)
                                .help("Remaining time as a fraction of the seven-day quota window.")
                            }
                        }
                    }
                }
            }
        }
    }

    private var statsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("Overview").padding(.horizontal, 6).padding(.vertical, 3)
                .foregroundStyle(style.selectedText).background(style.lavender)
            if let buckets = store.usage?.dailyUsageBuckets, !buckets.isEmpty {
                ActivityGrid(buckets: buckets, style: style)
            } else {
                Text("Daily activity unavailable").foregroundStyle(style.muted)
            }
            Text("All time").fontWeight(.bold).foregroundStyle(style.lavender)
            VStack(alignment: .leading, spacing: 9) {
                field("Total tokens:", UsageFormatting.tokens(store.usage?.summary.lifetimeTokens), color: style.lavender)
                field("Peak daily:", UsageFormatting.tokens(store.usage?.summary.peakDailyTokens), color: style.lavender)
                field("Longest turn:", turnDuration, color: style.lavender)
                field("Longest streak:", days(store.usage?.summary.longestStreakDays), color: style.lavender)
                field("Current streak:", days(store.usage?.summary.currentStreakDays), color: style.lavender)
            }
            Text("Metrics reported by Codex").foregroundStyle(style.lavender)
        }
    }

    private var turnDuration: String {
        guard let seconds = store.usage?.summary.longestRunningTurnSec else { return "Unavailable" }
        return seconds >= 3600 ? "\(seconds / 3600)h \((seconds % 3600) / 60)m" : "\(seconds / 60)m \(seconds % 60)s"
    }

    private func days(_ count: Int64?) -> String { count.map { "\($0) days" } ?? "Unavailable" }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .bold, design: .monospaced))
    }

    private func field(_ label: String, _ value: String, color: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).frame(width: 130, alignment: .leading)
            Text(value).foregroundStyle(color ?? style.text).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func quotaTitle(_ row: QuotaRow) -> String {
        let base = row.window.windowDurationMins == 10080 ? "Current week" : row.window.durationLabel
        return row.name.lowercased() == "codex" ? base : "\(base) (\(row.name))"
    }

    private func resetTime(_ window: QuotaWindow) -> String {
        guard let timestamp = window.resetsAt else { return "Reset time unavailable" }
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "h:mma" : "MMM d 'at' h:mma"
        return "Resets \(formatter.string(from: date)) (\(TimeZone.current.identifier))"
    }
}

private struct ActivityGrid: View {
    let buckets: [TokenUsageResponse.DailyBucket]
    let style: TerminalStyle
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    var body: some View {
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let start = calendar.date(byAdding: .day, value: -(25 * 7 + weekday - 1), to: today)!
        let formatter = DateFormatter()
        let _ = { formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd" }()
        let values = Dictionary(buckets.map { ($0.startDate, $0.tokens) }, uniquingKeysWith: { _, latest in latest })
        let peak = max(values.values.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 26 weeks · daily tokens (UTC)").foregroundStyle(style.muted)
                .font(.system(size: 10, design: .monospaced))
            HStack(alignment: .top, spacing: 6) {
                VStack(spacing: 3) {
                    ForEach(0..<7) { day in
                        Text(["", "Mon", "", "Wed", "", "Fri", ""][day])
                            .font(.system(size: 8, design: .monospaced)).frame(width: 21, height: 9)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(0..<26) { week in
                        VStack(spacing: 3) {
                            ForEach(0..<7) { day in
                                let date = calendar.date(byAdding: .day, value: week * 7 + day, to: start)!
                                let key = formatter.string(from: date)
                                let count = values[key]
                                ZStack {
                                    if date <= today {
                                        if let count, count > 0 {
                                            Rectangle().fill(style.lavender.opacity(0.3 + 0.7 * Double(count) / Double(peak)))
                                        } else {
                                            Circle().fill(style.track).frame(width: 3, height: 3)
                                        }
                                    }
                                }.frame(width: 9, height: 9)
                                    .help("\(key): \(count.map { $0.formatted() + " tokens" } ?? "No data reported")")
                                    .accessibilityLabel("\(key): \(count.map { $0.formatted() + " tokens" } ?? "No data reported")")
                            }
                        }
                    }
                }
            }
            HStack(spacing: 5) {
                Text("Less")
                ForEach(1..<5) { level in Rectangle().fill(style.lavender.opacity(Double(level) / 4)).frame(width: 9, height: 9) }
                Text("More")
                Spacer()
                Text("· No data / zero")
            }.font(.system(size: 9, design: .monospaced)).foregroundStyle(style.muted)
        }
    }
}
