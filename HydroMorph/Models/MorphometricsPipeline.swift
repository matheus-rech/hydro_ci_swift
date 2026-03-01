// MorphometricsPipeline.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Full on-device processing pipeline: brain mask → CSF → morphological ops →
// central crop → connected components → Evans Index → Callosal Angle → Volume → NPH score.
// Faithfully ported from app.js (1150 lines).
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import Foundation

// MARK: - Pipeline step names

let pipelineSteps: [String] = [
    "Parsing NIfTI header",
    "Building brain mask",
    "Extracting CSF voxels",
    "Morphological filtering",
    "Isolating ventricles",
    "Computing Evans Index",
    "Computing callosal angle",
    "Computing volume",
    "Generating report"
]

// MARK: - Pipeline errors

enum PipelineError: LocalizedError {
    case tooFewVentricleVoxels(Int)
    case noBrainTissueFound

    var errorDescription: String? {
        switch self {
        case .tooFewVentricleVoxels(let n):
            return "Very few ventricle voxels found (\(n)). Is this a head CT with HU values? Check that your file is a CT scan in Hounsfield Units."
        case .noBrainTissueFound:
            return "No brain tissue found. Verify this is a valid head CT scan."
        }
    }
}

// MARK: - Pipeline

actor MorphometricsPipeline {

    // Progress callback: (stepIndex: Int, message: String) → void
    typealias ProgressHandler = @Sendable (Int, String) -> Void

    private var onProgress: ProgressHandler?

    func setProgressHandler(_ handler: @escaping ProgressHandler) {
        onProgress = handler
    }

    // MARK: - Run

    func run(volume: Volume) async throws -> PipelineResult {
        let X = volume.dimX, Y = volume.dimY, Z = volume.dimZ
        let total = X * Y * Z
        let data = volume.data

        // ── Step 0: Header already parsed ────────────────────────────────────
        report(0, "Volume: \(X)×\(Y)×\(Z), spacing: \(String(format:"%.2f", volume.spacingX))×\(String(format:"%.2f", volume.spacingY))×\(String(format:"%.2f", volume.spacingZ)) mm")

        // ── Step 1: Brain mask ────────────────────────────────────────────────
        // Threshold HU [-5, 80]
        report(1, "Thresholding brain tissue (HU: -5 to 80)...")
        var brainMaskRaw = [UInt8](repeating: 0, count: total)
        for i in 0..<total {
            let hu = data[i]
            brainMaskRaw[i] = (hu >= -5 && hu <= 80) ? 1 : 0
        }

        // Closing to fill small gaps (2 iterations)
        report(1, "Closing brain mask...")
        var brainMask = MorphologicalOps.closing3D(brainMaskRaw,
                                                    shape: (X, Y, Z),
                                                    iterations: 2)

        // Keep largest component (min 1000 voxels)
        report(1, "Keeping largest brain component...")
        brainMask = ConnectedComponents.keepLargest(brainMask,
                                                     shape: (X, Y, Z),
                                                     minSize: 1000)

        let brainVoxCount = brainMask.reduce(0) { $0 + Int($1) }
        report(1, "Brain mask: \(brainVoxCount) voxels")

        guard brainVoxCount > 0 else { throw PipelineError.noBrainTissueFound }

        // ── Step 2: CSF mask ──────────────────────────────────────────────────
        // Within brain mask, HU [0, 22]
        report(2, "Extracting CSF (HU: 0 to 22) within brain...")
        var csfMask = [UInt8](repeating: 0, count: total)
        for i in 0..<total {
            let hu = data[i]
            csfMask[i] = (brainMask[i] == 1 && hu >= 0 && hu <= 22) ? 1 : 0
        }
        let csfCount = csfMask.reduce(0) { $0 + Int($1) }
        report(2, "CSF voxels: \(csfCount)")

        // ── Step 3: Morphological opening (adaptive) ──────────────────────────
        report(3, "Applying morphological filtering...")
        let minSpacingXY = min(Double(volume.spacingX), Double(volume.spacingY))
        var ventMask: [UInt8]
        if minSpacingXY < 0.7 || minSpacingXY > 2.5 {
            report(3, "Adaptive filtering — skipping erosion for this resolution...")
            ventMask = csfMask
        } else {
            ventMask = MorphologicalOps.opening3D(csfMask, shape: (X, Y, Z), iterations: 1)
        }

        // ── Step 4a: Central crop ─────────────────────────────────────────────
        report(4, "Restricting to central brain region (ventricles are central)...")

        // Compute brain bounding box
        var bxMin = X, bxMax = 0, byMin = Y, byMax = 0, bzMin = Z, bzMax = 0
        for z in 0..<Z {
            for y in 0..<Y {
                for x in 0..<X {
                    let idx = x + y * X + z * X * Y
                    if brainMask[idx] == 1 {
                        if x < bxMin { bxMin = x }; if x > bxMax { bxMax = x }
                        if y < byMin { byMin = y }; if y > byMax { byMax = y }
                        if z < bzMin { bzMin = z }; if z > bzMax { bzMax = z }
                    }
                }
            }
        }

        // Trim 20% X margins, 20% Y margins, 10% Z margins
        let marginX = Int(Double(bxMax - bxMin) * 0.20)
        let marginY = Int(Double(byMax - byMin) * 0.20)
        let marginZ = Int(Double(bzMax - bzMin) * 0.10)

        let cropXmin = bxMin + marginX, cropXmax = bxMax - marginX
        let cropYmin = byMin + marginY, cropYmax = byMax - marginY
        let cropZmin = bzMin + marginZ, cropZmax = bzMax - marginZ

        for z in 0..<Z {
            for y in 0..<Y {
                for x in 0..<X {
                    let idx = x + y * X + z * X * Y
                    guard ventMask[idx] != 0 else { continue }
                    if x < cropXmin || x > cropXmax ||
                       y < cropYmin || y > cropYmax ||
                       z < cropZmin || z > cropZmax {
                        ventMask[idx] = 0
                    }
                }
            }
        }

        // ── Step 4b: Keep large components (adaptive threshold) ───────────────
        let voxVol = Double(volume.spacingX) * Double(volume.spacingY) * Double(volume.spacingZ)
        // Adaptive threshold: ~0.5 mL equivalent in voxels (scales down for larger voxels).
        // Matches JS: max(50, Math.round((0.5 * 1000) / voxVol))
        let minComponentSize = max(50, Int((500.0 / voxVol).rounded()))
        report(4, "Filtering connected components (>\(minComponentSize) voxels)...")
        ventMask = ConnectedComponents.keepLarge(ventMask, shape: (X, Y, Z), minSize: minComponentSize)

        let ventCount = ventMask.reduce(0) { $0 + Int($1) }
        report(4, "Ventricle voxels: \(ventCount)")

        guard ventCount >= 100 else {
            throw PipelineError.tooFewVentricleVoxels(ventCount)
        }

        // ── Step 5: Evans Index ───────────────────────────────────────────────
        report(5, "Computing Evans Index per axial slice...")
        let evansResult = computeEvansIndex(data: data, ventMask: ventMask, volume: volume)

        // ── Step 6: Callosal Angle ────────────────────────────────────────────
        report(6, "Computing callosal angle on coronal view...")
        let callosalResult = computeCallosalAngle(ventMask: ventMask, volume: volume)

        // ── Step 7: Volume ────────────────────────────────────────────────────
        report(7, "Computing ventricle volume...")
        let ventVolMm3 = Double(ventCount) * voxVol
        let ventVolMl = ventVolMm3 / 1000.0

        // ── Step 8: NPH Probability ───────────────────────────────────────────
        report(8, "Generating clinical report...")
        var nphScore = 0
        if evansResult.maxEvans > 0.3 { nphScore += 1 }
        if let angle = callosalResult.angleDeg, angle < 90 { nphScore += 1 }
        if ventVolMl > 50 { nphScore += 1 }
        let nphPct = Int((Double(nphScore) / 3.0 * 100).rounded())

        let initialSlice = evansResult.bestSlice >= 0 ? evansResult.bestSlice : Z / 2

        return PipelineResult(
            evansIndex: evansResult.maxEvans,
            evansSlice: evansResult.bestSlice >= 0 ? evansResult.bestSlice : initialSlice,
            evansData: evansResult,
            callosalAngle: callosalResult.angleDeg,
            callosalSlice: callosalResult.bestCoronalSlice,
            callosalData: callosalResult,
            ventVolMl: ventVolMl,
            ventVolMm3: ventVolMm3,
            nphScore: nphScore,
            nphPct: nphPct,
            ventCount: ventCount,
            brainVoxCount: brainVoxCount,
            shape: (X, Y, Z),
            spacing: (volume.spacingX, volume.spacingY, volume.spacingZ),
            ventMask: ventMask
        )
    }

    // MARK: - Evans Index

    private func computeEvansIndex(data: [Float], ventMask: [UInt8], volume: Volume) -> EvansResult {
        let X = volume.dimX, Y = volume.dimY, Z = volume.dimZ
        var maxEvans: Double = 0
        var bestSlice = -1
        var perSlice: [EvansSliceData] = []

        for z in 0..<Z {
            var ventLeft = X, ventRight = 0
            var ventCount = 0

            for y in 0..<Y {
                for x in 0..<X {
                    let idx = x + y * X + z * X * Y
                    if ventMask[idx] == 1 {
                        ventCount += 1
                        if x < ventLeft  { ventLeft  = x }
                        if x > ventRight { ventRight = x }
                    }
                }
            }
            guard ventCount >= 20 else { continue }

            let ventWidthMm = Double(ventRight - ventLeft) * Double(volume.spacingX)

            // Find skull width: prefer bone HU > 300
            var skullLeft = X, skullRight = 0, boneCount = 0
            for y in 0..<Y {
                for x in 0..<X {
                    let hu = data[x + y * X + z * X * Y]
                    if hu > 300 {
                        boneCount += 1
                        if x < skullLeft  { skullLeft  = x }
                        if x > skullRight { skullRight = x }
                    }
                }
            }

            // Fallback: soft tissue extent (HU -20 … 1000)
            if boneCount < 10 || (skullRight - skullLeft) < 50 {
                skullLeft = X; skullRight = 0
                for y in 0..<Y {
                    for x in 0..<X {
                        let hu = data[x + y * X + z * X * Y]
                        if hu > -20 && hu < 1000 {
                            if x < skullLeft  { skullLeft  = x }
                            if x > skullRight { skullRight = x }
                        }
                    }
                }
            }

            guard skullRight > skullLeft else { continue }
            let skullWidthMm = Double(skullRight - skullLeft) * Double(volume.spacingX)
            guard skullWidthMm >= 50 else { continue }

            let evans = ventWidthMm / skullWidthMm
            perSlice.append(EvansSliceData(
                z: z, evans: evans,
                ventWidthMm: ventWidthMm, skullWidthMm: skullWidthMm,
                ventLeft: ventLeft, ventRight: ventRight,
                skullLeft: skullLeft, skullRight: skullRight
            ))

            if evans > maxEvans { maxEvans = evans; bestSlice = z }
        }

        return EvansResult(maxEvans: maxEvans, bestSlice: bestSlice, perSlice: perSlice)
    }

    // MARK: - Callosal Angle

    private func computeCallosalAngle(ventMask: [UInt8], volume: Volume) -> CallosalResult {
        let X = volume.dimX, Y = volume.dimY, Z = volume.dimZ

        // Find coronal slice (Y axis) with most ventricle voxels
        var maxCount = 0, bestY = -1
        for y in 0..<Y {
            var count = 0
            for z in 0..<Z {
                for x in 0..<X {
                    if ventMask[x + y * X + z * X * Y] == 1 { count += 1 }
                }
            }
            if count > maxCount { maxCount = count; bestY = y }
        }

        guard bestY >= 0, maxCount >= 20 else {
            return CallosalResult(angleDeg: nil, bestCoronalSlice: -1,
                                   vertex: nil, leftPt: nil, rightPt: nil, midX: X / 2)
        }

        let midX = X / 2
        var topZ = 0

        // Find topmost z (= highest Z index = superior in axial ordering)
        for z in 0..<Z {
            for x in 0..<X {
                if ventMask[x + bestY * X + z * X * Y] == 1 {
                    if z > topZ { topZ = z }
                }
            }
        }

        // Vertex = centroid of top 3 z-layers
        var vertexSumX: Double = 0, vertexSumZ: Double = 0, vertexN = 0
        let topZThresh = topZ - 3
        for z in max(0, topZThresh)...topZ {
            for x in 0..<X {
                if ventMask[x + bestY * X + z * X * Y] == 1 {
                    vertexSumX += Double(x); vertexSumZ += Double(z); vertexN += 1
                }
            }
        }
        guard vertexN > 0 else {
            return CallosalResult(angleDeg: nil, bestCoronalSlice: bestY,
                                   vertex: nil, leftPt: nil, rightPt: nil, midX: midX)
        }
        let vx = vertexSumX / Double(vertexN)
        let vz = vertexSumZ / Double(vertexN)

        // Left and right bottom-most extremes on each half
        var bLeftX = -1, bLeftZ = Z
        var bRightX = -1, bRightZ = Z
        for z in 0..<Z {
            for x in 0..<X {
                if ventMask[x + bestY * X + z * X * Y] == 1 {
                    if x < midX && z < bLeftZ  { bLeftZ = z;  bLeftX  = x }
                    if x >= midX && z < bRightZ { bRightZ = z; bRightX = x }
                }
            }
        }

        guard bLeftX >= 0, bRightX >= 0 else {
            return CallosalResult(angleDeg: nil, bestCoronalSlice: bestY,
                                   vertex: CallosalPoint(x: vx, z: vz),
                                   leftPt: nil, rightPt: nil, midX: midX)
        }

        // Vectors from vertex to bottom-left and bottom-right (mm space)
        let lx = (Double(bLeftX)  - vx) * Double(volume.spacingX)
        let lz = (Double(bLeftZ)  - vz) * Double(volume.spacingZ)
        let rx = (Double(bRightX) - vx) * Double(volume.spacingX)
        let rz = (Double(bRightZ) - vz) * Double(volume.spacingZ)

        let dotProd = lx * rx + lz * rz
        let magL = sqrt(lx * lx + lz * lz)
        let magR = sqrt(rx * rx + rz * rz)

        guard magL > 0.001, magR > 0.001 else {
            return CallosalResult(angleDeg: nil, bestCoronalSlice: bestY,
                                   vertex: CallosalPoint(x: vx, z: vz),
                                   leftPt: nil, rightPt: nil, midX: midX)
        }

        let cosAngle = max(-1, min(1, dotProd / (magL * magR)))
        let angleDeg = Double(Int((acos(cosAngle) * (180.0 / .pi)).rounded()))

        return CallosalResult(
            angleDeg: angleDeg,
            bestCoronalSlice: bestY,
            vertex: CallosalPoint(x: vx, z: vz),
            leftPt:  CallosalPoint(x: Double(bLeftX),  z: Double(bLeftZ)),
            rightPt: CallosalPoint(x: Double(bRightX), z: Double(bRightZ)),
            midX: midX
        )
    }

    // MARK: - Helpers

    private func report(_ step: Int, _ message: String) {
        onProgress?(step, message)
    }
}
