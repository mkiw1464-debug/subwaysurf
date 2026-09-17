import SwiftUI
import Combine

final class SessionStore: ObservableObject {
    // MARK: - Auth
    @Published var licenseInfo: LicenseInfo?

    // MARK: - UI prefs (persisted)
    @Published var languageSelected: Bool {
        didSet { UserDefaults.standard.set(languageSelected, forKey: "ffex.langSelected") }
    }
    @Published var isDarkMode: Bool {
        didSet { UserDefaults.standard.set(isDarkMode, forKey: "ffex.darkMode") }
    }

    var colorScheme: ColorScheme? { isDarkMode ? .dark : .light }

    // MARK: - Revalidation
    private var revalTimer: Timer?

    init() {
        self.languageSelected = UserDefaults.standard.bool(forKey: "ffex.langSelected")
        self.isDarkMode       = UserDefaults.standard.bool(forKey: "ffex.darkMode")

        // Fast local bootstrap
        if let info = LicenseService.restoreSessionLocal() {
            self.licenseInfo = info
        }
    }

    // Server-confirm on appear
    func restoreAsync() async {
        let info = await LicenseService.restoreSession()
        await MainActor.run { self.licenseInfo = info }
        if info != nil { startRevalTimer() }
    }

    func login(info: LicenseInfo) {
        licenseInfo = info
        startRevalTimer()
    }

    func logout() {
        LicenseService.logout()
        licenseInfo = nil
        stopRevalTimer()
    }

    // MARK: - Periodic revalidation (~2s)
    private func startRevalTimer() {
        stopRevalTimer()
        revalTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, let key = self.licenseInfo?.key else { return }
            Task {
                let ok = await LicenseService.revalidateBackground(key: key)
                if !ok {
                    await MainActor.run { self.logout() }
                }
            }
        }
    }

    private func stopRevalTimer() {
        revalTimer?.invalidate()
        revalTimer = nil
    }
}
