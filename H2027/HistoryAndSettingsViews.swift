import SwiftData
import SwiftUI

struct DoseHistoryView: View {
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query(sort: \DoseEvent.recordedAt, order: .reverse) private var events: [DoseEvent]

    private var medicationByID: [UUID: Medication] {
        Dictionary(uniqueKeysWithValues: medications.map { ($0.id, $0) })
    }

    var body: some View {
        NavigationStack {
            List(events) { event in
                DoseHistoryRow(
                    medicationName: medicationByID[event.medicationID]?.name ?? "已删除的药品",
                    dosage: event.dosage,
                    unit: event.unit,
                    status: event.status,
                    source: event.source,
                    recordedAt: event.recordedAt
                )
            }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView("暂无记录", systemImage: "list.bullet.clipboard")
                }
            }
            .navigationTitle("记录")
        }
    }
}

struct DoseHistoryRow: View {
    let medicationName: String
    let dosage: Double
    let unit: String
    let status: DoseStatus
    let source: DoseSource
    let recordedAt: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.systemImage)
                .foregroundStyle(status == .missed ? .orange : .blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(medicationName).font(.headline)
                Text("\(dosage, format: .number) \(unit) · \(status.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(recordedAt, format: .dateTime.month().day().hour().minute())
                Text(source.rawValue).foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SettingsView: View {
    @AppStorage("wakeHour") private var wakeHour = 7
    @AppStorage("bedHour") private var bedHour = 22
    @AppStorage("defaultGracePeriod") private var defaultGracePeriod = 120
    @AppStorage("appLanguage") private var appLanguageCode = AppLanguage.simplifiedChinese.rawValue
    @State private var notificationManager = NotificationManager.shared
    @State private var healthKitService = HealthKitService.shared
    @State private var weatherService = WeatherAdvisoryService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("语言") {
                    Picker("应用语言", selection: $appLanguageCode) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeTitle).tag(language.rawValue)
                        }
                    }
                }
                Section("作息") {
                    Stepper("起床时间：\(wakeHour):00", value: $wakeHour, in: 0...23)
                    Stepper("睡前提醒：\(bedHour):00", value: $bedHour, in: 0...23)
                    Stepper("默认宽限：\(defaultGracePeriod) 分钟", value: $defaultGracePeriod, in: 15...720, step: 15)
                }
                Section("系统能力") {
                    SettingsStatusRow(
                        title: "通知",
                        detail: notificationManager.permissionState.title,
                        systemImage: "bell.badge"
                    )
                    if notificationManager.permissionState != .authorized {
                        Button(notificationManager.permissionState == .denied ? "重新检查通知权限" : "启用通知") {
                            Task {
                                let granted = await notificationManager.requestAuthorization()
                                if granted {
                                    await notificationManager.scheduleDailyBriefings(
                                        wakeHour: wakeHour,
                                        bedtimeHour: bedHour
                                    )
                                }
                            }
                        }
                    }
                    SettingsStatusRow(
                        title: "Apple 健康",
                        detail: healthKitService.state.title,
                        systemImage: "heart.fill"
                    )
                    if healthKitService.canRequestAccess {
                        Button("连接 Apple 健康") {
                            Task { await healthKitService.requestReadAccess() }
                        }
                    }
                    SettingsStatusRow(
                        title: "天气位置",
                        detail: weatherStatusTitle,
                        systemImage: "location.fill"
                    )
                    Button("刷新天气与位置") {
                        Task { await weatherService.refresh() }
                    }
                    SettingsStatusRow(title: "Apple Watch", detail: "可选，不影响 iPhone 功能", systemImage: "applewatch")
                }
                Section("重要说明") {
                    Text("本应用只提供记录和提醒，不判断是否可以补服、停服或调整剂量。请遵循医生或药师建议。")
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = notificationManager.lastErrorMessage {
                    Section("通知错误") {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("设置")
            .task {
                await notificationManager.refreshPermissionState()
            }
            .onChange(of: wakeHour) { _, newValue in
                Task {
                    await notificationManager.scheduleDailyBriefings(
                        wakeHour: newValue,
                        bedtimeHour: bedHour
                    )
                }
            }
            .onChange(of: bedHour) { _, newValue in
                Task {
                    await notificationManager.scheduleDailyBriefings(
                        wakeHour: wakeHour,
                        bedtimeHour: newValue
                    )
                }
            }
        }
    }

    private var weatherStatusTitle: String {
        switch weatherService.state {
        case .idle: "尚未连接"
        case .requestingLocation: "正在获取"
        case .loaded: "已连接"
        case .unavailable: "不可用"
        }
    }
}

struct SettingsStatusRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        LabeledContent {
            Text(detail).foregroundStyle(.secondary)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
