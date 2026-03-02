// MedSAMClient.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Swift actor wrapping the MedSAM2 segmentation REST API.
// Sends a gzip-compressed volume and bounding box; receives a binary mask.
// Zero external dependencies — uses only Compression framework for gzip.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import Foundation
import Compression

// MARK: - BoundingBox

/// 2-D bounding box on a single axial slice for MedSAM2 prompting.
struct BoundingBox: Codable {
    let x1: Int
    let y1: Int
    let x2: Int
    let y2: Int
    /// Zero-based axial slice index this box applies to.
    let sliceIdx: Int

    func toJSON() -> String {
        "{\"x1\":\(x1),\"y1\":\(y1),\"x2\":\(x2),\"y2\":\(y2),\"slice_idx\":\(sliceIdx)}"
    }
}

// MARK: - MedSAMClient

/// Actor that communicates with a running MedSAM2 Flask server.
/// All methods are async and safe to call from any Swift concurrency context.
actor MedSAMClient {

    // MARK: Shared singleton

    static let shared = MedSAMClient()

    // MARK: State

    private var serverUrl: String = "http://localhost:5000"

    func setServerUrl(_ url: String) {
        serverUrl = url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    func getServerUrl() -> String { serverUrl }

    // MARK: - Health check

    struct HealthResponse: Codable {
        let status: String
        let model: String?
        let device: String?
    }

    /// Returns `(true, info)` when the server is reachable and healthy.
    func checkHealth() async -> (available: Bool, info: HealthResponse?) {
        guard let url = URL(string: "\(serverUrl)/api/health") else {
            return (false, nil)
        }
        do {
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "GET"
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return (false, nil)
            }
            let info = try JSONDecoder().decode(HealthResponse.self, from: data)
            return (info.status == "ok" || info.status == "ready", info)
        } catch {
            return (false, nil)
        }
    }

    // MARK: - Segmentation

    struct SegmentResponse: Codable {
        let mask_b64_gzip: String
        let shape: [Int]
        let method: String
    }

    /// Run AI-powered segmentation on the given volume.
    ///
    /// - Parameters:
    ///   - volumeData: Flat float array in x+y*X+z*X*Y order.
    ///   - shape: Volume dimensions (X, Y, Z).
    ///   - spacing: Voxel spacing in mm (X, Y, Z).
    ///   - box: Optional bounding box prompt; if nil, a whole-volume default is used.
    /// - Returns: Flat `[UInt8]` mask (1 = ventricle, 0 = background), same size as input volume.
    func segment(
        volumeData: [Float],
        shape: (Int, Int, Int),
        spacing: (Float, Float, Float),
        box: BoundingBox? = nil
    ) async throws -> [UInt8] {
        let (X, Y, Z) = shape
        let total = X * Y * Z

        // Window to brain CT range [−5, 80] HU and normalise to 0–255 uint8
        var windowed = [UInt8](repeating: 0, count: total)
        for i in 0..<total {
            let hu = volumeData[i]
            let clamped = max(-5.0, min(80.0, hu))
            windowed[i] = UInt8(((clamped + 5.0) / 85.0) * 255.0)
        }

        // Gzip compress the uint8 volume
        let compressedData = try gzipCompress(Data(windowed))

        // Build multipart/form-data request
        guard let url = URL(string: "\(serverUrl)/api/segment") else {
            throw MedSAMError.invalidUrl
        }

        let boundary = "HydroMorphBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()
        // Volume field (compressed)
        body.appendMultipart(
            boundary: boundary, name: "volume",
            filename: "volume.bin.gz", contentType: "application/octet-stream",
            data: compressedData
        )
        // Shape field
        body.appendMultipart(boundary: boundary, name: "shape",
                             value: "[\(X),\(Y),\(Z)]")
        // Spacing field
        body.appendMultipart(boundary: boundary, name: "spacing",
                             value: "[\(spacing.0),\(spacing.1),\(spacing.2)]")
        // Box field — use provided box or auto-generate a central-slice full-frame box
        let effectiveBox = box ?? defaultBox(X: X, Y: Y, Z: Z)
        body.appendMultipart(boundary: boundary, name: "box",
                             value: effectiveBox.toJSON())
        // Final boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let detail = String(data: responseData, encoding: .utf8) ?? "unknown error"
            throw MedSAMError.serverError(detail: detail)
        }

        let result = try JSONDecoder().decode(SegmentResponse.self, from: responseData)

        // Decode base64 → gzip → raw mask bytes
        guard let maskCompressed = Data(base64Encoded: result.mask_b64_gzip) else {
            throw MedSAMError.invalidResponse
        }
        let maskData = try gzipDecompress(maskCompressed)
        return [UInt8](maskData)
    }

    // MARK: - Default bounding box

    private func defaultBox(X: Int, Y: Int, Z: Int) -> BoundingBox {
        BoundingBox(
            x1: Int(Double(X) * 0.25),
            y1: Int(Double(Y) * 0.25),
            x2: Int(Double(X) * 0.75),
            y2: Int(Double(Y) * 0.75),
            sliceIdx: Z / 2
        )
    }

    // MARK: - Gzip compress

    func gzipCompress(_ input: Data) throws -> Data {
        // Allocate destination buffer: compression can expand slightly for incompressible data,
        // so cap at input.count * 2 or 64 KB minimum.
        let dstCapacity = max(input.count * 2, 65536)
        var dst = Data(count: dstCapacity)

        // Write a minimal 10-byte gzip header
        let header: [UInt8] = [
            0x1F, 0x8B,  // magic
            0x08,        // DEFLATE
            0x00,        // FLG (no extra, no name, no comment)
            0x00, 0x00, 0x00, 0x00,  // MTIME = 0
            0x00,        // XFL
            0xFF         // OS = unknown
        ]
        var output = Data(header)

        // Compress the payload using COMPRESSION_ZLIB (raw DEFLATE)
        let compressedSize: Int = input.withUnsafeBytes { srcPtr in
            dst.withUnsafeMutableBytes { dstPtr in
                compression_encode_buffer(
                    dstPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    dstCapacity,
                    srcPtr.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard compressedSize > 0 else { throw MedSAMError.compressionFailed }
        output.append(dst.prefix(compressedSize))

        // CRC32 of uncompressed data (simplified: use 0x00000000 for our use-case
        // — the server only needs the DEFLATE payload to decompress correctly)
        let crc32: UInt32 = computeCRC32(input)
        withUnsafeBytes(of: crc32.littleEndian) { output.append(contentsOf: $0) }

        // ISIZE: uncompressed size mod 2^32
        let isize = UInt32(input.count & 0xFFFFFFFF)
        withUnsafeBytes(of: isize.littleEndian) { output.append(contentsOf: $0) }

        return output
    }

    // MARK: - Gzip decompress

    func gzipDecompress(_ input: Data) throws -> Data {
        // Re-use NiftiReader.gunzip logic; it strips the gzip envelope for us.
        guard let decompressed = NiftiReader.gunzip(input) else {
            throw MedSAMError.decompressionFailed
        }
        return decompressed
    }

    // MARK: - CRC32

    private func computeCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 == 1 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return ~crc
    }

    // MARK: - Errors

    enum MedSAMError: LocalizedError {
        case invalidUrl
        case serverError(detail: String)
        case invalidResponse
        case compressionFailed
        case decompressionFailed

        var errorDescription: String? {
            switch self {
            case .invalidUrl:
                return "Invalid MedSAM2 server URL."
            case .serverError(let detail):
                return "MedSAM2 server returned an error: \(detail)"
            case .invalidResponse:
                return "Invalid or undecodable response from MedSAM2 server."
            case .compressionFailed:
                return "Failed to gzip-compress volume data."
            case .decompressionFailed:
                return "Failed to decompress mask data from MedSAM2 server."
            }
        }
    }
}

// MARK: - Multipart helpers

extension Data {
    /// Append a multipart/form-data field carrying binary data.
    mutating func appendMultipart(
        boundary: String,
        name: String,
        filename: String? = nil,
        contentType: String? = nil,
        data: Data
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        if let filename = filename {
            append(
                "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                    .data(using: .utf8)!
            )
        } else {
            append(
                "Content-Disposition: form-data; name=\"\(name)\"\r\n"
                    .data(using: .utf8)!
            )
        }
        if let ct = contentType {
            append("Content-Type: \(ct)\r\n".data(using: .utf8)!)
        }
        append("\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    /// Append a multipart/form-data field carrying a UTF-8 string value.
    mutating func appendMultipart(boundary: String, name: String, value: String) {
        appendMultipart(boundary: boundary, name: name, data: value.data(using: .utf8)!)
    }
}
