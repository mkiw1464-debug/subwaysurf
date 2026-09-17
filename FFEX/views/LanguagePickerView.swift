import SwiftUI

struct LanguagePickerView: View {
    @EnvironmentObject var session: SessionStore
    @StateObject private var langStore = LanguageStore.shared
    @State private var selected: FFLanguage = LanguageStore.shared.current

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("FFEX")
                    .font(.system(size: 32, weight: .bold, design: .default))
                    .foregroundColor(.primary)

                Text("Select Language")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 64)
            .padding(.bottom, 32)

            // Language list
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(FFLanguage.allCases) { lang in
                        Button {
                            selected = lang
                        } label: {
                            HStack {
                                Text(lang.displayName)
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundColor(.primary)
                                Spacer()
                                if selected == lang {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemGroupedBackground))
                        }
                        .buttonStyle(.plain)
                        Divider()
                            .padding(.leading, 20)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal, 20)
            }

            Spacer()

            // Continue button
            Button {
                langStore.select(selected)
                session.languageSelected = true
            } label: {
                Text(selected.t("continue"))
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .environment(\.layoutDirection, selected.isRTL ? .rightToLeft : .leftToRight)
    }
}
