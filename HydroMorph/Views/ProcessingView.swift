// ProcessingView.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Step-by-step processing progress screen with animated brain icon.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import SwiftUI

struct ProcessingView: View {
    @EnvironmentObject var vm: PipelineViewModel

    // Pulse animation for brain icon
    @State private var pulsing = false

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                Spacer(minLength: Spacing.xl)

                // ── Header ──────────────────────────────────────────
                VStack(spacing: Spacing.sm) {
                    Text("🧠")
                        .font(.system(size: 56))
                        .scaleEffect(pulsing ? 1.08 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                            value: pulsing
                        )
                        .onAppear { pulsing = true }

                    Text("Analyzing your scan…")
                        .font(AppFont.body(20, weight: .semibold))
                        .foregroundColor(.textPrimary)

                    Text(vm.processingFileName)
                        .font(AppFont.mono(13))
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                // ── Volume metadata ─────────────────────────────────
                metadataGrid

                // ── Progress steps ──────────────────────────────────
                progressList

                // ── Detail message ──────────────────────────────────
                Text(vm.progressDetail)
                    .font(AppFont.mono(12))
                    .foregroundColor(.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)
                    .animation(.easeInOut, value: vm.progressDetail)

                Spacer(minLength: Spacing.xl)
            }
            .padding(.horizontal, Spacing.md)
        }
        .background(Color.bgPrimary.ignoresSafeArea())
    }

    // MARK: - Metadata grid

    private var metadataGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible())
        ], spacing: Spacing.sm) {
            MetaItem(label: "Shape",    value: vm.volumeShape)
            MetaItem(label: "Spacing",  value: vm.volumeSpacing)
            MetaItem(label: "Datatype", value: vm.volumeDatatype)
            MetaItem(label: "File size",value: vm.volumeFileSize)
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    // MARK: - Progress steps list

    private var progressList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(vm.steps) { step in
                StepRow(step: step)
            }
        }
        .padding(Spacing.md)
        .cardStyle()
    }
}

// MARK: - MetaItem

private struct MetaItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.body(11))
                .foregroundColor(.textMuted)
                .textCase(.uppercase)
            Text(value)
                .font(AppFont.mono(13))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - StepRow

private struct StepRow: View {
    let step: ProgressStep

    var body: some View {
        HStack(spacing: Spacing.md) {
            stepIcon
                .frame(width: 20)
            Text(step.label)
                .font(AppFont.body(14))
                .foregroundColor(labelColor)
            Spacer()
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var stepIcon: some View {
        switch step.state {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.success)
        case .active:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .accent))
                .scaleEffect(0.8)
        case .pending:
            Circle()
                .stroke(Color.border, lineWidth: 1.5)
                .frame(width: 16, height: 16)
        }
    }

    private var labelColor: Color {
        switch step.state {
        case .done:    return .textSecondary
        case .active:  return .accent
        case .pending: return .textMuted
        }
    }
}
