// Volume.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import Foundation

/// A 3-D voxel volume loaded from a NIfTI file.
/// Data is stored as a flat Float32 array in NIfTI column-major order:
///   index = x + y*X + z*X*Y
struct Volume {
    // MARK: - Dimensions
    let dimX: Int
    let dimY: Int
    let dimZ: Int

    // MARK: - Voxel spacing (mm per voxel)
    let spacingX: Float   // pixdim[1]
    let spacingY: Float   // pixdim[2]
    let spacingZ: Float   // pixdim[3]

    // MARK: - Raw voxel data (Hounsfield Units for CT)
    let data: [Float]

    // MARK: - Header metadata (informational)
    let datatype: Int16
    let bitpix: Int16
    let voxOffset: Int
    let sformCode: Int16

    // MARK: - Computed helpers
    var totalVoxels: Int { dimX * dimY * dimZ }
    var shape: (Int, Int, Int) { (dimX, dimY, dimZ) }
    var spacing: (Float, Float, Float) { (spacingX, spacingY, spacingZ) }

    /// Safe inline voxel accessor — returns 0 for out-of-bounds coordinates.
    @inline(__always)
    func voxel(x: Int, y: Int, z: Int) -> Float {
        guard x >= 0, y >= 0, z >= 0,
              x < dimX, y < dimY, z < dimZ else { return 0 }
        return data[x + y * dimX + z * dimX * dimY]
    }

    /// Flat NIfTI index for (x, y, z).
    @inline(__always)
    func index(x: Int, y: Int, z: Int) -> Int {
        x + y * dimX + z * dimX * dimY
    }
}
