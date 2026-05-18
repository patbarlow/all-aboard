import AppIntents

struct ShowNextTrainsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Next Trains"
    static var description = IntentDescription(
        "Shows the next departures for your saved trip as a Live Activity on your Lock Screen and Dynamic Island."
    )

    // Don't open the app — just start the Live Activity silently
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        await LiveActivityManager.shared.start()
        return .result()
    }
}
