import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var savedTrip: SavedTrip? = SharedDefaults.loadTrip()
    @State private var showingSetup = false

    var body: some View {
        NavigationStack {
            Group {
                if let trip = savedTrip {
                    configuredView(trip: trip)
                } else {
                    emptyStateView
                }
            }
            .navigationTitle("All Aboard")
        }
        .sheet(isPresented: $showingSetup, onDismiss: {
            savedTrip = SharedDefaults.loadTrip()
            WidgetCenter.shared.reloadAllTimelines()
        }) {
            TripSetupView()
        }
        .onAppear {
            if savedTrip == nil { showingSetup = true }
        }
    }

    private func configuredView(trip: SavedTrip) -> some View {
        List {
            Section {
                Label(trip.origin.name, systemImage: "circle.fill")
                    .foregroundStyle(.primary, .green)
                Label(trip.destination.name, systemImage: "mappin.circle.fill")
                    .foregroundStyle(.primary, .red)
            } header: {
                Text("Your trip")
            } footer: {
                Text("Widgets show A→B in the morning and B→A from noon, flipping again at midnight.")
            }

            Section {
                Button("Change stops") { showingSetup = true }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { showingSetup = true }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "tram.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("Set up your commute")
                    .font(.title2.bold())
                Text("Choose two stops and your widgets will show upcoming departures — auto-flipping direction at noon.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button("Set Up Trip") { showingSetup = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }
}
