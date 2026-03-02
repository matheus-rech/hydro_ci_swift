// DicomReader.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Pure Swift DICOM parser (no external dependencies).
// Supports explicit VR and implicit VR, 8/16/32-bit pixel data,
// signed/unsigned, single-file or multi-file (DICOM series).
// Also supports loading PNG/JPEG images as single-slice pseudo-volumes.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import Foundation
import UIKit

// MARK: - DicomSlice

struct DicomSlice {
    let pixelData: [Float]
    let rows: Int
    let cols: Int
    let sliceLocation: Double
    let instanceNumber: Int
    let rescaleSlope: Double
    let rescaleIntercept: Double
    let pixelSpacing: (Double, Double)  // (row, col)
    let sliceThickness: Double
}

// MARK: - DicomReader

enum DicomReader {

    // MARK: - Parse single DICOM file

    /// Parse a single DICOM file from Data.
    /// Handles both Explicit VR and Implicit VR transfer syntaxes.
    static func parseFile(_ data: Data) throws -> DicomSlice {
        // Verify DICM magic at offset 128
        guard data.count > 132 else { throw DicomError.fileTooShort }
        let magic = data.readString(at: 128, length: 4)
        guard magic == "DICM" else { throw DicomError.notDicom }

        // Parse data elements starting at offset 132
        var offset = 132
        var rows: Int = 0
        var cols: Int = 0
        var bitsAllocated: Int = 16
        var pixelRepresentation: Int = 0
        var rescaleSlope: Double = 1.0
        var rescaleIntercept: Double = 0.0
        var sliceLocation: Double = 0.0
        var instanceNumber: Int = 0
        var pixelSpacingRow: Double = 1.0
        var pixelSpacingCol: Double = 1.0
        var sliceThickness: Double = 1.0
        var pixelDataOffset: Int = 0
        var pixelDataLength: Int = 0

        // Detect transfer syntax by checking if bytes 4–5 look like ASCII VR codes.
        // A two-letter ASCII VR will have both bytes in [0x41..0x5A] (A–Z).
        let isExplicitVR = isExplicitVRAtOffset(data, offset: offset)

        while offset < data.count - 8 {
            guard offset + 4 <= data.count else { break }
            let group   = data.readUInt16LE(at: offset)
            let element = data.readUInt16LE(at: offset + 2)
            let tag = (group, element)

            var valueLength: Int
            var valueOffset: Int

            if isExplicitVR {
                // Explicit VR: bytes [4,5] = VR string
                guard offset + 6 <= data.count else { break }
                let vr = data.readString(at: offset + 4, length: 2)

                if ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"].contains(vr) {
                    // 2 reserved bytes + 4-byte length at [offset+8]
                    guard offset + 12 <= data.count else { break }
                    valueLength = Int(data.readUInt32LE(at: offset + 8))
                    valueOffset = offset + 12
                } else {
                    // 2-byte length at [offset+6]
                    guard offset + 8 <= data.count else { break }
                    valueLength = Int(data.readUInt16LE(at: offset + 6))
                    valueOffset = offset + 8
                }
            } else {
                // Implicit VR: 4-byte length at [offset+4]
                guard offset + 8 <= data.count else { break }
                valueLength = Int(data.readUInt32LE(at: offset + 4))
                valueOffset = offset + 8
            }

            // Handle undefined length (0xFFFFFFFF)
            if valueLength == Int(bitPattern: UInt(0xFFFFFFFF)) {
                if tag == (0x7FE0, 0x0010) {
                    // Pixel data with undefined length: use rest of file (skip item tags)
                    pixelDataOffset = valueOffset + 8  // skip Basic Offset Table item
                    pixelDataLength = data.count - pixelDataOffset
                }
                break
            }

            // Guard against corrupt length values
            guard valueLength >= 0, valueOffset + valueLength <= data.count else { break }

            // Extract values for known tags
            switch tag {
            case (0x0028, 0x0010):
                rows = Int(data.readUInt16LE(at: valueOffset))
            case (0x0028, 0x0011):
                cols = Int(data.readUInt16LE(at: valueOffset))
            case (0x0028, 0x0100):
                bitsAllocated = Int(data.readUInt16LE(at: valueOffset))
            case (0x0028, 0x0103):
                pixelRepresentation = Int(data.readUInt16LE(at: valueOffset))
            case (0x0028, 0x1053):
                rescaleSlope = Double(data.readString(at: valueOffset, length: valueLength)) ?? 1.0
            case (0x0028, 0x1052):
                rescaleIntercept = Double(data.readString(at: valueOffset, length: valueLength)) ?? 0.0
            case (0x0020, 0x1041):
                sliceLocation = Double(data.readString(at: valueOffset, length: valueLength)) ?? 0.0
            case (0x0020, 0x0013):
                instanceNumber = Int(data.readString(at: valueOffset, length: valueLength)) ?? 0
            case (0x0028, 0x0030):
                let ps = data.readString(at: valueOffset, length: valueLength).split(separator: "\\")
                if ps.count >= 2 {
                    pixelSpacingRow = Double(ps[0]) ?? 1.0
                    pixelSpacingCol = Double(ps[1]) ?? 1.0
                }
            case (0x0018, 0x0050):
                sliceThickness = Double(data.readString(at: valueOffset, length: valueLength)) ?? 1.0
            case (0x7FE0, 0x0010):
                pixelDataOffset = valueOffset
                pixelDataLength = valueLength
            default:
                break
            }

            // Advance; align to even byte boundary
            var nextOffset = valueOffset + valueLength
            if nextOffset % 2 != 0 { nextOffset += 1 }
            if nextOffset <= offset { break }  // safety: avoid infinite loop
            offset = nextOffset
        }

        guard rows > 0, cols > 0, pixelDataOffset > 0 else {
            throw DicomError.missingRequiredTags
        }

        // Read pixel data into Float array
        let totalPixels = rows * cols
        var pixelData = [Float](repeating: 0, count: totalPixels)
        let bytesPerPixel = max(1, bitsAllocated / 8)

        for i in 0..<totalPixels {
            let byteOffset = pixelDataOffset + i * bytesPerPixel
            guard byteOffset + bytesPerPixel <= data.count else { break }

            let rawValue: Double
            switch bitsAllocated {
            case 8:
                rawValue = Double(data[byteOffset])
            case 32:
                if pixelRepresentation == 1 {
                    rawValue = Double(data.readInt32LE(at: byteOffset))
                } else {
                    rawValue = Double(data.readUInt32LE(at: byteOffset))
                }
            default:  // 16-bit (most common)
                if pixelRepresentation == 1 {
                    rawValue = Double(data.readInt16LE(at: byteOffset))
                } else {
                    rawValue = Double(data.readUInt16LE(at: byteOffset))
                }
            }

            pixelData[i] = Float(rawValue * rescaleSlope + rescaleIntercept)
        }

        return DicomSlice(
            pixelData: pixelData, rows: rows, cols: cols,
            sliceLocation: sliceLocation, instanceNumber: instanceNumber,
            rescaleSlope: rescaleSlope, rescaleIntercept: rescaleIntercept,
            pixelSpacing: (pixelSpacingRow, pixelSpacingCol),
            sliceThickness: sliceThickness
        )
    }

    // MARK: - Parse DICOM series

    /// Parse multiple DICOM files and assemble them into a 3-D Volume.
    /// Slices are sorted by sliceLocation; falls back to instanceNumber ordering.
    static func parseSeries(_ dataFiles: [Data]) throws -> Volume {
        var slices = [DicomSlice]()
        for fileData in dataFiles {
            if let slice = try? parseFile(fileData) {
                slices.append(slice)
            }
        }
        guard !slices.isEmpty else { throw DicomError.noSlices }

        // Sort: prefer sliceLocation; fall back to instanceNumber
        let hasLocation = slices.allSatisfy { $0.sliceLocation != 0 }
        let sorted = hasLocation
            ? slices.sorted { $0.sliceLocation < $1.sliceLocation }
            : slices.sorted { $0.instanceNumber < $1.instanceNumber }

        guard let first = sorted.first else { throw DicomError.noSlices }

        let X = first.cols
        let Y = first.rows
        let Z = sorted.count
        let spacingX = Float(first.pixelSpacing.1)   // col spacing = X
        let spacingY = Float(first.pixelSpacing.0)   // row spacing = Y
        var spacingZ = Float(first.sliceThickness)

        // Derive Z spacing from consecutive slice locations when available
        if sorted.count > 1 && hasLocation {
            let dz = abs(Float(sorted[1].sliceLocation - sorted[0].sliceLocation))
            if dz > 0.01 { spacingZ = dz }
        }

        var volumeData = [Float](repeating: 0, count: X * Y * Z)
        for z in 0..<Z {
            let slice = sorted[z]
            // Guard against dimension mismatch across slices
            guard slice.cols == X, slice.rows == Y else { continue }
            for y in 0..<Y {
                for x in 0..<X {
                    volumeData[x + y * X + z * X * Y] = slice.pixelData[y * X + x]
                }
            }
        }

        return Volume(
            shape: (X, Y, Z),
            spacing: (spacingX, spacingY, spacingZ),
            data: volumeData
        )
    }

    // MARK: - Parse single image (PNG / JPEG)

    /// Load a PNG or JPEG image and create a single-slice pseudo-volume.
    /// Pixel values are rendered as grayscale (0–255) — suitable for testing.
    static func parseImage(_ data: Data) throws -> Volume {
        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            throw DicomError.invalidImage
        }

        let width  = cgImage.width
        let height = cgImage.height

        // Render to 8-bit grayscale context
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw DicomError.invalidImage
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let volumeData = pixels.map { Float($0) }

        return Volume(
            shape: (width, height, 1),
            spacing: (1.0, 1.0, 1.0),
            data: volumeData
        )
    }

    // MARK: - Helpers

    /// Heuristic: check if the first data element at `offset` uses explicit VR.
    /// In explicit VR, bytes [offset+4] and [offset+5] are printable ASCII A–Z letters.
    private static func isExplicitVRAtOffset(_ data: Data, offset: Int) -> Bool {
        guard offset + 6 <= data.count else { return true }
        let b4 = data[offset + 4]
        let b5 = data[offset + 5]
        let isUpperAlpha = { (b: UInt8) -> Bool in b >= 0x41 && b <= 0x5A }
        return isUpperAlpha(b4) && isUpperAlpha(b5)
    }

    // MARK: - Error types

    enum DicomError: LocalizedError {
        case fileTooShort
        case notDicom
        case missingRequiredTags
        case noSlices
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .fileTooShort:
                return "File is too short to be a valid DICOM file."
            case .notDicom:
                return "File is not in DICOM format (missing DICM magic bytes at offset 128)."
            case .missingRequiredTags:
                return "DICOM file is missing required tags (rows, columns, or pixel data)."
            case .noSlices:
                return "No valid DICOM slices could be parsed from the selected files."
            case .invalidImage:
                return "Failed to load image file. Ensure it is a valid PNG or JPEG."
            }
        }
    }
}

// MARK: - Data extension helpers (public for MedSAMClient)

extension Data {

    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: UInt16.self).littleEndian
        }
    }

    func readInt16LE(at offset: Int) -> Int16 {
        guard offset + 2 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: Int16.self).littleEndian
        }
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: UInt32.self).littleEndian
        }
    }

    func readInt32LE(at offset: Int) -> Int32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: offset, as: Int32.self).littleEndian
        }
    }

    func readString(at offset: Int, length: Int) -> String {
        guard offset >= 0, length > 0, offset + length <= count else { return "" }
        return String(data: self[offset..<(offset + length)], encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
