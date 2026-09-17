import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: SessionStore
    @StateObject private var langStore = LanguageStore.shared

    @State private var keyInput: String = ""
    @State private var isValidating = false
    @State private var errorMessage: String? = nil
    @State private var didAppear = false

    private var t: (String) -> String { langStore.t }

    // Support check
    private var vt: (major: Int, minor: Int, patch: Int) { AppInfo.versionTuple }
    private var buildStr: String { AppInfo.osBuild }
    private var isSupported: Bool {
        ExploitSupportPolicy.isSupported(
            major: vt.major, minor: vt.minor, patch: vt.patch, build: buildStr
        )
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Top controls (theme / language / no logout here — not logged in)
            HStack {
                Spacer()
                HStack(spacing: 16) {
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
                }
                .padding(.trailing, 20)
                .padding(.top, 16)
            }

            ScrollView {
                VStack(spacing: 24) {

                    // ── App name
                    VStack(spacing: 6) {
                        Text("FFEX")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 20)

                    // ── Key input card
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(t("key_placeholder"), text: $keyInput)
                            .font(.system(size: 15, design: .monospaced))
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                            .keyboardType(.asciiCapable)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(10)
                            .onChange(of: keyInput) { val in
                                keyInput = val.uppercased()
                                errorMessage = nil
                            }

                        if let err = errorMessage {
                            Text(err)
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                                .padding(.horizontal, 4)
                        }

                        Button {
                            validate()
                        } label: {
                            Group {
                                if isValidating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text(t("validate"))
                                        .font(.system(size: 15, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(keyInput.isEmpty ? Color.accentColor.opacity(0.4) : Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(keyInput.isEmpty || isValidating)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)
                    .padding(.horizontal, 20)

                    // ── Device support card
                    VStack(alignment: .leading, spacing: 12) {
                        deviceRow(label: t("device"),      value: AppInfo.iPhoneModel)
                        Divider()
                        deviceRow(label: "Model",          value: AppInfo.machineID)
                        Divider()
                        deviceRow(label: t("ios_version"), value: AppInfo.iOSVersion)
                        Divider()
                        HStack {
                            Text(t("supported"))
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Spacer()
                            if isSupported {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.green)
                                    Text(t("verified"))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.green)
                                }
                            } else {
                                Text(t("not_supported"))
                                    .font(.system(size: 13))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)
                    .padding(.horizontal, 20)

                    // ── Telegram
                    Button {
                        if let url = URL(string: "https://t.me/ffexternal") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane")
                                .font(.system(size: 14))
                            Text("t.me/ffexternal")
                                .font(.system(size: 14))
                        }
                        .foregroundColor(.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(10)
                        .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .environment(\.layoutDirection, langStore.current.isRTL ? .rightToLeft : .leftToRight)
        .onAppear {
            if !didAppear {
                didAppear = true
                if let msg = session.revocationMessage {
                    errorMessage = msg
                    session.revocationMessage = nil
                }
                Task { await session.restoreAsync() }
            }
        }
    }

    // MARK: - Validate

    private func validate() {
        guard !keyInput.isEmpty, !isValidating else { return }
        isValidating = true
        errorMessage = nil
        Task {
            do {
                let info = try await LicenseService.validate(key: keyInput)
                await MainActor.run { session.login(info: info) }
            } catch let e as LicenseError {
                await MainActor.run {
                    errorMessage  = e.errorDescription
                    isValidating  = false
                }
            } catch {
                await MainActor.run {
                    errorMessage  = t("key_invalid")
                    isValidating  = false
                }
            }
        }
    }

    // MARK: - Language cycle

    private func nextLanguage() -> FFLanguage {
        let all = FFLanguage.allCases
        let idx = all.firstIndex(of: langStore.current) ?? 0
        return all[(idx + 1) % all.count]
    }

    // MARK: - Row helper

    @ViewBuilder
    private func deviceRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}
