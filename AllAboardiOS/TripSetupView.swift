import SwiftUI

struct TripSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedOrigin: StopLocation?
    @State private var selectedDestination: StopLocation?
    @State private var showingOriginSearch = false
    @State private var showingDestinationSearch = false

    var canSave: Bool { selectedOrigin != nil && selectedDestination != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("From") {
                    stopRow(
                        label: selectedOrigin.map { $0.disassembledName ?? $0.name } ?? "Choose origin station",
                        isPlaceholder: selectedOrigin == nil,
                        action: { showingOriginSearch = true }
                    )
                }
                Section("To") {
                    stopRow(
                        label: selectedDestination.map { $0.disassembledName ?? $0.name } ?? "Choose destination station",
                        isPlaceholder: selectedDestination == nil,
                        action: { showingDestinationSearch = true }
                    )
                }
            }
            .navigationTitle("Set Up Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveAndDismiss() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .sheet(isPresented: $showingOriginSearch) {
            StopSearchScreen(selected: $selectedOrigin)
        }
        .sheet(isPresented: $showingDestinationSearch) {
            StopSearchScreen(selected: $selectedDestination)
        }
    }

    private func stopRow(label: String, isPlaceholder: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(isPlaceholder ? .secondary : .primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func saveAndDismiss() {
        guard let origin = selectedOrigin, let destination = selectedDestination else { return }
        let trip = SavedTrip(
            id: UUID().uuidString,
            name: "\(origin.name) → \(destination.name)",
            origin: StopRef(id: origin.id, name: origin.disassembledName ?? origin.name),
            destination: StopRef(id: destination.id, name: destination.disassembledName ?? destination.name),
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
        SharedDefaults.saveTrip(trip)
        dismiss()
    }
}
