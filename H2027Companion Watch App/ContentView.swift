//
//  ContentView.swift
//  H2027Watch Watch App
//
//  Created by Shawn Huang on 11/16/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                HStack {
                    Label("\(store.completedCount)/\(store.doses.count)", systemImage: "pills.fill").font(.headline)
                    Spacer()
                    Image(systemName: store.isPhoneReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                        .foregroundStyle(store.isPhoneReachable ? .green : .secondary)
                        .accessibilityLabel(store.isPhoneReachable ? store.copy.connected : store.copy.offline)
                }
                if store.doses.isEmpty {
                    ContentUnavailableView(store.copy.noPlan, systemImage: "checkmark.circle", description: Text(store.copy.openPhone))
                } else {
                    ForEach(store.doses) { dose in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(dose.name).font(.headline)
                                Spacer()
                                Text(dose.scheduledAt, format: .dateTime.hour().minute()).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Text("\(dose.dosage, format: .number) \(dose.unit)").font(.caption).foregroundStyle(.secondary)
                            if let status = dose.status {
                                Label(store.copy.status(status), systemImage: status == "taken" ? "checkmark.circle.fill" : "clock.fill")
                                    .font(.caption.weight(.semibold)).foregroundStyle(status == "taken" ? .green : .orange)
                            } else {
                                HStack {
                                    Button { store.record(dose, status: "taken") } label: { Image(systemName: "checkmark") }
                                        .tint(.green).accessibilityLabel(store.copy.taken)
                                    Button { store.record(dose, status: "snoozed") } label: { Image(systemName: "clock") }
                                        .tint(.orange).accessibilityLabel(store.copy.snooze)
                                }
                            }
                        }.accessibilityElement(children: .contain)
                    }
                }
            }
            .navigationTitle(store.copy.today)
            .refreshable { store.requestRefresh() }
        }
    }
}

#Preview { ContentView().environment(WatchStore.preview) }
