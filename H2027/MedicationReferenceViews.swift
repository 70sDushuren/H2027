import SwiftUI

struct MedicationReferencePicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedRegion = ReferenceRegion.mainlandChina
    @State private var searchText = ""
    let onSelect: (MedicationReference) -> Void

    private var entries: [MedicationReference] {
        MedicationReferenceCatalog.entries.filter { entry in
            entry.regions.contains(selectedRegion) &&
            (searchText.isEmpty || entry.genericName.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("地区", selection: $selectedRegion) {
                        ForEach(ReferenceRegion.allCases) { region in
                            Text(region.title).tag(region)
                        }
                    }
                } footer: {
                    Text("地区表示官方目录或说明书资料的参考范围，不代表药品一定有售。")
                }
                ForEach(ChronicCondition.allCases) { condition in
                    let matching = entries.filter { $0.condition == condition }
                    if !matching.isEmpty {
                        Section {
                            ForEach(matching) { entry in
                                NavigationLink {
                                    MedicationReferenceDetail(entry: entry) {
                                        onSelect(entry)
                                        dismiss()
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.genericName).font(.headline)
                                        Text(entry.commonStrengths.formatted(.list(type: .and)))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        } header: {
                            Text(condition.title)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索通用名")
            .navigationTitle("常用药参考")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

struct MedicationReferenceDetail: View {
    let entry: MedicationReference
    let onUse: () -> Void

    var body: some View {
        List {
            Section("常见规格") {
                Text(entry.commonStrengths.formatted(.list(type: .and)))
            }
            Section("说明书参考") {
                Text(entry.exampleUse)
                Text(entry.mealGuidance)
            }
            Section("资料来源") {
                Link(entry.sourceTitle, destination: entry.sourceURL)
                LabeledContent("复核日期") {
                    Text(entry.reviewedOn, format: .dateTime.year().month().day())
                }
            }
            Section {
                Text("这不是处方或治疗建议。请按照药袋、处方或医生/药师指示确认药名、剂型、剂量和频次。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(entry.genericName)
        .safeAreaInset(edge: .bottom) {
            Button("使用此参考并自行确认", action: onUse)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }
}
