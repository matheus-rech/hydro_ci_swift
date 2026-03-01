// MorphologicalOps.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// 3D morphological operations (erosion, dilation, opening, closing) with 6-connectivity.
// Faithfully ported from the JavaScript reference implementation.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import Foundation

// MARK: - 6-connectivity neighbor offsets

/// Face-connected 6 neighbors in 3-D.
private let neighbors6: [(Int, Int, Int)] = [
    (-1, 0, 0), (1, 0, 0),
    (0, -1, 0), (0, 1, 0),
    (0, 0, -1), (0, 0, 1)
]

// MARK: - Public API

enum MorphologicalOps {

    // MARK: Erosion

    /// 3-D binary erosion with 6-connectivity.
    /// A voxel survives only if all 6 face-neighbors are also set.
    static func erode3D(_ mask: inout [UInt8], shape: (Int, Int, Int), iterations: Int = 1) -> [UInt8] {
        let (X, Y, Z) = shape
        let total = X * Y * Z
        var src = mask
        var dst = [UInt8](repeating: 0, count: total)

        for _ in 0..<iterations {
            for i in 0..<total { dst[i] = 0 }
            for z in 1..<(Z - 1) {
                for y in 1..<(Y - 1) {
                    for x in 1..<(X - 1) {
                        let idx = x + y * X + z * X * Y
                        guard src[idx] != 0 else { continue }
                        var keep = true
                        for (dx, dy, dz) in neighbors6 {
                            let nidx = (x + dx) + (y + dy) * X + (z + dz) * X * Y
                            if src[nidx] == 0 { keep = false; break }
                        }
                        if keep { dst[idx] = 1 }
                    }
                }
            }
            src = dst
            for i in 0..<total { dst[i] = 0 }
        }
        return src
    }

    // MARK: Dilation

    /// 3-D binary dilation with 6-connectivity.
    /// Any voxel adjacent (face-connected) to a set voxel becomes set.
    static func dilate3D(_ mask: inout [UInt8], shape: (Int, Int, Int), iterations: Int = 1) -> [UInt8] {
        let (X, Y, Z) = shape
        let total = X * Y * Z
        var src = mask
        var dst = [UInt8](repeating: 0, count: total)

        for _ in 0..<iterations {
            // Start with a copy of src
            for i in 0..<total { dst[i] = src[i] }
            for z in 1..<(Z - 1) {
                for y in 1..<(Y - 1) {
                    for x in 1..<(X - 1) {
                        let idx = x + y * X + z * X * Y
                        guard src[idx] != 0 else { continue }
                        for (dx, dy, dz) in neighbors6 {
                            let nidx = (x + dx) + (y + dy) * X + (z + dz) * X * Y
                            dst[nidx] = 1
                        }
                    }
                }
            }
            src = dst
            for i in 0..<total { dst[i] = 0 }
        }
        return src
    }

    // MARK: Opening (erode then dilate)

    /// Morphological opening = erosion followed by dilation.
    /// Removes small isolated foreground objects.
    static func opening3D(_ mask: [UInt8], shape: (Int, Int, Int), iterations: Int = 1) -> [UInt8] {
        var m = mask
        let eroded  = erode3D(&m,  shape: shape, iterations: iterations)
        var e = eroded
        return dilate3D(&e, shape: shape, iterations: iterations)
    }

    // MARK: Closing (dilate then erode)

    /// Morphological closing = dilation followed by erosion.
    /// Fills small holes in foreground objects.
    static func closing3D(_ mask: [UInt8], shape: (Int, Int, Int), iterations: Int = 1) -> [UInt8] {
        var m = mask
        let dilated = dilate3D(&m, shape: shape, iterations: iterations)
        var d = dilated
        return erode3D(&d, shape: shape, iterations: iterations)
    }
}
