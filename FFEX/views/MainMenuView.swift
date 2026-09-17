import SwiftUI

// MARK: - Inject state per game

enum InjectState: Equatable {
    case idle
    case checking
    case ready
    case unavailable
    case injecting
    case done
    case failed(String)
}

// MARK: - MainMenuView

struct MainMenuView: View {
    @EnvironmentObject var session: SessionStore
    @StateObject private var langStore = LanguageStore.shared

    @State private var isOnline: Bool? = nil
    @State private var showLogoutAlert = false

    // Per-game states
    @State private var ffState:    InjectState = .checking
    @State private var ffmaxState: InjectState = .checking

    // Real-time countdown timer
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // Active sessions (retain to keep files deployed)
    @State private var ffSession:    InjectSession? = nil
    @State private var ffmaxSession: InjectSession? = nil

    private var t: (String) -> String { langStore.t }

    private var info: LicenseInfo? { session.licenseInfo }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Top bar
            HStack(alignment: .center) {
                Text("FFEX")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                HStack(spacing: 18) {
                    Button { langStore.select(nextLanguage()) } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 17))
                            .foregroundColor(.secondary)
                    }
                    Button { session.isDarkMode.toggle() } label: {
                        Image(systemName: session.isDarkMode ? "sun.max" : "moon")
                            .font(.system(size: 17))
                            .foregroundColor(.secondary)
                    }
                    Button { showLogoutAlert = true } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 17))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(spacing: 16) {

                    // ── Info card
                    infoCard

                    // ── Status
                    statusRow

                    // ── Game buttons
                    gameSection(game: .freeFire,    state: $ffState,    activeSession: $ffSession)
                    gameSection(game: .freefireMax, state: $ffmaxState, activeSession: $ffmaxSession)

                    // ── Telegram
                    Button {
                        UIApplication.shared.open(URL(string: "https://t.me/ffexternal")!)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane")
                                .font(.system(size: 13))
                            Text("t.me/ffexternal")
                                .font(.system(size: 13))
                        }
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 40)
                }
                .padding(.top, 16)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .environment(\.layoutDirection, langStore.current.isRTL ? .rightToLeft : .leftToRight)
        .onReceive(timer) { _ in now = Date() }
        .task { await checkAvailabilityAll() }
        .task {
            // Auto-refresh availability every 30s
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await checkAvailabilityAll()
            }
        }
        .alert(t("logout_confirm_title"), isPresented: $showLogoutAlert) {
            Button(t("logout_confirm_yes"), role: .destructive) {
                terminateAllSessions()
                session.logout()
            }
            Button(t("logout_confirm_cancel"), role: .cancel) {}
        } message: {
            Text(t("logout_confirm_msg"))
        }
    }

    // MARK: - Info card

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Masked key
            if let key = info?.key {
                HStack {
                    Text(LicenseService.maskedKey(key))
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                    Spacer()
                }
            }

            Divider()

            // Device rows
            infoRow(label: t("device"),      value: AppInfo.iPhoneModel)
            Divider()
            infoRow(label: t("ios_version"), value: AppInfo.iOSVersion)
            Divider()

            // Expiry countdown
            HStack {
                Text(t("expires"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
                if let exp = info?.expiryDate {
                    Text(LicenseService.countdownString(from: exp))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(exp.timeIntervalSinceNow < 3600 ? .orange : .primary)
                        .onReceive(timer) { _ in }  // trigger redraw
                }
            }

            Divider()

            // Support status
            HStack {
                Text(t("supported"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
                let vt = AppInfo.versionTuple
                if ExploitSupportPolicy.isSupported(
                    major: vt.major, minor: vt.minor, patch: vt.patch, build: AppInfo.osBuild) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.green)
                        Text(t("verified"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                } else {
                    Text(t("not_supported"))
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .padding(.horizontal, 20)
    }

    // MARK: - Status row

    private var statusRow: some View {
        HStack {
            Circle()
                .fill(isOnline == true ? Color.green : (isOnline == nil ? Color.orange : Color.red))
                .frame(width: 8, height: 8)
            Text(isOnline == true ? t("status_online") : (isOnline == nil ? t("checking") : t("status_offline")))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(10)
        .padding(.horizontal, 20)
    }

    // MARK: - Game section

    @ViewBuilder
    private func gameSection(
        game: FFGame,
        state: Binding<InjectState>,
        activeSession: Binding<InjectSession?>
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(game.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
            Spacer()
            injectButton(game: game, state: state, activeSession: activeSession)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func injectButton(
        game: FFGame,
        state: Binding<InjectState>,
        activeSession: Binding<InjectSession?>
    ) -> some View {
        let current = state.wrappedValue
        let isUnavailable = current == .unavailable || current == .checking
        let isWorking     = current == .injecting
        let isDone        = current == .done

        Button {
            Task { await handleInject(game: game, state: state, activeSession: activeSession) }
        } label: {
            Group {
                switch current {
                case .checking:
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 20, height: 20)
                case .unavailable:
                    Text(t("unavailable"))
                        .font(.system(size: 13, weight: .semibold))
                case .injecting:
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 20, height: 20)
                case .done:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text(t("inject"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                case .failed:
                    Text(t("inject"))
                        .font(.system(size: 13, weight: .semibold))
                default:
                    Text(t("inject"))
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(buttonColor(for: current))
            .foregroundColor(.white)
            .cornerRadius(9)
        }
        .disabled(isUnavailable || isWorking)
    }

    private func buttonColor(for state: InjectState) -> Color {
        switch state {
        case .unavailable, .checking: return Color.secondary.opacity(0.5)
        case .done:                   return .green
        case .failed:                 return .red
        default:                      return .accentColor
        }
    }

    // MARK: - Inject flow

    private func handleInject(
        game: FFGame,
        state: Binding<InjectState>,
        activeSession: Binding<InjectSession?>
    ) async {
        guard case .ready = state.wrappedValue else { return }
        guard let key = session.licenseInfo?.key else { return }

        // Re-validate session
        let ok = await LicenseService.revalidateBackground(key: key)
        guard ok else {
            await MainActor.run { session.logout() }
            return
        }

        await MainActor.run { state.wrappedValue = .injecting }

        do {
            let injectSession = try await FFInjectService.inject(game: game, key: key)
            await MainActor.run {
                activeSession.wrappedValue = injectSession
                state.wrappedValue = .done
            }
            // Small delay then launch game
            try? await Task.sleep(nanoseconds: 600_000_000)
            FFInjectService.launchGame(game)
        } catch {
            await MainActor.run {
                state.wrappedValue = .failed(error.localizedDescription)
            }
            // Reset to ready after 3s so they can retry
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { state.wrappedValue = .ready }
        }
    }

    // MARK: - Availability check

    private func checkAvailabilityAll() async {
        let available = await FFAvailabilityService.checkAvailability()
        await MainActor.run {
            isOnline     = available
            ffState      = available ? .ready : .unavailable
            ffmaxState   = available ? .ready : .unavailable
        }
    }

    // MARK: - Cleanup

    private func terminateAllSessions() {
        if let s = ffSession    { FFInjectService.terminateSession(s); ffSession    = nil }
        if let s = ffmaxSession { FFInjectService.terminateSession(s); ffmaxSession = nil }
    }

    // MARK: - Language cycle

    private func nextLanguage() -> FFLanguage {
        let all = FFLanguage.allCases
        let idx = all.firstIndex(of: langStore.current) ?? 0
        return all[(idx + 1) % all.count]
    }

    // MARK: - Row helper

    @ViewBuilder
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}
