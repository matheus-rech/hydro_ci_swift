// UploadView.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// File picker screen supporting NIfTI, DICOM series, PNG, and JPEG files.
// Includes a settings gear button for MedSAM2 server configuration.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Custom UTTypes

extension UTType {
    /// NIfTI files (.nii)
    static let nifti   = UTType(filenameExtension: "nii")   ?? .data
    /// Gzip-compressed NIfTI files (.nii.gz) — treated as gzip by the system
    static let niftiGz = UTType(filenameExtension: "nii.gz") ?? .gzip
    /// DICOM files (.dcm)
    static let dicom   = UTType(filenameExtension: "dcm")   ?? .data
}

// MARK: - File type classification

private enum FileKind {
    case nifti
    case dicomSeries([URL])
    case image(URL)
    case unknown(String)

    static func classify(urls: [URL]) -> FileKind {
        guard !urls.isEmpty else { return .unknown("No file selected") }

        // Multiple files → treat as DICOM series
        if urls.count > 1 { return .dicomSeries(urls) }

        let url  = urls[0]
        let name = url.lastPathComponent.lowercased()

        if name.hasSuffix(".nii") || name.hasSuffix(".nii.gz") {
            return .nifti
        }
        if name.hasSuffix(".dcm") || name.hasSuffix(".dicom") {
            return .dicomSeries([url])
        }
        if name.hasSuffix(".png") || name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") {
            return .image(url)
        }

        // Try DICOM magic byte detection (DICM at offset 128)
        if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           data.count > 132,
           String(data: data[128..<132], encoding: .ascii) == "DICM" {
            return .dicomSeries([url])
        }

        return .unknown("Unsupported format: \(url.pathExtension.isEmpty ? "unknown" : url.pathExtension)")
    }
}

// MARK: - Upload View

struct UploadView: View {
    @EnvironmentObject var vm: PipelineViewModel

    @State private var isShowingFilePicker   = false
    @State private var isDraggingOver        = false

    // Supported types for the file importer
    private let supportedTypes: [UTType] = [
        .nifti, .niftiGz, .dicom, .png, .jpeg, .gzip, .data
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    Spacer(minLength: Spacing.xxl)

                    // ── Header ──────────────────────────────────────────
                    headerSection

                    // ── MedSAM2 status pill ──────────────────────────────
                    if vm.medSAMAvailable {
                        medSAMBadge
                    }

                    // ── Drop zone ───────────────────────────────────────
                    dropZone
                        .onDrop(of: [.data, .nifti, .dicom, .png, .jpeg],
                                isTargeted: $isDraggingOver) { providers in
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
            // Settings gear in top-right
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        vm.showSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .fileImporter(
                isPresented: $isShowingFilePicker,
                allowedContentTypes: supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                handleFileImporterResult(result)
            }
            .navigationBarHidden(true)
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

    private var medSAMBadge: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundColor(.accent)
            Text("MedSAM2 AI ready")
                .font(AppFont.body(12, weight: .medium))
                .foregroundColor(.accent)
            if !vm.medSAMInfo.isEmpty {
                Text("· \(vm.medSAMInfo)")
                    .font(AppFont.body(12))
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 6)
        .background(Color.accent.opacity(0.10))
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.accent.opacity(0.25), lineWidth: 1)
        )
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

                // Format badges
                VStack(spacing: 6) {
                    HStack(spacing: Spacing.sm) {
                        FormatBadge(label: ".nii")
                        FormatBadge(label: ".nii.gz")
                        FormatBadge(label: ".dcm")
                    }
                    HStack(spacing: Spacing.sm) {
                        FormatBadge(label: ".png")
                        FormatBadge(label: ".jpg")
                        Text("· multi-file DICOM series supported")
                            .font(AppFont.body(10))
                            .foregroundColor(.textMuted)
                    }
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
            Text("NIfTI · DICOM · PNG · JPEG · Head CT in Hounsfield Units")
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
            routeFiles(urls: urls)
        case .failure(let error):
            vm.errorMessage = error.localizedDescription
            vm.showError = true
        }
    }

    private func routeFiles(urls: [URL]) {
        vm.showError = false
        let kind = FileKind.classify(urls: urls)
        switch kind {
        case .nifti:
            guard let url = urls.first else { return }
            vm.loadFile(url: url)

        case .dicomSeries(let dicomUrls):
            vm.loadDicomSeries(urls: dicomUrls)

        case .image(let url):
            vm.loadImageFile(url: url)

        case .unknown(let reason):
            vm.errorMessage = reason + ". Supported formats: .nii, .nii.gz, .dcm, .png, .jpg"
            vm.showError = true
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        // Dropping works best from Files app; open the picker as guidance
        DispatchQueue.main.async {
            self.isShowingFilePicker = true
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
