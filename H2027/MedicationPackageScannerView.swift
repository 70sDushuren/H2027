import SwiftUI
import VisionKit

struct MedicationPackageScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var recognizedText = ""
    @State private var scannerError: String?

    let onConfirm: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported {
                    ZStack(alignment: .bottom) {
                        MedicationTextScanner(
                            recognizedText: $recognizedText,
                            errorMessage: $scannerError
                        )
                        ScannerResultPanel(recognizedText: recognizedText)
                            .padding()
                    }
                } else {
                    ContentUnavailableView(
                        "此设备不支持实时文字扫描",
                        systemImage: "camera.viewfinder",
                        description: Text("你仍可返回并手动输入药品信息。")
                    )
                }
            }
            .navigationTitle("扫描药品包装")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("使用文字") {
                        onConfirm(recognizedText)
                        dismiss()
                    }
                    .disabled(recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("无法使用相机扫描", isPresented: scannerErrorBinding) {
                Button("好") { scannerError = nil }
            } message: {
                Text(scannerError ?? "")
            }
        }
    }

    private var scannerErrorBinding: Binding<Bool> {
        Binding(
            get: { scannerError != nil },
            set: { if !$0 { scannerError = nil } }
        )
    }
}

private struct ScannerResultPanel: View {
    let recognizedText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("已识别文字", systemImage: "text.viewfinder")
                .font(.headline)
            if recognizedText.isEmpty {
                Text("请将药品名称和规格放入取景框。")
                    .foregroundStyle(.secondary)
            } else {
                Text(recognizedText)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("识别结果仅用于辅助录入，保存前请对照药盒或药袋确认。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MedicationTextScanner: UIViewControllerRepresentable {
    @Binding var recognizedText: String
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(recognizedText: $recognizedText, errorMessage: $errorMessage)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: ["zh-Hans", "zh-Hant", "en-US"], textContentType: nil)],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !uiViewController.isScanning, DataScannerViewController.isAvailable else { return }
        do {
            try uiViewController.startScanning()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private var recognizedText: Binding<String>
        private var errorMessage: Binding<String?>

        init(recognizedText: Binding<String>, errorMessage: Binding<String?>) {
            self.recognizedText = recognizedText
            self.errorMessage = errorMessage
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            updateText(from: allItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            updateText(from: allItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didRemove removedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            updateText(from: allItems)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            errorMessage.wrappedValue = error.localizedDescription
        }

        private func updateText(from items: [RecognizedItem]) {
            let lines = items.compactMap { item -> String? in
                guard case let .text(text) = item else { return nil }
                return text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            recognizedText.wrappedValue = lines.joined(separator: "\n")
        }
    }
}
