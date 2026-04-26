import SwiftUI

struct SignInView: View {
    var onSignedIn: () -> Void

    @State private var step: Step = .email
    @State private var email = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage = ""
    @FocusState private var focused: Field?

    enum Step { case email, otp, subscribe }
    enum Field { case email, otp }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.primary)
                Text("All Aboard")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(headline)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 32)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            Divider()

            VStack(spacing: 14) {
                switch step {
                case .email:
                    emailForm
                case .otp:
                    otpForm
                case .subscribe:
                    subscribeForm
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
        .frame(width: 340)
        .onAppear { focused = .email }
    }

    private var headline: String {
        switch step {
        case .email: return "Enter your email to sign in or create an account."
        case .otp: return "Check \(email) for a 6-digit code."
        case .subscribe: return "A subscription is required to use All Aboard."
        }
    }

    // MARK: - Forms

    private var emailForm: some View {
        VStack(spacing: 10) {
            TextField("you@example.com", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .disableAutocorrection(true)
                .focused($focused, equals: .email)
                .onSubmit { Task { await sendCode() } }

            Button(action: { Task { await sendCode() } }) {
                Group {
                    if isWorking {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Sending…") }
                    } else {
                        Text("Send code")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(email.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
        }
    }

    private var otpForm: some View {
        VStack(spacing: 10) {
            TextField("6-digit code", text: $code)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .disableAutocorrection(true)
                .focused($focused, equals: .otp)
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(6))
                    if digits != new { code = digits }
                    if digits.count == 6 { Task { await verifyCode() } }
                }
                .onSubmit { Task { await verifyCode() } }

            Button(action: { Task { await verifyCode() } }) {
                Group {
                    if isWorking {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Verifying…") }
                    } else {
                        Text("Verify")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(code.count != 6 || isWorking)

            HStack {
                Button("Use different email") {
                    step = .email; code = ""; errorMessage = ""; focused = .email
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Resend code") { Task { await sendCode() } }
                    .buttonStyle(.borderless)
                    .disabled(isWorking)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var subscribeForm: some View {
        VStack(spacing: 12) {
            Button(action: { Task { await startTrial() } }) {
                Group {
                    if isWorking {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Starting trial…") }
                    } else {
                        Text("Start 7-day free trial")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking)

            Button("Already subscribed? Check status") { Task { await checkSubscription() } }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(isWorking)

            Button("Sign out") { AuthManager.shared.signOut(); step = .email; email = ""; code = "" }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func sendCode() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        email = trimmed
        isWorking = true
        errorMessage = ""
        defer { isWorking = false }
        do {
            try await AuthManager.shared.requestCode(email: trimmed)
            step = .otp
            code = ""
            focused = .otp
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyCode() async {
        guard code.count == 6, !isWorking else { return }
        isWorking = true
        errorMessage = ""
        defer { isWorking = false }
        do {
            let result = try await AuthManager.shared.verify(email: email, code: code)
            if result.user.isSubscribed {
                onSignedIn()
            } else {
                step = .subscribe
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startTrial() async {
        isWorking = true
        errorMessage = ""
        defer { isWorking = false }
        do {
            try await AuthManager.shared.startTrial()
            onSignedIn()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func checkSubscription() async {
        isWorking = true
        errorMessage = ""
        defer { isWorking = false }
        if let user = await AuthManager.shared.refresh(), user.isSubscribed {
            onSignedIn()
        } else {
            errorMessage = "No active subscription found. Complete your purchase and try again."
        }
    }
}
