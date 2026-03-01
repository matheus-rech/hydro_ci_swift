// ConnectedComponents.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// 3-D connected components labeling with 6-connectivity, using BFS.
// Faithfully ported from the JavaScript reference implementation.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import Foundation

// MARK: - Result type

struct ComponentsResult {
    let labels: [Int32]              // per-voxel component label (0 = background)
    let counts: [Int32: Int]         // label -> voxel count
    let numLabels: Int
}

// MARK: - Public API

enum ConnectedComponents {

    /// 3-D BFS connected components with 6-connectivity.
    /// Returns labels array (same size as mask) and counts dictionary.
    static func label3D(_ mask: [UInt8], shape: (Int, Int, Int)) -> ComponentsResult {
        let (X, Y, Z) = shape
        let total = X * Y * Z
        var labels = [Int32](repeating: 0, count: total)
        var counts = [Int32: Int]()
        var nextLabel: Int32 = 1

        // BFS queue encoded as flat triplets [x, y, z, x, y, z, …]
        // Pre-allocate a generous size; grow if needed.
        let queueCapacity = min(total * 3, 6 * 1024 * 1024)
        var queue = [Int32](repeating: 0, count: queueCapacity)

        for z in 0..<Z {
            for y in 0..<Y {
                for x in 0..<X {
                    let idx = x + y * X + z * X * Y
                    guard mask[idx] != 0, labels[idx] == 0 else { continue }

                    let label = nextLabel
                    nextLabel += 1
                    labels[idx] = label
                    var count = 1

                    var head = 0
                    var tail = 0
                    queue[tail] = Int32(x); tail += 1
                    queue[tail] = Int32(y); tail += 1
                    queue[tail] = Int32(z); tail += 1

                    while head < tail {
                        let cx = Int(queue[head]); head += 1
                        let cy = Int(queue[head]); head += 1
                        let cz = Int(queue[head]); head += 1

                        // 6-connectivity
                        let neighborOffsets: [(Int, Int, Int)] = [
                            (-1, 0, 0), (1, 0, 0),
                            (0, -1, 0), (0, 1, 0),
                            (0, 0, -1), (0, 0, 1)
                        ]
                        for (dx, dy, dz) in neighborOffsets {
                            let nx = cx + dx, ny = cy + dy, nz = cz + dz
                            guard nx >= 0, ny >= 0, nz >= 0,
                                  nx < X, ny < Y, nz < Z else { continue }
                            let nidx = nx + ny * X + nz * X * Y
                            guard mask[nidx] != 0, labels[nidx] == 0 else { continue }
                            labels[nidx] = label
                            count += 1
                            if tail + 3 <= queue.count {
                                queue[tail] = Int32(nx); tail += 1
                                queue[tail] = Int32(ny); tail += 1
                                queue[tail] = Int32(nz); tail += 1
                            }
                        }
                    }
                    counts[label] = count
                }
            }
        }
        return ComponentsResult(labels: labels, counts: counts, numLabels: Int(nextLabel - 1))
    }

    // MARK: - Keep largest component

    /// Returns a new mask containing only the single largest connected component.
    /// - Parameter minSize: Minimum voxel count; returns empty mask if largest is smaller.
    static func keepLargest(_ mask: [UInt8], shape: (Int, Int, Int), minSize: Int = 1) -> [UInt8] {
        let result = label3D(mask, shape: shape)
        var maxLabel: Int32 = -1
        var maxCount = 0
        for (label, count) in result.counts {
            if count > maxCount { maxCount = count; maxLabel = label }
        }
        guard maxLabel >= 0, maxCount >= minSize else {
            return [UInt8](repeating: 0, count: mask.count)
        }
        return result.labels.map { $0 == maxLabel ? 1 : 0 }
    }

    // MARK: - Keep all components ≥ threshold

    /// Returns a new mask keeping all components with count ≥ minSize.
    static func keepLarge(_ mask: [UInt8], shape: (Int, Int, Int), minSize: Int = 500) -> [UInt8] {
        let result = label3D(mask, shape: shape)
        var keepSet = Set<Int32>()
        for (label, count) in result.counts {
            if count >= minSize { keepSet.insert(label) }
        }
        return result.labels.map { keepSet.contains($0) ? 1 : 0 }
    }
}
