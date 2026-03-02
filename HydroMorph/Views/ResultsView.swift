// ResultsView.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// Main results layout: NPH badge, metric cards, slice viewers, measurements table.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import SwiftUI

struct ResultsView: View {
    @EnvironmentObject var vm: PipelineViewModel

    var body: some View {
        guard let result = vm.result, let volume = vm.volume else {
            // Fallback: shouldn't happen but gracefully go back
            return AnyView(
                VStack {
                    Text("No results available")
                        .foregroundColor(.textSecondary)
                    Button("New Scan") { vm.reset() }
                        .foregroundColor(.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgPrimary.ignoresSafeArea())
            )
        }
        return AnyView(resultsBody(result: result, volume: volume))
    }

    // MARK: - Main body

    private func resultsBody(result: PipelineResult, volume: Volume) -> some View {
        VStack(spacing: 0) {

            // ── Sticky top bar ──────────────────────────────────────
            topBar

            // ── Scrollable content ──────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {

                    // A: NPH Assessment
                    sectionHeader("NPH Assessment")
                    NPHBadgeView(result: result)

                    // B: Key Metrics
                    sectionHeader("Key Metrics")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: Spacing.sm) {
                        MetricCardView.evansCard(value: result.evansIndex)
                        MetricCardView.angleCard(value: result.callosalAngle)
                        MetricCardView.volumeCard(ml: result.ventVolMl)
                        MetricCardView.nphCard(score: result.nphScore, pct: result.nphPct)
                    }
                    refLegend

                    // C: Axial Slice Viewer
                    sectionHeader("Axial View — Evans Index")
                    AxialSliceViewer(
                        volume: volume,
                        result: result,
                        sliceIndex: $vm.currentAxialSlice,
                        showMask: $vm.showMask
                    )

                    // D: Coronal Slice Viewer
                    sectionHeader("Coronal View — Callosal Angle")
                    CoronalSliceViewer(volume: volume, result: result)

                    // E: Detailed Measurements
                    sectionHeader("Detailed Measurements")
                    MeasurementsTableView(result: result)

                    // F: Sanity Checks
                    sectionHeader("Sanity Checks")
                    SanityChecksView(result: result)

                    // New scan button
                    Button {
                        vm.reset()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.uturn.left")
                            Text("Analyze New Scan")
                                .font(AppFont.body(16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .foregroundColor(.bgPrimary)
                        .background(Color.accent)
                        .cornerRadius(Radius.md)
                    }
                    .buttonStyle(.plain)

                    // Footer
                    footerSection
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            }
        }
        .background(Color.bgPrimary.ignoresSafeArea())
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            HStack(spacing: Spacing.sm) {
                Text("🧠")
                Text("HydroMorph")
                    .font(AppFont.body(17, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("Results")
                    .font(AppFont.body(11, weight: .semibold))
                    .foregroundColor(.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accent.opacity(0.15))
                    .cornerRadius(4)
            }
            Spacer()
            // Segmentation method badge
            if let result = vm.result {
                segMethodBadge(result.segmentationMethod)
            }
            // Settings
            Button {
                vm.showSettings = true
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .padding(8)
                    .background(Color.bgTertiary)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            // New scan
            Button {
                vm.reset()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.left")
                        .font(.system(size: 11))
                    Text("New Scan")
                        .font(AppFont.body(12, weight: .medium))
                }
                .foregroundColor(.danger)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.danger.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.bgSecondary)
        .overlay(Divider().background(Color.border), alignment: .bottom)
    }

    @ViewBuilder
    private func segMethodBadge(_ method: SegmentationMethod) -> some View {
        HStack(spacing: 4) {
            Image(systemName: method == .medsam2 ? "sparkles" : "cpu")
                .font(.system(size: 10))
            Text(method.displayName)
                .font(AppFont.body(10, weight: .medium))
        }
        .foregroundColor(method == .medsam2 ? .accent : .textMuted)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background((method == .medsam2 ? Color.accent : Color.textMuted).opacity(0.12))
        .cornerRadius(5)
    }

    // MARK: - Reference legend

    private var refLegend: some View {
        HStack(spacing: Spacing.md) {
            LegendItem(color: .success,  label: "Normal range")
            LegendItem(color: .danger,   label: "Abnormal range")
            LegendItem(color: .accent,   label: "Ventricle overlay")
        }
        .padding(.top, -Spacing.sm)
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppFont.body(13, weight: .semibold))
            .foregroundColor(.textMuted)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 4) {
            Text("⚠ Research use only. Not for clinical diagnosis.")
                .font(AppFont.body(11, weight: .medium))
                .foregroundColor(.warning)
            Text("HydroMorph v2.0.0")
                .font(AppFont.mono(11))
                .foregroundColor(.textMuted)
            Text("Matheus Machado Rech")
                .font(AppFont.body(12))
                .foregroundColor(.textSecondary)
            Text("Data reference: CADS BrainCT-1mm (CC BY 4.0)")
                .font(AppFont.body(11))
                .foregroundColor(.textMuted)
                .opacity(0.7)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }
}
