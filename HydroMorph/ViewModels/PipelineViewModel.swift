// PipelineViewModel.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// ObservableObject managing pipeline state, progress, and results.
// Supports NIfTI, DICOM series, and image files.
// Integrates with MedSAM2 AI segmentation when available, with automatic
// fallback to the on-device threshold pipeline.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import Foundation
import SwiftUI

// MARK: - App screens

enum AppScreen {
    case upload
    case processing
    case results
}

// MARK: - Progress step state

struct ProgressStep: Identifiable {
    let id: Int
    let label: String
    var state: StepState

    enum StepState {
        case pending, active, done
    }
}

// MARK: - ViewModel

@MainActor
final class PipelineViewModel: ObservableObject {

    // MARK: Navigation
    @Published var currentScreen: AppScreen = .upload

    // MARK: Processing state
    @Published var steps: [ProgressStep] = pipelineSteps.enumerated().map {
        ProgressStep(id: $0.offset, label: $0.element, state: .pending)
    }
    @Published var currentStepIndex: Int = 0
    @Published var progressDetail: String = "Initializing pipeline…"

    // MARK: Volume metadata (shown during processing)
    @Published var volumeShape: String = "—"
    @Published var volumeSpacing: String = "—"
    @Published var volumeDatatype: String = "—"
    @Published var volumeFileSize: String = "—"
    @Published var processingFileName: String = "—"

    // MARK: Results
    @Published var result: PipelineResult?
    @Published var volume: Volume?

    // MARK: Axial viewer state
    @Published var currentAxialSlice: Int = 0
    @Published var showMask: Bool = true

    // MARK: Errors
    @Published var errorMessage: String?
    @Published var showError: Bool = false

    // MARK: MedSAM2 status
    @Published var medSAMAvailable: Bool = false
    @Published var medSAMInfo: String = ""

    // MARK: Settings sheet
    @Published var showSettings: Bool = false

    // MARK: - Init

    init() {
        Task { await checkMedSAMHealth() }
    }

    // MARK: - MedSAM2 health check

    func checkMedSAMHealth() async {
        let (available, info) = await MedSAMClient.shared.checkHealth()
        medSAMAvailable = available
        if available {
            var parts: [String] = []
            if let m = info?.model  { parts.append(m) }
            if let d = info?.device { parts.append(d) }
            medSAMInfo = parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
        } else {
            medSAMInfo = ""
        }
    }

    /// Called from SettingsView when the URL is changed.
    func refreshMedSAMStatus() async {
        await checkMedSAMHealth()
    }

    // MARK: - Load NIfTI file from URL

    func loadFile(url: URL) {
        processingFileName = url.lastPathComponent
        switchToProcessing()

        Task {
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }

                let fileData = try Data(contentsOf: url)
                let fileSizeMB = String(format: "%.1f MB", Double(fileData.count) / (1024 * 1024))
                volumeFileSize = fileSizeMB

                await setProgress(0, "Decompressing & parsing NIfTI…")
                let vol = try NiftiReader.parse(fileData)
                volume = vol
                updateMetadata(vol)

                try await runPipeline(vol)

            } catch {
                await handleError(error)
            }
        }
    }

    // MARK: - Load DICOM series from multiple URLs

    func loadDicomSeries(urls: [URL]) {
        let names = urls.map { $0.lastPathComponent }
        processingFileName = names.count == 1
            ? names[0]
            : "\(names.count) DICOM files"
        switchToProcessing()

        Task {
            do {
                await setProgress(0, "Reading \(urls.count) DICOM file(s)…")

                var dataFiles = [Data]()
                for url in urls {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    dataFiles.append(data)
                }

                let totalBytes = dataFiles.reduce(0) { $0 + $1.count }
                volumeFileSize = String(format: "%.1f MB", Double(totalBytes) / (1024 * 1024))

                await setProgress(0, "Parsing DICOM series…")
                let vol = try DicomReader.parseSeries(dataFiles)
                volume = vol
                updateMetadata(vol, sourceLabel: "DICOM")

                try await runPipelineWithMedSAM(vol)

            } catch {
                await handleError(error)
            }
        }
    }

    // MARK: - Load image file (PNG / JPEG)

    func loadImageFile(url: URL) {
        processingFileName = url.lastPathComponent
        switchToProcessing()

        Task {
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }

                let fileData = try Data(contentsOf: url)
                volumeFileSize = String(format: "%.1f MB", Double(fileData.count) / (1024 * 1024))

                await setProgress(0, "Loading image…")
                let vol = try DicomReader.parseImage(fileData)
                volume = vol
                updateMetadata(vol, sourceLabel: "Image")

                try await runPipelineWithMedSAM(vol)

            } catch {
                await handleError(error)
            }
        }
    }

    // MARK: - Load sample data from bundled JSON

    func loadSampleData() {
        processingFileName = "Sample CT — CADS BrainCT-1mm Subject 155"
        switchToProcessing()

        Task {
            do {
                await setProgress(0, "Fetching sample CT scan (~430 KB)…")
                guard let url = Bundle.main.url(forResource: "sample-data", withExtension: "json") else {
                    throw NSError(domain: "HydroMorph", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "Sample data not found in bundle."])
                }
                let jsonData = try Data(contentsOf: url)

                await setProgress(0, "Decompressing sample volume…")
                let sample = try JSONDecoder().decode(SampleDataJSON.self, from: jsonData)

                guard let compressed = Data(base64Encoded: sample.data_b64_gzip_int16) else {
                    throw NSError(domain: "HydroMorph", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 sample data."])
                }
                guard let decompressed = NiftiReader.gunzip(compressed) else {
                    throw NSError(domain: "HydroMorph", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to decompress sample data."])
                }

                let int16Count = decompressed.count / 2
                var floatData = [Float](repeating: 0, count: int16Count)
                decompressed.withUnsafeBytes { ptr in
                    let int16Ptr = ptr.bindMemory(to: Int16.self)
                    for i in 0..<min(int16Count, int16Ptr.count) {
                        floatData[i] = Float(int16Ptr[i])
                    }
                }

                let vol = Volume(
                    dimX: sample.shape[0], dimY: sample.shape[1], dimZ: sample.shape[2],
                    spacingX: sample.spacing[0], spacingY: sample.spacing[1], spacingZ: sample.spacing[2],
                    data: floatData,
                    datatype: 16, bitpix: 32, voxOffset: 352, sformCode: 0
                )

                volume = vol
                volumeFileSize = String(format: "%.1f MB", Double(compressed.count) / (1024 * 1024))
                updateMetadata(vol)

                try await runPipeline(vol)

            } catch {
                await handleError(error)
            }
        }
    }

    // MARK: - Reset

    func reset() {
        result = nil
        volume = nil
        currentAxialSlice = 0
        showMask = true
        errorMessage = nil
        showError = false
        steps = pipelineSteps.enumerated().map {
            ProgressStep(id: $0.offset, label: $0.element, state: .pending)
        }
        currentScreen = .upload
        // Re-check MedSAM2 availability when returning to upload screen
        Task { await checkMedSAMHealth() }
    }

    // MARK: - Private: pipeline runner (threshold only)

    private func runPipeline(_ vol: Volume) async throws {
        let pipeline = MorphometricsPipeline()
        await pipeline.setProgressHandler { [weak self] stepIdx, message in
            guard let self else { return }
            Task { @MainActor in
                self.advanceSteps(to: stepIdx)
                self.progressDetail = message
            }
        }

        let res = try await pipeline.run(volume: vol, segmentationMethod: .threshold)

        result = res
        currentAxialSlice = res.evansSlice >= 0 ? res.evansSlice : vol.dimZ / 2
        finishAllSteps()
        currentScreen = .results
    }

    // MARK: - Private: pipeline runner with MedSAM2 attempt

    /// Tries MedSAM2 segmentation first; if unavailable or it fails, falls back
    /// to the on-device threshold pipeline.
    private func runPipelineWithMedSAM(_ vol: Volume) async throws {
        // Check MedSAM2 availability
        await checkMedSAMHealth()

        if medSAMAvailable {
            do {
                try await runMedSAMPipeline(vol)
                return
            } catch {
                // Log fallback reason and continue to threshold pipeline
                await setProgress(1, "MedSAM2 unavailable (\(error.localizedDescription)). Falling back to threshold pipeline…")
            }
        }

        // Fallback: threshold pipeline
        try await runPipeline(vol)
    }

    // MARK: - Private: MedSAM2 pipeline runner

    private func runMedSAMPipeline(_ vol: Volume) async throws {
        await setProgress(0, "Sending volume to MedSAM2 server…")

        let maskBytes = try await MedSAMClient.shared.segment(
            volumeData: vol.data,
            shape: vol.shape,
            spacing: vol.spacing
        )

        // Validate mask size
        guard maskBytes.count == vol.totalVoxels else {
            throw NSError(domain: "HydroMorph", code: 10,
                          userInfo: [NSLocalizedDescriptionKey:
                            "MedSAM2 mask size (\(maskBytes.count)) does not match volume (\(vol.totalVoxels))."])
        }

        await setProgress(1, "AI segmentation complete — computing morphometrics…")

        // Run Evans / callosal / volume computations using the AI mask
        let pipeline = MorphometricsPipeline()
        await pipeline.setProgressHandler { [weak self] stepIdx, message in
            guard let self else { return }
            Task { @MainActor in
                self.advanceSteps(to: stepIdx)
                self.progressDetail = message
            }
        }

        let res = try await pipeline.runWithExternalMask(
            volume: vol,
            ventMask: maskBytes,
            segmentationMethod: .medsam2
        )

        result = res
        currentAxialSlice = res.evansSlice >= 0 ? res.evansSlice : vol.dimZ / 2
        finishAllSteps()
        currentScreen = .results
    }

    // MARK: - Private: UI helpers

    private func switchToProcessing() {
        steps = pipelineSteps.enumerated().map {
            ProgressStep(id: $0.offset, label: $0.element, state: .pending)
        }
        currentStepIndex = 0
        progressDetail = "Initializing pipeline…"
        currentScreen = .processing
    }

    private func updateMetadata(_ vol: Volume, sourceLabel: String? = nil) {
        volumeShape   = "\(vol.dimX)×\(vol.dimY)×\(vol.dimZ)"
        volumeSpacing = String(format: "%.2f×%.2f×%.2f mm", vol.spacingX, vol.spacingY, vol.spacingZ)
        volumeDatatype = sourceLabel ?? "INT\(vol.bitpix)"
    }

    private func advanceSteps(to index: Int) {
        currentStepIndex = index
        for i in 0..<steps.count {
            if i < index       { steps[i].state = .done }
            else if i == index { steps[i].state = .active }
            else               { steps[i].state = .pending }
        }
    }

    private func finishAllSteps() {
        for i in 0..<steps.count { steps[i].state = .done }
    }

    private func setProgress(_ step: Int, _ message: String) async {
        advanceSteps(to: step)
        progressDetail = message
    }

    private func handleError(_ error: Error) async {
        errorMessage = error.localizedDescription
        showError = true
        currentScreen = .upload
    }
}

// MARK: - Sample data JSON model

private struct SampleDataJSON: Decodable {
    let shape: [Int]
    let spacing: [Float]
    let data_b64_gzip_int16: String
}
