// MeasurementsTableView.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Detailed measurements table and sanity check warnings.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import SwiftUI

// MARK: - Measurements table

struct MeasurementsTableView: View {
    let result: PipelineResult

    var body: some View {
        VStack(spacing: 0) {
            tableHeader
            Divider().background(Color.border)
            ForEach(rows, id: \.measurement) { row in
                tableRow(row)
                Divider().background(Color.border.opacity(0.4))
            }
        }
        .cardStyle()
    }

    // MARK: - Table rows data

    private var rows: [TableRow] {
        let (X, Y, Z) = result.shape
        let (sx, sy, sz) = result.spacing
        let voxVol = Double(sx) * Double(sy) * Double(sz)

        return [
            TableRow(
                measurement: "Evans Index",
                value: String(format: "%.4f", result.evansIndex),
                unit: "ratio",
                status: result.evansIndex > 0.3 ? .abnormal : .normal
            ),
            TableRow(
                measurement: "Best Evans Slice",
                value: "\(result.evansSlice)",
                unit: "voxel",
                status: .neutral
            ),
            TableRow(
                measurement: "Callosal Angle",
                value: result.callosalAngle.map { "\(Int($0))" } ?? "N/A",
                unit: "degrees",
                status: (result.callosalAngle ?? 999) < 90 ? .abnormal : .normal
            ),
            TableRow(
                measurement: "Callosal Slice (coronal)",
                value: "\(result.callosalSlice)",
                unit: "voxel",
                status: .neutral
            ),
            TableRow(
                measurement: "Ventricle Volume",
                value: String(format: "%.0f", result.ventVolMm3),
                unit: "mm³",
                status: .neutral
            ),
            TableRow(
                measurement: "Ventricle Volume",
                value: String(format: "%.2f", result.ventVolMl),
                unit: "mL",
                status: result.ventVolMl > 50 ? .abnormal : .normal
            ),
            TableRow(
                measurement: "Ventricle Voxels",
                value: "\(result.ventCount)",
                unit: "voxels",
                status: .neutral
            ),
            TableRow(
                measurement: "Voxel Volume",
                value: String(format: "%.4f", voxVol),
                unit: "mm³",
                status: .neutral
            ),
            TableRow(
                measurement: "Volume (X×Y×Z)",
                value: "\(X)×\(Y)×\(Z)",
                unit: "voxels",
                status: .neutral
            ),
            TableRow(
                measurement: "Spacing (X×Y×Z)",
                value: String(format: "%.3f×%.3f×%.3f", sx, sy, sz),
                unit: "mm/voxel",
                status: .neutral
            ),
        ]
    }

    // MARK: - Header

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("Measurement")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Value")
                .frame(width: 100, alignment: .trailing)
            Text("Unit")
                .frame(width: 70, alignment: .trailing)
            Text("Status")
                .frame(width: 80, alignment: .trailing)
        }
        .font(AppFont.body(11, weight: .semibold))
        .foregroundColor(.textMuted)
        .textCase(.uppercase)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgSecondary)
    }

    // MARK: - Row

    private func tableRow(_ row: TableRow) -> some View {
        HStack(spacing: 0) {
            Text(row.measurement)
                .font(AppFont.body(13))
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .minimumScaleFactor(0.8)

            Text(row.value)
                .font(AppFont.mono(12))
                .foregroundColor(.textSecondary)
                .frame(width: 100, alignment: .trailing)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(row.unit)
                .font(AppFont.body(11))
                .foregroundColor(.textMuted)
                .frame(width: 70, alignment: .trailing)

            statusBadge(row.status)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func statusBadge(_ status: TableRowStatus) -> some View {
        switch status {
        case .normal:
            Text("NORMAL")
                .font(AppFont.body(10, weight: .semibold))
                .foregroundColor(.success)
        case .abnormal:
            Text("ABNORMAL")
                .font(AppFont.body(10, weight: .semibold))
                .foregroundColor(.danger)
        case .neutral:
            Text("—")
                .font(AppFont.body(11))
                .foregroundColor(.textMuted)
        }
    }
}

// MARK: - Sanity checks

struct SanityChecksView: View {
    let result: PipelineResult

    var body: some View {
        let warnings = result.sanityWarnings
        if warnings.isEmpty {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.success)
                Text("All measurements within expected ranges")
                    .font(AppFont.body(13))
                    .foregroundColor(.textSecondary)
                Spacer()
            }
            .padding(Spacing.md)
            .background(Color.success.opacity(0.06))
            .cornerRadius(Radius.md)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.success.opacity(0.2), lineWidth: 1))
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(warnings, id: \.self) { warning in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.warning)
                            .font(.system(size: 13))
                            .padding(.top, 1)
                        Text(warning)
                            .font(AppFont.body(13))
                            .foregroundColor(.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.warning.opacity(0.06))
                    .cornerRadius(Radius.md)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).stroke(Color.warning.opacity(0.2), lineWidth: 1))
                }
            }
        }
    }
}

// MARK: - Data types

private struct TableRow {
    let measurement: String
    let value: String
    let unit: String
    let status: TableRowStatus
}

private enum TableRowStatus { case normal, abnormal, neutral }
