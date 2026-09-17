import SwiftUI

@main
struct FFEXApp: App {
    init() {
        AntiDebug.runChecks()
        AntiDebug.startPeriodicChecks()
        setupLogCapture()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    @StateObject private var session = SessionStore()

    var body: some View {
        Group {
            if session.languageSelected {
                if session.licenseInfo != nil {
                    MainMenuView()
                        .environmentObject(session)
                } else {
                    LoginView()
                        .environmentObject(session)
                }
            } else {
                LanguagePickerView()
                    .environmentObject(session)
            }
        }
        .preferredColorScheme(session.colorScheme)
    }
}
