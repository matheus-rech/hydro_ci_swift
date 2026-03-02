// Volume.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import Foundation

/// A 3-D voxel volume loaded from a NIfTI file, DICOM series, or image.
/// Data is stored as a flat Float32 array in column-major order:
///   index = x + y*X + z*X*Y
struct Volume {
    // MARK: - Dimensions
    let dimX: Int
    let dimY: Int
    let dimZ: Int

    // MARK: - Voxel spacing (mm per voxel)
    let spacingX: Float   // pixdim[1] / col spacing
    let spacingY: Float   // pixdim[2] / row spacing
    let spacingZ: Float   // pixdim[3] / slice thickness

    // MARK: - Raw voxel data (Hounsfield Units for CT; raw intensity for images)
    let data: [Float]

    // MARK: - Header metadata (informational; defaults provided for non-NIfTI sources)
    let datatype: Int16
    let bitpix: Int16
    let voxOffset: Int
    let sformCode: Int16

    // MARK: - Computed helpers
    var totalVoxels: Int { dimX * dimY * dimZ }
    var shape: (Int, Int, Int) { (dimX, dimY, dimZ) }
    var spacing: (Float, Float, Float) { (spacingX, spacingY, spacingZ) }

    // MARK: - Convenience initialiser for DICOM / image sources

    /// Create a Volume from a DICOM series or image without NIfTI header fields.
    /// Uses sensible defaults for metadata (FLOAT32 datatype).
    init(shape: (Int, Int, Int), spacing: (Float, Float, Float), data: [Float]) {
        self.dimX     = shape.0
        self.dimY     = shape.1
        self.dimZ     = shape.2
        self.spacingX = spacing.0
        self.spacingY = spacing.1
        self.spacingZ = spacing.2
        self.data     = data
        // Sensible defaults — not meaningful for DICOM/image sources
        self.datatype  = 16   // FLOAT32
        self.bitpix    = 32
        self.voxOffset = 0
        self.sformCode = 0
    }

    // MARK: - Safe voxel accessor

    /// Returns 0 for out-of-bounds coordinates.
    @inline(__always)
    func voxel(x: Int, y: Int, z: Int) -> Float {
        guard x >= 0, y >= 0, z >= 0,
              x < dimX, y < dimY, z < dimZ else { return 0 }
        return data[x + y * dimX + z * dimX * dimY]
    }

    /// Flat index for (x, y, z).
    @inline(__always)
    func index(x: Int, y: Int, z: Int) -> Int {
        x + y * dimX + z * dimX * dimY
    }
}
