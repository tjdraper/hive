#if os(macOS) && (DEBUG || TEST_BUILD)
import HiveKit
import SwiftUI

/// Sends any request to a Hive as this device and shows what comes back, for checking routes before
/// Beekeeper has screens for them.
struct DeveloperWindow: View {
    static let id = "developer"

    private static let methods = ["GET", "POST", "PUT", "DELETE"]

    @Environment(HiveListStore.self) private var store
    @State private var hiveID: UUID?
    @State private var method = "GET"
    @State private var path = HiveEndpoint.settings
    @State private var requestBody = ""
    @State private var response: (status: Int, body: String)?
    @State private var failure: String?
    @State private var isSending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Hive", selection: $hiveID) {
                    ForEach(store.hives) { hive in
                        Text(hive.name).tag(Optional(hive.id))
                    }
                }
                .frame(maxWidth: 260)
                Picker("Method", selection: $method) {
                    ForEach(Self.methods, id: \.self) { Text($0) }
                }
                .labelsHidden()
                .frame(width: 100)
                TextField("Path", text: $path)
                    .font(.body.monospaced())
                    .onSubmit { Task { await send() } }
                Button("Send") { Task { await send() } }
                    .keyboardShortcut(.return)
                    .disabled(hiveID == nil || isSending)
            }

            Text("Body")
                .font(.headline)
            TextEditor(text: $requestBody)
                .font(.body.monospaced())
                .frame(minHeight: 100, maxHeight: 180)

            HStack {
                Text("Response")
                    .font(.headline)
                if let response {
                    Text("\(response.status)")
                        .font(.body.monospaced())
                        .foregroundStyle((200 ..< 300).contains(response.status) ? .green : .orange)
                }
                if isSending { ProgressView().controlSize(.small) }
            }
            ScrollView {
                Text(failure ?? response?.body ?? "")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.background.secondary)
        }
        .padding()
        .onAppear {
            if hiveID == nil { hiveID = store.hives.first?.id }
        }
    }

    private func send() async {
        guard let hiveID, let link = store.link(for: hiveID) else { return }
        isSending = true
        defer { isSending = false }
        let body = requestBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Data(requestBody.utf8)
        let method = method
        let path = path
        do {
            let answer = try await link.perform { try await $0.send(method: method, path: path, body: body) }
            response = (answer.status, Self.pretty(answer.body))
            failure = nil
        } catch {
            response = nil
            failure = HiveLink.message(for: error)
        }
    }

    private static func pretty(_ data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: formatted, encoding: .utf8)
        else { return String(data: data, encoding: .utf8) ?? "\(data.count) bytes" }
        return text
    }
}
#endif
