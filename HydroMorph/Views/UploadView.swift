// UploadView.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// File picker screen with drop zone, sample data button, and privacy notice.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import SwiftUI
import UniformTypeIdentifiers

// MARK: - NIfTI UTType

extension UTType {
    /// Custom UTType for NIfTI files. Falls back to generic data type.
    static let nifti = UTType(filenameExtension: "nii") ?? .data
    static let niftiGz = UTType(filenameExtension: "nii.gz") ?? .gzip
}

// MARK: - Upload View

struct UploadView: View {
    @EnvironmentObject var vm: PipelineViewModel

    @State private var isShowingFilePicker = false
    @State private var isDraggingOver = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                Spacer(minLength: Spacing.xxl)

                // ── Header ──────────────────────────────────────────
                headerSection

                // ── Drop zone ───────────────────────────────────────
                dropZone
                    .onDrop(of: [.data, UTType.nifti], isTargeted: $isDraggingOver) { providers in
                        handleDrop(providers: providers)
                        return true
                    }

                // ── Privacy strip ───────────────────────────────────
                privacyStrip

                // ── Error ───────────────────────────────────────────
                if vm.showError, let msg = vm.errorMessage {
                    errorBanner(msg)
                }

                // ── Sample data button ──────────────────────────────
                sampleButton

                // ── Footer ──────────────────────────────────────────
                footerSection

                Spacer(minLength: Spacing.xxl)
            }
            .padding(.horizontal, Spacing.md)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [UTType.nifti, UTType.niftiGz, .data, .gzip],
            allowsMultipleSelection: false
        ) { result in
            handleFileImporterResult(result)
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: Spacing.sm) {
            Text("🧠")
                .font(.system(size: 56))
            Text("HydroMorph")
                .font(AppFont.body(32, weight: .bold))
                .foregroundColor(.textPrimary)
            Text("Hydrocephalus Morphometrics Pipeline")
                .font(AppFont.body(15))
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var dropZone: some View {
        Button {
            vm.showError = false
            isShowingFilePicker = true
        } label: {
            VStack(spacing: Spacing.md) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(isDraggingOver ? .accent : .textSecondary)

                Text("Tap to select a head CT scan")
                    .font(AppFont.body(17, weight: .semibold))
                    .foregroundColor(.textPrimary)

                Text("Or drag and drop your file here.\nNo data ever leaves your device.")
                    .font(AppFont.body(13))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: Spacing.sm) {
                    FormatBadge(label: ".nii")
                    FormatBadge(label: ".nii.gz")
                }
            }
            .padding(.vertical, Spacing.xl)
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .stroke(
                        isDraggingOver ? Color.accent : Color.border,
                        style: StrokeStyle(lineWidth: isDraggingOver ? 2 : 1, dash: [6, 4])
                    )
            )
            .background(
                Color(isDraggingOver ? Color.accentMuted.description : Color.bgSecondary.description)
                    .opacity(isDraggingOver ? 0.1 : 1)
                    .cornerRadius(Radius.lg)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isDraggingOver)
    }

    private var privacyStrip: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "lock.fill")
                .foregroundColor(.success)
            Group {
                Text("100% On-Device").bold()
                + Text(" — All processing happens locally. Zero server uploads.")
            }
            .font(AppFont.body(13))
            .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgSecondary)
        .cornerRadius(Radius.md)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.border, lineWidth: 1))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.danger)
            Text(message)
                .font(AppFont.body(13))
                .foregroundColor(.danger)
                .multilineTextAlignment(.leading)
            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.danger.opacity(0.12))
        .cornerRadius(Radius.md)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.danger.opacity(0.4), lineWidth: 1))
        .transition(.opacity)
    }

    private var sampleButton: some View {
        Button {
            vm.showError = false
            vm.loadSampleData()
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accent)
                Text("Try with sample CT scan")
                    .font(AppFont.body(15, weight: .medium))
                    .foregroundColor(.accent)
            }
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(Color.accentMuted.opacity(0.12))
            .cornerRadius(Radius.md)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.accent.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("Supports NIfTI-1 format · Head CT in Hounsfield Units")
                .font(AppFont.body(12))
                .foregroundColor(.textMuted)
            HStack(spacing: 4) {
                Text("Built by")
                    .foregroundColor(.textMuted)
                Text("Matheus Machado Rech")
                    .foregroundColor(.accent)
            }
            .font(AppFont.body(12, weight: .medium))
            Text("Research use only · Not for clinical diagnosis")
                .font(AppFont.body(11))
                .foregroundColor(.textMuted)
                .opacity(0.6)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - File handling

    private func handleFileImporterResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let name = url.lastPathComponent.lowercased()
            guard name.hasSuffix(".nii") || name.hasSuffix(".nii.gz") else {
                vm.errorMessage = "Please select a NIfTI file (.nii or .nii.gz)"
                vm.showError = true
                return
            }
            vm.loadFile(url: url)
        case .failure(let error):
            vm.errorMessage = error.localizedDescription
            vm.showError = true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
            // Cannot easily get filename from drop; guide user to file picker
            DispatchQueue.main.async {
                self.isShowingFilePicker = true
            }
        }
    }
}

// MARK: - Format badge

private struct FormatBadge: View {
    let label: String
    var body: some View {
        Text(label)
            .font(AppFont.mono(12, weight: .medium))
            .foregroundColor(.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.bgTertiary)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.border, lineWidth: 1))
    }
}
