// PipelineResult.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import Foundation

// MARK: - Segmentation method

/// Indicates which pipeline was used to produce the ventricle mask.
enum SegmentationMethod: String {
    /// Classical HU-threshold + morphological pipeline (fully on-device).
    case threshold = "threshold"
    /// AI-powered segmentation via MedSAM2 backend server.
    case medsam2 = "medsam2"

    var displayName: String {
        switch self {
        case .threshold: return "On-Device Threshold"
        case .medsam2:   return "MedSAM2 AI"
        }
    }
}

// MARK: - Per-slice Evans data

struct EvansSliceData {
    let z: Int
    let evans: Double
    let ventWidthMm: Double
    let skullWidthMm: Double
    let ventLeft: Int
    let ventRight: Int
    let skullLeft: Int
    let skullRight: Int
}

struct EvansResult {
    let maxEvans: Double
    let bestSlice: Int          // axial z-index of max evans
    let perSlice: [EvansSliceData]
}

// MARK: - Callosal angle result

struct CallosalPoint {
    let x: Double   // in voxel coordinates
    let z: Double
}

struct CallosalResult {
    let angleDeg: Double?          // nil if undetermined
    let bestCoronalSlice: Int      // y-index with most ventricle voxels
    let vertex: CallosalPoint?
    let leftPt: CallosalPoint?
    let rightPt: CallosalPoint?
    let midX: Int
}

// MARK: - NPH Probability levels

enum NPHLevel: String {
    case low = "LOW"
    case moderate = "MODERATE"
    case high = "HIGH"

    var color: String {
        switch self {
        case .low:      return "nphLow"
        case .moderate: return "nphModerate"
        case .high:     return "nphHigh"
        }
    }
}

// MARK: - Main pipeline result

struct PipelineResult {
    // Core morphometrics
    let evansIndex: Double
    let evansSlice: Int
    let evansData: EvansResult

    let callosalAngle: Double?
    let callosalSlice: Int
    let callosalData: CallosalResult

    let ventVolMl: Double
    let ventVolMm3: Double

    // NPH probability
    let nphScore: Int       // 0–3
    let nphPct: Int         // 0–100
    var nphLevel: NPHLevel {
        if nphScore >= 2 { return .high }
        if nphScore == 1 { return .moderate }
        return .low
    }

    // Diagnostics
    let ventCount: Int
    let brainVoxCount: Int
    let shape: (Int, Int, Int)
    let spacing: (Float, Float, Float)

    // Ventricle mask (flattened, x+y*X+z*X*Y order)
    let ventMask: [UInt8]

    // Segmentation method used for this result
    let segmentationMethod: SegmentationMethod

    // Sanity warnings
    var sanityWarnings: [String] {
        var warnings: [String] = []
        if evansIndex > 0.7 {
            warnings.append("Evans Index \(String(format:"%.3f", evansIndex)) is very high (>0.7). Please verify segmentation.")
        }
        if evansIndex < 0.1 {
            warnings.append("Evans Index \(String(format:"%.3f", evansIndex)) is very low. Verify ventricles were detected.")
        }
        if let angle = callosalAngle, angle > 160 {
            warnings.append("Callosal angle \(Int(angle))° seems very wide. Verify coronal segmentation.")
        }
        if ventVolMl < 5 {
            warnings.append("Ventricle volume \(String(format:"%.1f", ventVolMl)) mL seems very low. Check segmentation.")
        }
        if ventVolMl > 200 {
            warnings.append("Ventricle volume \(String(format:"%.1f", ventVolMl)) mL seems very high. Verify segmentation.")
        }
        let (sx, sy, sz) = spacing
        if sx > 5 || sy > 5 || sz > 5 {
            warnings.append("Large voxel spacing detected (\(String(format:"%.1f", sx))×\(String(format:"%.1f", sy))×\(String(format:"%.1f", sz)) mm). Results may be less accurate.")
        }
        return warnings
    }
}
