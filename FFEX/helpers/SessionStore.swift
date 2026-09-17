import SwiftUI
import Combine

final class SessionStore: ObservableObject {
    // MARK: - Auth
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

    // MARK: - Revalidation
    private var revalTimer: Timer?

    // Consecutive network errors — only logout after confirmed revocation, not transient errors
    private var networkErrorCount = 0
    private let maxNetworkErrors  = 5

    init() {
        self.languageSelected = UserDefaults.standard.bool(forKey: "ffex.langSelected")
        self.isDarkMode       = UserDefaults.standard.bool(forKey: "ffex.darkMode")
        if let info = LicenseService.restoreSessionLocal() {
            self.licenseInfo = info
        }
    }

    func restoreAsync() async {
        let info = await LicenseService.restoreSession()
        await MainActor.run { self.licenseInfo = info }
        if info != nil { startRevalTimer() }
    }

    func login(info: LicenseInfo) {
        licenseInfo       = info
        revocationMessage = nil
        networkErrorCount = 0
        startRevalTimer()
    }

    func logout(reason: RevocationReason? = nil) {
        LicenseService.logout()
        if let r = reason {
            revocationMessage = r.displayMessage
        }
        licenseInfo = nil
        stopRevalTimer()
    }

    // MARK: - Revalidation every 2s

    private func startRevalTimer() {
        stopRevalTimer()
        revalTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, let key = self.licenseInfo?.key else { return }
            Task {
                let result = await LicenseService.revalidateBackground(key: key)
                await MainActor.run {
                    switch result {
                    case .ok:
                        self.networkErrorCount = 0

                    case .revoked(let reason):
                        // Confirmed by server — logout immediately
                        self.logout(reason: reason)

                    case .networkError:
                        // Transient — tolerate up to maxNetworkErrors then logout
                        self.networkErrorCount += 1
                        if self.networkErrorCount >= self.maxNetworkErrors {
                            self.logout(reason: .unknown)
                        }
                    }
                }
            }
        }
    }

    private func stopRevalTimer() {
        revalTimer?.invalidate()
        revalTimer = nil
    }
}
