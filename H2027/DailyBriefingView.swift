import SwiftUI

enum DailyBriefingKind: String, Identifiable {
    case morning
    case bedtime

    var id: String { rawValue }
}

enum DailyBriefingPolicy {
    static func nextBriefing(
        now: Date,
        wakeHour: Int,
        bedtimeHour: Int,
        lastMorningDate: Date?,
        lastBedtimeDate: Date?,
        calendar: Calendar = .current
    ) -> DailyBriefingKind? {
        let hour = calendar.component(.hour, from: now)
        let isBedtimePeriod = wakeHour < bedtimeHour
            ? hour >= bedtimeHour
            : hour >= bedtimeHour && hour < wakeHour
        if isBedtimePeriod, !isSameDay(lastBedtimeDate, as: now, calendar: calendar) {
            return .bedtime
        }
        let isMorningPeriod = wakeHour < bedtimeHour
            ? hour >= wakeHour && hour < bedtimeHour
            : hour >= wakeHour || hour < bedtimeHour
        if isMorningPeriod, !isSameDay(lastMorningDate, as: now, calendar: calendar) {
            return .morning
        }
        return nil
    }

    private static func isSameDay(_ date: Date?, as otherDate: Date, calendar: Calendar) -> Bool {
        date.map { calendar.isDate($0, inSameDayAs: otherDate) } ?? false
    }
}

struct DailyBriefingView: View {
    @Environment(\.dismiss) private var dismiss

    let kind: DailyBriefingKind
    let plannedCount: Int
    let completedCount: Int
    let pendingCount: Int
    let missedCount: Int
    let previousMissedMedicationNames: [String]
    let weatherState: WeatherLoadState
    let temperatureCelsius: Double?
    let conditionText: String
    let conditionSymbol: String
    let clothingAdvice: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DailyBriefingHeader(kind: kind)
                    if kind == .morning {
                        MorningDailyBriefingContent(
                            plannedCount: plannedCount,
                            completedCount: completedCount,
                            previousMissedMedicationNames: previousMissedMedicationNames,
                            weatherState: weatherState,
                            temperatureCelsius: temperatureCelsius,
                            conditionText: conditionText,
                            conditionSymbol: conditionSymbol,
                            clothingAdvice: clothingAdvice
                        )
                    } else {
                        BedtimeDailyBriefingContent(
                            plannedCount: plannedCount,
                            completedCount: completedCount,
                            pendingCount: pendingCount,
                            missedCount: missedCount
                        )
                    }
                }
                .padding()
            }
            .navigationTitle(kind == .morning ? "晨间简报" : "睡前检查")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct DailyBriefingHeader: View {
    let kind: DailyBriefingKind

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: kind == .morning ? "sun.horizon.fill" : "moon.stars.fill")
                .font(.largeTitle)
                .foregroundStyle(kind == .morning ? .orange : .indigo)
                .accessibilityHidden(true)
            Text(kind == .morning ? "早上好" : "准备休息了吗？")
                .font(.largeTitle.bold())
            Text(kind == .morning ? "这是今天的天气与用药概览。" : "一起检查今天的用药计划。")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MorningDailyBriefingContent: View {
    let plannedCount: Int
    let completedCount: Int
    let previousMissedMedicationNames: [String]
    let weatherState: WeatherLoadState
    let temperatureCelsius: Double?
    let conditionText: String
    let conditionSymbol: String
    let clothingAdvice: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BriefingSectionCard(title: "今日用药", systemImage: "pills.fill") {
                Text("今天计划服用 \(plannedCount) 次，已完成 \(completedCount) 次。")
            }
            BriefingSectionCard(title: "天气与穿衣", systemImage: "cloud.sun.fill") {
                WeatherBriefingContent(
                    state: weatherState,
                    temperatureCelsius: temperatureCelsius,
                    conditionText: conditionText,
                    conditionSymbol: conditionSymbol,
                    clothingAdvice: clothingAdvice
                )
            }
            BriefingSectionCard(title: "昨日漏服", systemImage: "exclamationmark.triangle.fill") {
                if previousMissedMedicationNames.isEmpty {
                    Text("没有发现昨日漏服记录。")
                } else {
                    Text("昨日可能漏服：\(previousMissedMedicationNames.formatted()). 请勿自行补服，请遵循医生或药师建议。")
                }
            }
        }
    }
}

private struct BedtimeDailyBriefingContent: View {
    let plannedCount: Int
    let completedCount: Int
    let pendingCount: Int
    let missedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BriefingSectionCard(title: "今日完成情况", systemImage: "checklist") {
                Text("共计划 \(plannedCount) 次，已完成 \(completedCount) 次。")
                if pendingCount == 0 && missedCount == 0 {
                    Label("今天的用药计划已全部完成。", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("还有 \(pendingCount) 项待处理，\(missedCount) 项可能已漏服。")
                        .foregroundStyle(.orange)
                    Text("请勿自行补服或调整剂量；如有疑问，请联系医生或药师。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct BriefingSectionCard<Content: View>: View {
    let title: LocalizedStringResource
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}
