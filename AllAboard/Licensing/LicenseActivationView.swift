import SwiftUI

struct LicenseActivationView: View {
    @State private var licenseKey = ""
    @State private var isActivating = false
    @State private var errorMessage = ""

    var onActivated: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.primary)

                Text("All Aboard")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Enter your license key to get started.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 36)
            .padding(.bottom, 28)

            Divider()

            // Input
            VStack(spacing: 16) {
                TextField("XXXX-XXXX-XXXX-XXXX", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .disableAutocorrection(true)
                    .onSubmit { Task { await activate() } }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }

                Button(action: { Task { await activate() } }) {
                    if isActivating {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Activating…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Activate License")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)
            }
            .padding(24)

            Divider()

            // Footer
            HStack {
                Link("Buy a license →", destination: URL(string: "https://barlow.lemonsqueezy.com")!)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .frame(width: 340)
    }

    private func activate() async {
        let key = licenseKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        isActivating = true
        errorMessage = ""
        do {
            try await LicenseManager.shared.activate(key: key)
            await MainActor.run { onActivated() }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isActivating = false
            }
        }
    }
}
