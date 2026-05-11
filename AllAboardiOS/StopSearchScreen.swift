import SwiftUI

struct StopSearchScreen: View {
    @Binding var selected: StopLocation?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [StopLocation] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List(results) { stop in
                Button {
                    selected = stop
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.disassembledName ?? stop.name)
                            .foregroundStyle(.primary)
                        if let locality = stop.properties?.mainLocality {
                            Text(locality)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if isSearching {
                    ProgressView()
                } else if results.isEmpty && query.count >= 2 {
                    ContentUnavailableView("No stations found", systemImage: "tram", description: Text("Try a different name."))
                } else if query.count < 2 {
                    ContentUnavailableView("Search for a station", systemImage: "magnifyingglass")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Station name")
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                guard newValue.count >= 2 else {
                    results = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    isSearching = true
                    results = (try? await APIClient.shared.searchStops(query: newValue)) ?? []
                    isSearching = false
                }
            }
            .navigationTitle("Search Stations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
