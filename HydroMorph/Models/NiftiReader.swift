// NiftiReader.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// NIfTI-1 parser supporting .nii and .nii.gz files.
// Handles INT16(4), INT32(8), FLOAT32(16), FLOAT64(64), UINT8(2), UINT16(512).
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import Foundation
import Compression

// MARK: - Errors

enum NiftiError: LocalizedError {
    case invalidHeaderSize(Int32)
    case insufficientDimensions(Int16)
    case invalidDimensions(Int, Int, Int)
    case unsupportedDatatype(Int16)
    case insufficientData(expected: Int, got: Int)
    case gzipDecompressionFailed
    case readError(String)

    var errorDescription: String? {
        switch self {
        case .invalidHeaderSize(let s):
            return "Invalid NIfTI header size: \(s). Expected 348."
        case .insufficientDimensions(let n):
            return "NIfTI has only \(n) dimension(s); need at least 3."
        case .invalidDimensions(let x, let y, let z):
            return "Invalid dimensions: \(x)×\(y)×\(z)."
        case .unsupportedDatatype(let dt):
            return "Unsupported NIfTI datatype: \(dt)."
        case .insufficientData(let exp, let got):
            return "Insufficient image data: expected \(exp) bytes, got \(got)."
        case .gzipDecompressionFailed:
            return "Failed to decompress gzip data."
        case .readError(let msg):
            return "NIfTI read error: \(msg)."
        }
    }
}

// MARK: - NIfTI datatype codes

private enum NiftiType: Int16 {
    case uint8   = 2
    case int16   = 4
    case int32   = 8
    case float32 = 16
    case float64 = 64
    case uint16  = 512
}

// MARK: - NIfTI Reader

struct NiftiReader {

    /// Parse a NIfTI-1 file from Data.
    /// Automatically handles .nii (raw) and .nii.gz (gzip compressed).
    static func parse(_ inputData: Data) throws -> Volume {
        // Detect gzip magic bytes (0x1F 0x8B)
        let rawData: Data
        if inputData.count >= 2,
           inputData[inputData.startIndex] == 0x1F,
           inputData[inputData.index(after: inputData.startIndex)] == 0x8B {
            guard let decompressed = gunzip(inputData) else {
                throw NiftiError.gzipDecompressionFailed
            }
            rawData = decompressed
        } else {
            rawData = inputData
        }

        return try parseRaw(rawData)
    }

    // MARK: - Private: Parse decompressed NIfTI bytes

    private static func parseRaw(_ data: Data) throws -> Volume {
        // Read sizeof_hdr at offset 0 (Int32)
        let hdrSizeLE: Int32 = data.readInt32(at: 0, bigEndian: false)
        let littleEndian: Bool
        if hdrSizeLE == 348 {
            littleEndian = true
        } else {
            let hdrSizeBE: Int32 = data.readInt32(at: 0, bigEndian: true)
            if hdrSizeBE == 348 {
                littleEndian = false
            } else {
                throw NiftiError.invalidHeaderSize(hdrSizeLE)
            }
        }

        // dim array: Int16 × 8 starting at offset 40
        let ndim: Int16 = data.readInt16(at: 40, bigEndian: !littleEndian)
        let dimX: Int16 = data.readInt16(at: 42, bigEndian: !littleEndian)
        let dimY: Int16 = data.readInt16(at: 44, bigEndian: !littleEndian)
        let dimZ: Int16 = data.readInt16(at: 46, bigEndian: !littleEndian)

        guard ndim >= 3 else { throw NiftiError.insufficientDimensions(ndim) }
        guard dimX >= 1, dimY >= 1, dimZ >= 1 else {
            throw NiftiError.invalidDimensions(Int(dimX), Int(dimY), Int(dimZ))
        }

        // datatype: Int16 at offset 70
        let datatype: Int16 = data.readInt16(at: 70, bigEndian: !littleEndian)
        // bitpix: Int16 at offset 72
        let bitpix: Int16 = data.readInt16(at: 72, bigEndian: !littleEndian)

        // pixdim: Float32 × 8 starting at offset 76; pixdim[1..3] = spacing
        let rawSx: Float = data.readFloat32(at: 80, bigEndian: !littleEndian)
        let rawSy: Float = data.readFloat32(at: 84, bigEndian: !littleEndian)
        let rawSz: Float = data.readFloat32(at: 88, bigEndian: !littleEndian)

        let spacingX: Float = (rawSx > 0 && rawSx < 100) ? abs(rawSx) : 1.0
        let spacingY: Float = (rawSy > 0 && rawSy < 100) ? abs(rawSy) : 1.0
        let spacingZ: Float = (rawSz > 0 && rawSz < 100) ? abs(rawSz) : 1.0

        // vox_offset: Float32 at offset 108
        var voxOffset: Int = Int(data.readFloat32(at: 108, bigEndian: !littleEndian))
        if voxOffset < 348 { voxOffset = 352 }

        // sform_code: Int16 at offset 252
        let sformCode: Int16 = data.readInt16(at: 252, bigEndian: !littleEndian)

        // Extract voxel data
        let totalVoxels = Int(dimX) * Int(dimY) * Int(dimZ)
        guard data.count > voxOffset else {
            throw NiftiError.insufficientData(expected: voxOffset + totalVoxels, got: data.count)
        }
        let imageData = data.subdata(in: voxOffset..<data.count)

        let floatData = try readTypedData(
            imageData,
            datatype: datatype,
            count: totalVoxels,
            littleEndian: littleEndian
        )

        return Volume(
            dimX: Int(dimX),
            dimY: Int(dimY),
            dimZ: Int(dimZ),
            spacingX: spacingX,
            spacingY: spacingY,
            spacingZ: spacingZ,
            data: floatData,
            datatype: datatype,
            bitpix: bitpix,
            voxOffset: voxOffset,
            sformCode: sformCode
        )
    }

    // MARK: - Typed data reader

    private static func readTypedData(
        _ buffer: Data,
        datatype: Int16,
        count: Int,
        littleEndian: Bool
    ) throws -> [Float] {
        let bigEndian = !littleEndian
        switch NiftiType(rawValue: datatype) {
        case .uint8:
            return buffer.withUnsafeBytes { ptr in
                let src = ptr.bindMemory(to: UInt8.self)
                return (0..<min(count, src.count)).map { Float(src[$0]) }
            }
        case .int16:
            let bytesNeeded = count * 2
            guard buffer.count >= bytesNeeded else {
                throw NiftiError.insufficientData(expected: bytesNeeded, got: buffer.count)
            }
            return (0..<count).map { i in
                let val: Int16 = buffer.readInt16(at: i * 2, bigEndian: bigEndian)
                return Float(val)
            }
        case .int32:
            let bytesNeeded = count * 4
            guard buffer.count >= bytesNeeded else {
                throw NiftiError.insufficientData(expected: bytesNeeded, got: buffer.count)
            }
            return (0..<count).map { i in
                let val: Int32 = buffer.readInt32(at: i * 4, bigEndian: bigEndian)
                return Float(val)
            }
        case .float32:
            let bytesNeeded = count * 4
            guard buffer.count >= bytesNeeded else {
                throw NiftiError.insufficientData(expected: bytesNeeded, got: buffer.count)
            }
            return (0..<count).map { i in
                buffer.readFloat32(at: i * 4, bigEndian: bigEndian)
            }
        case .float64:
            let bytesNeeded = count * 8
            guard buffer.count >= bytesNeeded else {
                throw NiftiError.insufficientData(expected: bytesNeeded, got: buffer.count)
            }
            return (0..<count).map { i in
                Float(buffer.readFloat64(at: i * 8, bigEndian: bigEndian))
            }
        case .uint16:
            let bytesNeeded = count * 2
            guard buffer.count >= bytesNeeded else {
                throw NiftiError.insufficientData(expected: bytesNeeded, got: buffer.count)
            }
            return (0..<count).map { i in
                let val: UInt16 = buffer.readUInt16(at: i * 2, bigEndian: bigEndian)
                return Float(val)
            }
        case nil:
            throw NiftiError.unsupportedDatatype(datatype)
        }
    }

    // MARK: - Gzip decompression

    /// Strip 10-byte gzip header + optional extras, then inflate the raw DEFLATE
    /// stream using the Compression framework (COMPRESSION_ZLIB).
    static func gunzip(_ data: Data) -> Data? {
        // gzip format: 10 byte header minimum
        guard data.count > 18 else { return nil }
        guard data[data.startIndex] == 0x1F,
              data[data.index(after: data.startIndex)] == 0x8B else { return nil }

        // Parse gzip header to find start of DEFLATE payload
        var offset = 10

        // FLG byte is at index 3
        let flags = data[data.index(data.startIndex, offsetBy: 3)]
        let fextra: UInt8  = (flags >> 2) & 0x01
        let fname:  UInt8  = (flags >> 3) & 0x01
        let fcomment: UInt8 = (flags >> 4) & 0x01

        // Skip XLEN extra field
        if fextra != 0 {
            guard offset + 2 <= data.count else { return nil }
            let xlen = Int(data[data.index(data.startIndex, offsetBy: offset)]) |
                       (Int(data[data.index(data.startIndex, offsetBy: offset + 1)]) << 8)
            offset += 2 + xlen
        }
        // Skip null-terminated original filename
        if fname != 0 {
            while offset < data.count {
                if data[data.index(data.startIndex, offsetBy: offset)] == 0 {
                    offset += 1; break
                }
                offset += 1
            }
        }
        // Skip null-terminated comment
        if fcomment != 0 {
            while offset < data.count {
                if data[data.index(data.startIndex, offsetBy: offset)] == 0 {
                    offset += 1; break
                }
                offset += 1
            }
        }

        // The last 8 bytes of the gzip stream are CRC32 (4) + ISIZE (4).
        // The DEFLATE payload is everything between offset and data.count - 8.
        guard data.count > offset + 8 else { return nil }
        let deflateEnd = data.count - 8
        let deflateRange = data.index(data.startIndex, offsetBy: offset)..<data.index(data.startIndex, offsetBy: deflateEnd)
        let deflateData = data.subdata(in: deflateRange)

        // Expected uncompressed size from ISIZE (last 4 bytes, little-endian)
        let isizeOffset = data.count - 4
        let isize = Int(data[data.index(data.startIndex, offsetBy: isizeOffset)]) |
                    (Int(data[data.index(data.startIndex, offsetBy: isizeOffset + 1)]) << 8) |
                    (Int(data[data.index(data.startIndex, offsetBy: isizeOffset + 2)]) << 16) |
                    (Int(data[data.index(data.startIndex, offsetBy: isizeOffset + 3)]) << 24)

        // Allocate output buffer. If isize is 0 or unreliable, use a large estimate.
        let bufferSize = isize > 0 ? isize + 64 : deflateData.count * 8
        var outputData = Data(count: bufferSize)

        let result: Int = deflateData.withUnsafeBytes { srcPtr in
            outputData.withUnsafeMutableBytes { dstPtr in
                compression_decode_buffer(
                    dstPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    bufferSize,
                    srcPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    deflateData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard result > 0 else { return nil }
        outputData.count = result
        return outputData
    }
}

// MARK: - Data reading extensions

private extension Data {

    func readInt16(at offset: Int, bigEndian: Bool) -> Int16 {
        var value: Int16 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { valuePtr in
            self.copyBytes(to: valuePtr, from: (startIndex + offset)..<(startIndex + offset + 2))
        }
        return bigEndian ? Int16(bigEndian: value) : Int16(littleEndian: value)
    }

    func readUInt16(at offset: Int, bigEndian: Bool) -> UInt16 {
        var value: UInt16 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { valuePtr in
            self.copyBytes(to: valuePtr, from: (startIndex + offset)..<(startIndex + offset + 2))
        }
        return bigEndian ? UInt16(bigEndian: value) : UInt16(littleEndian: value)
    }

    func readInt32(at offset: Int, bigEndian: Bool) -> Int32 {
        var value: Int32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { valuePtr in
            self.copyBytes(to: valuePtr, from: (startIndex + offset)..<(startIndex + offset + 4))
        }
        return bigEndian ? Int32(bigEndian: value) : Int32(littleEndian: value)
    }

    func readFloat32(at offset: Int, bigEndian: Bool) -> Float {
        var value: UInt32 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { valuePtr in
            self.copyBytes(to: valuePtr, from: (startIndex + offset)..<(startIndex + offset + 4))
        }
        let bits = bigEndian ? UInt32(bigEndian: value) : UInt32(littleEndian: value)
        return Float(bitPattern: bits)
    }

    func readFloat64(at offset: Int, bigEndian: Bool) -> Double {
        var value: UInt64 = 0
        _ = Swift.withUnsafeMutableBytes(of: &value) { valuePtr in
            self.copyBytes(to: valuePtr, from: (startIndex + offset)..<(startIndex + offset + 8))
        }
        let bits = bigEndian ? UInt64(bigEndian: value) : UInt64(littleEndian: value)
        return Double(bitPattern: bits)
    }
}
