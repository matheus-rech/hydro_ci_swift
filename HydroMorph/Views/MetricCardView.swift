// MetricCardView.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Individual metric card for Evans Index, Callosal Angle, Ventricle Volume, NPH%.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import SwiftUI

// MARK: - Metric status

enum MetricStatus {
    case normal, abnormal, moderate

    var backgroundColor: Color {
        switch self {
        case .normal:   return .metricNormal
        case .abnormal: return .metricAbnormal
        case .moderate: return .metricModerate
        }
    }

    var borderColor: Color {
        switch self {
        case .normal:   return .success.opacity(0.3)
        case .abnormal: return .danger.opacity(0.3)
        case .moderate: return .warning.opacity(0.3)
        }
    }

    var valueColor: Color {
        switch self {
        case .normal:   return .success
        case .abnormal: return .danger
        case .moderate: return .warning
        }
    }
}

// MARK: - MetricCardView

struct MetricCardView: View {
    let value: String
    let label: String
    let reference: String
    let status: MetricStatus

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(value)
                .font(AppFont.mono(22, weight: .bold))
                .foregroundColor(status.valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(AppFont.body(13, weight: .medium))
                .foregroundColor(.textPrimary)

            Text(reference)
                .font(AppFont.body(11))
                .foregroundColor(.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(status.backgroundColor)
        .cornerRadius(Radius.md)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(status.borderColor, lineWidth: 1)
        )
    }
}

// MARK: - Preview helpers

extension MetricCardView {
    static func evansCard(value: Double) -> MetricCardView {
        MetricCardView(
            value: String(format: "%.3f", value),
            label: "Evans Index",
            reference: ">0.3 = abnormal",
            status: value > 0.3 ? .abnormal : .normal
        )
    }

    static func angleCard(value: Double?) -> MetricCardView {
        let displayVal = value.map { "\(Int($0))°" } ?? "N/A"
        let status: MetricStatus = value.map { $0 < 90 ? .abnormal : .normal } ?? .normal
        return MetricCardView(
            value: displayVal,
            label: "Callosal Angle",
            reference: "<90° = abnormal",
            status: status
        )
    }

    static func volumeCard(ml: Double) -> MetricCardView {
        MetricCardView(
            value: String(format: "%.1f mL", ml),
            label: "Ventricle Volume",
            reference: ">50 mL = abnormal",
            status: ml > 50 ? .abnormal : .normal
        )
    }

    static func nphCard(score: Int, pct: Int) -> MetricCardView {
        let status: MetricStatus = score >= 2 ? .abnormal : (score == 1 ? .moderate : .normal)
        return MetricCardView(
            value: "\(pct)%",
            label: "NPH Probability",
            reference: "\(score)/3 criteria",
            status: status
        )
    }
}
