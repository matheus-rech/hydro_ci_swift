// SliceViewerView.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Canvas-based axial and coronal NIfTI slice renderer with ventricle overlay.
// Faithfully ports renderAxialSlice, renderCoronalSlice, drawEvansAnnotation,
// and drawCallosalAnnotation from app.js.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import SwiftUI
import CoreGraphics

// MARK: - Slice type

enum SliceOrientation { case axial, coronal }

// MARK: - Axial Slice Viewer

struct AxialSliceViewer: View {
    let volume: Volume
    let result: PipelineResult
    @Binding var sliceIndex: Int
    @Binding var showMask: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Axial Slice")
                        .font(AppFont.body(14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("Brain window W:80 L:40")
                        .font(AppFont.body(11))
                        .foregroundColor(.textMuted)
                }
                Spacer()
                Button {
                    showMask.toggle()
                } label: {
                    Text(showMask ? "Hide Overlay" : "Show Overlay")
                        .font(AppFont.body(12, weight: .medium))
                        .foregroundColor(showMask ? .bgPrimary : .accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(showMask ? Color.accent : Color.accentMuted.opacity(0.2))
                        .cornerRadius(6)
                }
            }
            .padding(Spacing.md)
            .background(Color.bgSecondary)

            // Canvas
            SliceCanvas(
                volume: volume,
                result: result,
                sliceIndex: sliceIndex,
                showMask: showMask,
                orientation: .axial
            )
            .aspectRatio(
                CGFloat(volume.dimX) / CGFloat(volume.dimY),
                contentMode: .fit
            )

            // Controls
            VStack(spacing: Spacing.sm) {
                HStack {
                    Text("Slice \(sliceIndex) / \(volume.dimZ - 1)")
                        .font(AppFont.mono(12))
                        .foregroundColor(.textSecondary)
                    Spacer()
                    if sliceIndex == result.evansSlice {
                        Text("← Best Evans slice")
                            .font(AppFont.body(11))
                            .foregroundColor(.accent)
                    }
                }

                Slider(
                    value: Binding(
                        get: { Double(sliceIndex) },
                        set: { sliceIndex = Int($0) }
                    ),
                    in: 0...Double(max(volume.dimZ - 1, 1)),
                    step: 1
                )
                .accentColor(.accent)

                // Legend
                HStack(spacing: Spacing.md) {
                    LegendItem(color: .accent,  label: "Ventricle width (V)")
                    LegendItem(color: .orange,  label: "Skull width (S)")
                }
            }
            .padding(Spacing.md)
            .background(Color.bgSecondary)
        }
        .cardStyle()
    }
}

// MARK: - Coronal Slice Viewer

struct CoronalSliceViewer: View {
    let volume: Volume
    let result: PipelineResult

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coronal Slice")
                        .font(AppFont.body(14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Text("Best cross-section")
                        .font(AppFont.body(11))
                        .foregroundColor(.textMuted)
                }
                Spacer()
            }
            .padding(Spacing.md)
            .background(Color.bgSecondary)

            // Canvas
            SliceCanvas(
                volume: volume,
                result: result,
                sliceIndex: result.callosalSlice,
                showMask: true,
                orientation: .coronal
            )
            .aspectRatio(
                CGFloat(volume.dimX) / CGFloat(volume.dimZ),
                contentMode: .fit
            )

            // Legend
            HStack(spacing: Spacing.md) {
                LegendItem(color: .cyan,   label: "Vertex")
                LegendItem(color: .orange, label: "L/R points")
                LegendItem(color: .cyan.opacity(0.5), label: "Angle vectors")
            }
            .padding(Spacing.md)
            .background(Color.bgSecondary)
        }
        .cardStyle()
    }
}

// MARK: - LegendItem

struct LegendItem: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(AppFont.body(11))
                .foregroundColor(.textSecondary)
        }
    }
}

// MARK: - SliceCanvas

/// A SwiftUI view that renders a NIfTI slice using a CGImage drawn in Canvas.
struct SliceCanvas: View {
    let volume: Volume
    let result: PipelineResult
    let sliceIndex: Int
    let showMask: Bool
    let orientation: SliceOrientation

    var body: some View {
        GeometryReader { _ in
            let image = buildImage()
            Canvas { ctx, size in
                if let img = image {
                    ctx.draw(Image(decorative: img, scale: 1), in: CGRect(origin: .zero, size: size))
                }
                drawAnnotations(ctx: ctx, size: size)
            }
            .background(Color.black)
        }
    }

    // MARK: - Image generation

    private func buildImage() -> CGImage? {
        switch orientation {
        case .axial:
            return makeAxialImage()
        case .coronal:
            return makeCoronalImage()
        }
    }

    private func makeAxialImage() -> CGImage? {
        let X = volume.dimX, Y = volume.dimY
        let z = sliceIndex
        guard z >= 0, z < volume.dimZ else { return nil }

        var pixels = [UInt8](repeating: 255, count: X * Y * 4)

        for y in 0..<Y {
            for x in 0..<X {
                let hu = volume.voxel(x: x, y: y, z: z)
                let gray = UInt8(max(0, min(255, Int((min(max(hu, 0), 80) / 80) * 255))))
                let pixIdx = (y * X + x) * 4
                let isMask = showMask && result.ventMask[volume.index(x: x, y: y, z: z)] == 1
                if isMask {
                    // Blue tint for ventricle overlay
                    pixels[pixIdx]     = UInt8(min(255, Int(Float(gray) * 0.4 + 88 * 0.6)))
                    pixels[pixIdx + 1] = UInt8(min(255, Int(Float(gray) * 0.4 + 166 * 0.6)))
                    pixels[pixIdx + 2] = 255
                } else {
                    pixels[pixIdx]     = gray
                    pixels[pixIdx + 1] = gray
                    pixels[pixIdx + 2] = gray
                }
                pixels[pixIdx + 3] = 255
            }
        }
        return makeCGImage(pixels: pixels, width: X, height: Y)
    }

    private func makeCoronalImage() -> CGImage? {
        let X = volume.dimX, Z = volume.dimZ
        let y = result.callosalSlice
        guard y >= 0, y < volume.dimY else { return nil }

        var pixels = [UInt8](repeating: 255, count: X * Z * 4)

        for z in 0..<Z {
            for x in 0..<X {
                let hu = volume.voxel(x: x, y: y, z: z)
                let gray = UInt8(max(0, min(255, Int((min(max(hu, 0), 80) / 80) * 255))))
                // Flip z: display z=0 at bottom (dispZ = Z-1-z)
                let dispZ = Z - 1 - z
                let pixIdx = (dispZ * X + x) * 4
                let isMask = result.ventMask[volume.index(x: x, y: y, z: z)] == 1
                if isMask {
                    pixels[pixIdx]     = UInt8(min(255, Int(Float(gray) * 0.4 + 88 * 0.6)))
                    pixels[pixIdx + 1] = UInt8(min(255, Int(Float(gray) * 0.4 + 166 * 0.6)))
                    pixels[pixIdx + 2] = 255
                } else {
                    pixels[pixIdx]     = gray
                    pixels[pixIdx + 1] = gray
                    pixels[pixIdx + 2] = gray
                }
                pixels[pixIdx + 3] = 255
            }
        }
        return makeCGImage(pixels: pixels, width: X, height: Z)
    }

    private func makeCGImage(pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace, bitmapInfo: bitmapInfo,
            provider: provider, decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Annotation drawing

    private func drawAnnotations(ctx: GraphicsContext, size: CGSize) {
        switch orientation {
        case .axial:
            if sliceIndex == result.evansSlice {
                drawEvansAnnotation(ctx: ctx, size: size)
            }
        case .coronal:
            drawCallosalAnnotation(ctx: ctx, size: size)
        }
    }

    private func drawEvansAnnotation(ctx: GraphicsContext, size: CGSize) {
        guard let sliceData = result.evansData.perSlice.first(where: { $0.z == sliceIndex }) else { return }
        let X = volume.dimX, Y = volume.dimY
        let scaleX = size.width  / CGFloat(X)
        let scaleY = size.height / CGFloat(Y)

        let sy = CGFloat(Y) * 0.4 * scaleY

        // Ventricle width line (blue)
        var path = Path()
        path.move(to:    CGPoint(x: CGFloat(sliceData.ventLeft)  * scaleX, y: sy))
        path.addLine(to: CGPoint(x: CGFloat(sliceData.ventRight) * scaleX, y: sy))
        ctx.stroke(path, with: .color(.accent), lineWidth: 2)

        // Skull width line (orange)
        var skullPath = Path()
        skullPath.move(to:    CGPoint(x: CGFloat(sliceData.skullLeft)  * scaleX, y: sy + 8))
        skullPath.addLine(to: CGPoint(x: CGFloat(sliceData.skullRight) * scaleX, y: sy + 8))
        ctx.stroke(skullPath, with: .color(.orange), lineWidth: 2)

        // Labels
        ctx.draw(
            Text("V").font(AppFont.mono(12, weight: .bold)).foregroundColor(.accent),
            at: CGPoint(x: CGFloat(sliceData.ventLeft) * scaleX + 2, y: sy - 12)
        )
        ctx.draw(
            Text("S").font(AppFont.mono(12, weight: .bold)).foregroundColor(.orange),
            at: CGPoint(x: CGFloat(sliceData.skullLeft) * scaleX + 2, y: sy + 22)
        )
    }

    private func drawCallosalAnnotation(ctx: GraphicsContext, size: CGSize) {
        let calData = result.callosalData
        guard let vertex = calData.vertex,
              let leftPt = calData.leftPt,
              let rightPt = calData.rightPt else { return }

        let Z = volume.dimZ
        let X = volume.dimX
        let scaleX = size.width  / CGFloat(X)
        let scaleZ = size.height / CGFloat(Z)

        // Flip z: display z=0 at bottom
        let vx = CGFloat(vertex.x) * scaleX
        let vz = CGFloat(Z - 1) * scaleZ - CGFloat(vertex.z) * scaleZ
        let lx = CGFloat(leftPt.x) * scaleX
        let lz = CGFloat(Z - 1) * scaleZ - CGFloat(leftPt.z) * scaleZ
        let rx = CGFloat(rightPt.x) * scaleX
        let rz = CGFloat(Z - 1) * scaleZ - CGFloat(rightPt.z) * scaleZ

        // Dashed lines from vertex to left/right
        var leftPath = Path()
        leftPath.move(to: CGPoint(x: vx, y: vz))
        leftPath.addLine(to: CGPoint(x: lx, y: lz))
        ctx.stroke(leftPath,  with: .color(.cyan.opacity(0.7)), style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))

        var rightPath = Path()
        rightPath.move(to: CGPoint(x: vx, y: vz))
        rightPath.addLine(to: CGPoint(x: rx, y: rz))
        ctx.stroke(rightPath, with: .color(.cyan.opacity(0.7)), style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))

        // Vertex dot (cyan)
        let vRect = CGRect(x: vx - 5, y: vz - 5, width: 10, height: 10)
        ctx.fill(Path(ellipseIn: vRect), with: .color(.cyan))

        // L/R dots (orange)
        let lRect = CGRect(x: lx - 4, y: lz - 4, width: 8, height: 8)
        let rRect = CGRect(x: rx - 4, y: rz - 4, width: 8, height: 8)
        ctx.fill(Path(ellipseIn: lRect), with: .color(.orange))
        ctx.fill(Path(ellipseIn: rRect), with: .color(.orange))

        // Angle label
        if let angle = calData.angleDeg {
            ctx.draw(
                Text("\(Int(angle))°")
                    .font(AppFont.mono(14, weight: .bold))
                    .foregroundColor(.cyan),
                at: CGPoint(x: vx + 8, y: vz - 10)
            )
        }
    }
}
