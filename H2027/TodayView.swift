import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query private var schedules: [MedicationSchedule]
    @Query(sort: \DoseEvent.recordedAt, order: .reverse) private var events: [DoseEvent]
    @AppStorage("appLanguage") private var appLanguageCode = AppLanguage.simplifiedChinese.rawValue
    @AppStorage("wakeHour") private var wakeHour = 7
    @AppStorage("bedHour") private var bedHour = 22
    @AppStorage("lastMorningBriefingTimestamp") private var lastMorningBriefingTimestamp = 0.0
    @AppStorage("lastBedtimeBriefingTimestamp") private var lastBedtimeBriefingTimestamp = 0.0
    @State private var weatherService = WeatherAdvisoryService.shared
    @State private var automaticBriefing: DailyBriefingKind?

    private var todayDoses: [ScheduledDose] {
        ScheduleEngine.doses(on: .now, medications: medications, schedules: schedules, events: events)
    }

    private var yesterdayMissedMedicationNames: [String] {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) else { return [] }
        let doses = ScheduleEngine.doses(on: yesterday, medications: medications, schedules: schedules, events: events)
        return Array(Set(doses.filter { ScheduleEngine.effectiveStatus(for: $0) == .missed }.map(\.medicationName))).sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    MorningBriefingCard(
                        plannedCount: todayDoses.count,
                        completedCount: todayDoses.filter { $0.recordedStatus == .taken }.count,
                        weatherState: weatherService.state,
                        temperatureCelsius: weatherService.temperatureCelsius,
                        conditionText: weatherService.conditionText,
                        conditionSymbol: weatherService.conditionSymbol,
                        clothingAdvice: weatherService.clothingAdvice
                    )
                    if todayDoses.isEmpty {
                        ContentUnavailableView(
                            "今天没有用药计划",
                            systemImage: "checkmark.circle",
                            description: Text("可以在“药品”中添加药品和提醒时间。")
                        )
                        .frame(minHeight: 260)
                    } else {
                        ForEach(todayDoses) { dose in
                            DoseCard(
                                dose: dose,
                                effectiveStatus: ScheduleEngine.effectiveStatus(for: dose),
                                onRecord: { record(dose, status: $0) }
                            )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("今日")
            .task {
                syncToWatch()
                await weatherService.refresh()
                await NotificationManager.shared.scheduleDailyBriefings(
                    wakeHour: wakeHour,
                    bedtimeHour: bedHour
                )
                presentAutomaticBriefingIfNeeded()
            }
            .onChange(of: todayDoses) { _, _ in syncToWatch() }
            .onChange(of: appLanguageCode) { _, _ in syncToWatch() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { presentAutomaticBriefingIfNeeded() }
            }
            .sheet(item: $automaticBriefing) { kind in
                DailyBriefingView(
                    kind: kind,
                    plannedCount: todayDoses.count,
                    completedCount: todayDoses.filter { $0.recordedStatus == .taken }.count,
                    pendingCount: todayDoses.filter { ScheduleEngine.effectiveStatus(for: $0) == nil }.count,
                    missedCount: todayDoses.filter { ScheduleEngine.effectiveStatus(for: $0) == .missed }.count,
                    previousMissedMedicationNames: yesterdayMissedMedicationNames,
                    weatherState: weatherService.state,
                    temperatureCelsius: weatherService.temperatureCelsius,
                    conditionText: weatherService.conditionText,
                    conditionSymbol: weatherService.conditionSymbol,
                    clothingAdvice: weatherService.clothingAdvice
                )
            }
        }
    }

    private func syncToWatch() {
        WatchSyncManager.shared.send(doses: todayDoses, languageCode: appLanguageCode)
    }

    private func record(_ dose: ScheduledDose, status: DoseStatus) {
        modelContext.insert(
            DoseEvent(
                medicationID: dose.medicationID,
                scheduleID: dose.scheduleID,
                scheduledAt: dose.scheduledAt,
                dosage: dose.dosage,
                unit: dose.unit,
                status: status
            )
        )
        try? modelContext.save()
        Task {
            await NotificationManager.shared.scheduleDailyBriefings(
                wakeHour: wakeHour,
                bedtimeHour: bedHour
            )
        }
    }

    private func presentAutomaticBriefingIfNeeded(now: Date = .now) {
        let lastMorningDate = lastMorningBriefingTimestamp > 0 ? Date(timeIntervalSince1970: lastMorningBriefingTimestamp) : nil
        let lastBedtimeDate = lastBedtimeBriefingTimestamp > 0 ? Date(timeIntervalSince1970: lastBedtimeBriefingTimestamp) : nil
        guard let kind = DailyBriefingPolicy.nextBriefing(
            now: now,
            wakeHour: wakeHour,
            bedtimeHour: bedHour,
            lastMorningDate: lastMorningDate,
            lastBedtimeDate: lastBedtimeDate
        ) else { return }
        switch kind {
        case .morning: lastMorningBriefingTimestamp = now.timeIntervalSince1970
        case .bedtime: lastBedtimeBriefingTimestamp = now.timeIntervalSince1970
        }
        automaticBriefing = kind
    }
}

struct MorningBriefingCard: View {
    let plannedCount: Int
    let completedCount: Int
    let weatherState: WeatherLoadState
    let temperatureCelsius: Double?
    let conditionText: String
    let conditionSymbol: String
    let clothingAdvice: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("早上好", systemImage: "sun.horizon.fill")
                .font(.title2.bold())
            Text("今天计划服用 \(plannedCount) 次，已完成 \(completedCount) 次。")
            WeatherBriefingContent(
                state: weatherState,
                temperatureCelsius: temperatureCelsius,
                conditionText: conditionText,
                conditionSymbol: conditionSymbol,
                clothingAdvice: clothingAdvice
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.blue.gradient.opacity(0.16), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

struct WeatherBriefingContent: View {
    let state: WeatherLoadState
    let temperatureCelsius: Double?
    let conditionText: String
    let conditionSymbol: String
    let clothingAdvice: String

    var body: some View {
        switch state {
        case .idle, .requestingLocation:
            Label("正在获取天气和穿衣建议…", systemImage: "location")
                .foregroundStyle(.secondary)
        case .loaded:
            VStack(alignment: .leading, spacing: 6) {
                if let temperatureCelsius {
                    Label {
                        Text("\(conditionText) · \(temperatureCelsius, format: .number.precision(.fractionLength(0)))°C")
                    } icon: {
                        Image(systemName: conditionSymbol)
                    }
                }
                Label(clothingAdvice, systemImage: "tshirt.fill")
                    .foregroundStyle(.secondary)
            }
        case .unavailable:
            Label("无法获取天气；可在设置中检查位置权限。", systemImage: "location.slash")
                .foregroundStyle(.secondary)
        }
    }
}

struct DoseCard: View {
    let dose: ScheduledDose
    let effectiveStatus: DoseStatus?
    let onRecord: (DoseStatus) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dose.medicationName).font(.headline)
                    Text("\(dose.dosage, format: .number) \(dose.unit)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(dose.scheduledAt, format: .dateTime.hour().minute())
                    .font(.headline.monospacedDigit())
            }
            if !dose.mealNote.isEmpty {
                Label(dose.mealNote, systemImage: "fork.knife")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let effectiveStatus {
                Label(effectiveStatus.title, systemImage: effectiveStatus.systemImage)
                    .font(.subheadline.weight(.semibold))
            } else {
                HStack {
                    Button("已服用", systemImage: "checkmark") { onRecord(.taken) }
                        .buttonStyle(.borderedProminent)
                    Button("延后", systemImage: "clock") { onRecord(.snoozed) }
                        .buttonStyle(.bordered)
                    Menu("更多", systemImage: "ellipsis") {
                        Button("跳过本次", systemImage: "forward.end") { onRecord(.skipped) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.quaternary) }
    }
}
