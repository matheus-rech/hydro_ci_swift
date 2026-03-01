// PipelineViewModel.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// ObservableObject managing pipeline state, progress, and results.
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

    // MARK: - Load NIfTI file from URL

    func loadFile(url: URL) {
        processingFileName = url.lastPathComponent
        switchToProcessing()

        Task {
            do {
                // Read file data (may be on a security-scoped resource)
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }

                let fileData = try Data(contentsOf: url)
                let fileSizeMB = String(format: "%.1f MB", Double(fileData.count) / (1024 * 1024))
                await MainActor.run { self.volumeFileSize = fileSizeMB }

                // Parse NIfTI
                await setProgress(0, "Decompressing & parsing NIfTI…")
                let vol = try NiftiReader.parse(fileData)
                await MainActor.run {
                    self.volume = vol
                    self.updateMetadata(vol)
                }

                // Run pipeline
                try await runPipeline(vol)

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

                // Decode: base64 → gzip → Int16 → Float32
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

                await MainActor.run {
                    self.volume = vol
                    self.volumeFileSize = String(format: "%.1f MB", Double(compressed.count) / (1024 * 1024))
                    self.updateMetadata(vol)
                }

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
    }

    // MARK: - Private: pipeline runner

    private func runPipeline(_ vol: Volume) async throws {
        let pipeline = MorphometricsPipeline()
        await pipeline.setProgressHandler { [weak self] stepIdx, message in
            guard let self else { return }
            Task { @MainActor in
                self.advanceSteps(to: stepIdx)
                self.progressDetail = message
            }
        }

        let res = try await pipeline.run(volume: vol)

        await MainActor.run {
            self.result = res
            self.currentAxialSlice = res.evansSlice >= 0 ? res.evansSlice : vol.dimZ / 2
            self.finishAllSteps()
            self.currentScreen = .results
        }
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

    private func updateMetadata(_ vol: Volume) {
        volumeShape = "\(vol.dimX)×\(vol.dimY)×\(vol.dimZ)"
        volumeSpacing = String(format: "%.2f×%.2f×%.2f mm", vol.spacingX, vol.spacingY, vol.spacingZ)
        volumeDatatype = "INT\(vol.bitpix)"
    }

    private func advanceSteps(to index: Int) {
        currentStepIndex = index
        for i in 0..<steps.count {
            if i < index      { steps[i].state = .done }
            else if i == index { steps[i].state = .active }
            else               { steps[i].state = .pending }
        }
    }

    private func finishAllSteps() {
        for i in 0..<steps.count { steps[i].state = .done }
    }

    private func setProgress(_ step: Int, _ message: String) async {
        await MainActor.run {
            self.advanceSteps(to: step)
            self.progressDetail = message
        }
    }

    private func handleError(_ error: Error) async {
        await MainActor.run {
            self.errorMessage = error.localizedDescription
            self.showError = true
            self.currentScreen = .upload
        }
    }
}

// MARK: - Sample data JSON model

private struct SampleDataJSON: Decodable {
    let shape: [Int]
    let spacing: [Float]
    let data_b64_gzip_int16: String
}
