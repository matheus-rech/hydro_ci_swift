// NPHBadgeView.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Large NPH probability badge displayed at top of results.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import SwiftUI

struct NPHBadgeView: View {
    let result: PipelineResult

    private var levelColor: Color {
        switch result.nphLevel {
        case .low:      return .nphLow
        case .moderate: return .nphModerate
        case .high:     return .nphHigh
        }
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            // Level label
            Text(result.nphLevel.rawValue)
                .font(AppFont.body(28, weight: .black))
                .foregroundColor(levelColor)
                .tracking(2)

            Text("NPH Probability")
                .font(AppFont.body(13))
                .foregroundColor(.textSecondary)

            // Percentage
            Text("\(result.nphPct)%")
                .font(AppFont.mono(36, weight: .bold))
                .foregroundColor(levelColor)

            // Score line
            Text("\(result.nphScore)/3 criteria met")
                .font(AppFont.body(13))
                .foregroundColor(.textSecondary)

            // Criteria dots
            criteriaDots
        }
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(levelColor.opacity(0.08))
        .cornerRadius(Radius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(levelColor.opacity(0.35), lineWidth: 2)
        )
    }

    private var criteriaDots: some View {
        HStack(spacing: Spacing.sm) {
            CriteriaDot(
                label: "Evans >0.3",
                met: result.evansIndex > 0.3,
                color: levelColor
            )
            CriteriaDot(
                label: "Angle <90°",
                met: (result.callosalAngle ?? 999) < 90,
                color: levelColor
            )
            CriteriaDot(
                label: "Vol >50 mL",
                met: result.ventVolMl > 50,
                color: levelColor
            )
        }
        .padding(.top, 2)
    }
}

// MARK: - Criteria dot

private struct CriteriaDot: View {
    let label: String
    let met: Bool
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(met ? color : .textMuted)
            Text(label)
                .font(AppFont.body(11))
                .foregroundColor(met ? .textPrimary : .textMuted)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(met ? color.opacity(0.12) : Color.bgTertiary)
        .cornerRadius(20)
    }
}
