import AppIntents

struct RecordMedicationIntent: AppIntent {
    static let title: LocalizedStringResource = "记录服药"
    static let description = IntentDescription("打开 H2027 的快速服药记录界面，由你确认药品和剂量。")
    static var supportedModes: IntentModes { .foreground }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set(true, forKey: "quickRecordRequested")
        return .result(dialog: "已打开快速记录，请选择药品并确认。")
    }
}

struct H2027Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordMedicationIntent(),
            phrases: [
                "在 \(.applicationName) 记录服药",
                "用 \(.applicationName) 记录服药",
            ],
            shortTitle: "记录服药",
            systemImageName: "pills.fill"
        )
    }
}
