// SettingsView.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Settings screen for configuring the MedSAM2 backend server URL
// and testing the connection.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import SwiftUI

// MARK: - Connection status

private enum ConnectionStatus {
    case idle
    case checking
    case connected(model: String?, device: String?)
    case failed(reason: String)

    var label: String {
        switch self {
        case .idle:                     return "Not checked"
        case .checking:                 return "Checking…"
        case .connected(let m, let d):
            var parts: [String] = []
            if let m { parts.append(m) }
            if let d { parts.append(d) }
            return "Connected" + (parts.isEmpty ? "" : " · \(parts.joined(separator: ", "))")
        case .failed(let reason):       return reason
        }
    }

    var color: Color {
        switch self {
        case .idle:       return .textMuted
        case .checking:   return .textSecondary
        case .connected:  return .success
        case .failed:     return .danger
        }
    }

    var systemImage: String {
        switch self {
        case .idle:       return "circle"
        case .checking:   return "circle.dotted"
        case .connected:  return "checkmark.circle.fill"
        case .failed:     return "xmark.circle.fill"
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: PipelineViewModel

    @State private var serverUrlText: String = ""
    @State private var connectionStatus: ConnectionStatus = .idle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    Spacer(minLength: Spacing.sm)

                    // ── MedSAM2 server section ───────────────────────
                    sectionHeader("MedSAM2 AI Segmentation")
                    serverCard

                    // ── About MedSAM2 section ────────────────────────
                    sectionHeader("About")
                    aboutCard

                    // ── Offline mode notice ──────────────────────────
                    offlineNotice

                    Spacer(minLength: Spacing.xxl)
                }
                .padding(.horizontal, Spacing.md)
            }
            .background(Color.bgPrimary.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.accent)
                        .font(AppFont.body(16, weight: .semibold))
                }
            }
            .onAppear {
                Task {
                    serverUrlText = await MedSAMClient.shared.getServerUrl()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Server card

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // URL row
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Server URL")
                    .font(AppFont.body(13))
                    .foregroundColor(.textMuted)

                TextField("http://localhost:5000", text: $serverUrlText)
                    .font(AppFont.mono(14))
                    .foregroundColor(.textPrimary)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(Spacing.sm)
                    .background(Color.bgTertiary)
                    .cornerRadius(Radius.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .stroke(Color.border, lineWidth: 1)
                    )
                    .submitLabel(.done)
                    .onSubmit { saveUrl() }
            }

            // Status row
            HStack(spacing: Spacing.sm) {
                if case .checking = connectionStatus {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .textSecondary))
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: connectionStatus.systemImage)
                        .foregroundColor(connectionStatus.color)
                        .font(.system(size: 14))
                }
                Text(connectionStatus.label)
                    .font(AppFont.body(13))
                    .foregroundColor(connectionStatus.color)
                    .lineLimit(2)
                Spacer()
            }
            .padding(.vertical, 2)

            // Check button
            Button {
                saveUrl()
                checkConnection()
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Check Connection")
                        .font(AppFont.body(15, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .foregroundColor(.accent)
                .background(Color.accentMuted.opacity(0.15))
                .cornerRadius(Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Color.accent.opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled({
                if case .checking = connectionStatus { return true }
                return false
            }())
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    // MARK: - About card

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            infoRow(icon: "cpu.fill",
                    title: "AI Segmentation",
                    body: "When a MedSAM2 server is available, the app uses AI-powered ventricle segmentation instead of the built-in threshold pipeline.")

            Divider().background(Color.border)

            infoRow(icon: "server.rack",
                    title: "Setup",
                    body: "Run the HydroMorph backend (Python / Flask) on the same network. Enter its URL above. Port 5000 is the default.")

            Divider().background(Color.border)

            infoRow(icon: "lock.shield.fill",
                    title: "Privacy",
                    body: "Images are sent to your own server only. No data is transmitted to third-party services.")
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    // MARK: - Offline notice

    private var offlineNotice: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "wifi.slash")
                .foregroundColor(.warning)
                .font(.system(size: 16))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Offline Fallback")
                    .font(AppFont.body(13, weight: .semibold))
                    .foregroundColor(.warning)
                Text("If the MedSAM2 server is unreachable, HydroMorph automatically falls back to the on-device threshold pipeline. Full functionality without a server.")
                    .font(AppFont.body(12))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.md)
        .background(Color.warning.opacity(0.08))
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.warning.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppFont.body(11, weight: .semibold))
            .foregroundColor(.textMuted)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    // MARK: - Info row

    private func infoRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.accent)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.body(13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(body)
                    .font(AppFont.body(12))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private func saveUrl() {
        let trimmed = serverUrlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            await MedSAMClient.shared.setServerUrl(trimmed)
            await vm.refreshMedSAMStatus()
        }
    }

    private func checkConnection() {
        connectionStatus = .checking
        Task {
            let (available, info) = await MedSAMClient.shared.checkHealth()
            if available {
                connectionStatus = .connected(model: info?.model, device: info?.device)
            } else {
                connectionStatus = .failed(reason: "Server not reachable. Check URL and network.")
            }
        }
    }
}
