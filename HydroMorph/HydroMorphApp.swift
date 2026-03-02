// HydroMorphApp.swift
// HydroMorph — Hydrocephalus Morphometrics Pipeline
// App entry point with settings sheet support.
// Author: Matheus Machado Rech
// Research use only — not for clinical diagnosis

import SwiftUI

@main
struct HydroMorphApp: App {

    @StateObject private var viewModel = PipelineViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Root navigator

struct ContentView: View {
    @EnvironmentObject var vm: PipelineViewModel

    var body: some View {
        ZStack {
            Color.bgPrimary.ignoresSafeArea()
            switch vm.currentScreen {
            case .upload:
                UploadView()
            case .processing:
                ProcessingView()
            case .results:
                ResultsView()
            }
        }
        // Global settings sheet — accessible from any screen via vm.showSettings
        .sheet(isPresented: $vm.showSettings) {
            SettingsView()
                .environmentObject(vm)
        }
        .animation(.easeInOut(duration: 0.3), value: vm.currentScreen)
    }
}
