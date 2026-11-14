import SwiftUI

/// Warren → Settings… (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 460)
    }
}

private struct GeneralSettings: View {
    @AppStorage(SessionStore.restoreAtLaunchKey) private var restoreAtLaunch = false
    @EnvironmentObject private var updater: AppUpdater

    var body: some View {
        Form {
            Toggle("Reopen windows and tabs from last session when Warren opens", isOn: $restoreAtLaunch)
            Text("Otherwise, History → Reopen All Windows from Last Session brings them back.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if updater.isEnabled {
                Divider()
                    .padding(.vertical, 6)
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                Toggle("Automatically download and install updates", isOn: $updater.automaticallyDownloadsUpdates)
                    .disabled(!updater.automaticallyChecksForUpdates)
                HStack {
                    Text("Downloaded updates install when you quit Warren.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }
        }
        .padding(20)
    }
}

private struct AppearanceSettings: View {
    @AppStorage(Theme.storageKey) private var theme = Theme.monochrome

    var body: some View {
        Form {
            Picker("Accent colors:", selection: $theme) {
                ForEach(Theme.allCases) { theme in
                    ThemeRow(theme: theme).tag(theme)
                }
            }
            .pickerStyle(.radioGroup)
            Text("Gopher themes add a touch of color to links and the active tab, adapted for dark mode.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct ThemeRow: View {
    let theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            Text(theme.name)
                .frame(width: 110, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(Array(theme.swatches.enumerated()), id: \.offset) { _, color in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(nsColor: color))
                        .frame(width: 14, height: 14)
                }
            }
        }
    }
}
