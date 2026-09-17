import SwiftUI

final class SessionStore: ObservableObject {

    // MARK: - Published state
    @Published var licenseInfo: LicenseInfo?
    @Published var revocationMessage: String? = nil

    // MARK: - UI prefs
    @Published var languageSelected: Bool {
        didSet { UserDefaults.standard.set(languageSelected, forKey: "ffex.langSelected") }
    }
    @Published var isDarkMode: Bool {
        didSet { UserDefaults.standard.set(isDarkMode, forKey: "ffex.darkMode") }
    }

    var colorScheme: ColorScheme? { isDarkMode ? .dark : .light }

    // MARK: - Revalidation loop
    private var revalTask: Task<Void, Never>?

    // Tolerate up to N consecutive network errors before logging out
    private var networkErrorCount = 0
    private let maxNetworkErrors  = 3

    // MARK: - Init

    init() {
        self.languageSelected = UserDefaults.standard.bool(forKey: "ffex.langSelected")
        self.isDarkMode       = UserDefaults.standard.bool(forKey: "ffex.darkMode")
        // Fast local bootstrap — server confirm happens in restoreAsync()
        if let info = LicenseService.restoreSessionLocal() {
            self.licenseInfo = info
        }
    }

    // MARK: - Server-confirmed restore (call on appear)

    func restoreAsync() async {
        let info = await LicenseService.restoreSession()
        await MainActor.run {
            self.licenseInfo = info
        }
        if info != nil {
            startRevalLoop()
        }
    }

    // MARK: - Login / Logout

    func login(info: LicenseInfo) {
        licenseInfo       = info
        revocationMessage = nil
        networkErrorCount = 0
        startRevalLoop()
    }

    func logout(reason: RevocationReason? = nil) {
        stopRevalLoop()
        LicenseService.logout()
        if let r = reason {
            revocationMessage = r.displayMessage
        }
        licenseInfo = nil
    }

    // MARK: - Async revalidation loop (Task-based, not Timer)
    // Timer.scheduledTimer stops firing when RunLoop.main is blocked or app backgrounds.
    // Task-based loop with sleep is more reliable on iOS.

    private func startRevalLoop() {
        stopRevalLoop()
        revalTask = Task { [weak self] in
            while !Task.isCancelled {
                // Wait 2 seconds between checks
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                guard !Task.isCancelled else { break }
                guard let self, let key = await self.currentKey() else { break }

                let result = await LicenseService.revalidateBackground(key: key)

                await MainActor.run {
                    switch result {
                    case .ok:
                        self.networkErrorCount = 0

                    case .revoked(let reason):
                        // Server confirmed revocation — logout immediately
                        self.logout(reason: reason)

                    case .networkError:
                        // Transient failure — tolerate a few before giving up
                        self.networkErrorCount += 1
                        if self.networkErrorCount >= self.maxNetworkErrors {
                            self.logout(reason: .unknown)
                        }
                    }
                }
            }
        }
    }

    private func stopRevalLoop() {
        revalTask?.cancel()
        revalTask = nil
    }

    @MainActor
    private func currentKey() -> String? {
        licenseInfo?.key
    }
}
