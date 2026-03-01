# HydroMorph — Swift/SwiftUI iOS App

**Native iOS hydrocephalus morphometrics app.**
Evans Index · Callosal Angle · Ventricle Volume · NPH Scoring

100% on-device. Zero external dependencies. Apple frameworks only.

## Deploy (pick your level)

### Level 1: Simulator build (zero config)

1. Create a GitHub repo, push these files to `main`
2. GitHub Actions builds automatically on the macOS runner
3. Download the simulator `.app` from the Actions → Artifacts tab
4. Drag it into your iOS Simulator

**No secrets, no signing, no Apple Developer account needed.**

### Level 2: TestFlight (needs Apple Developer account)

1. Complete Level 1 setup
2. Add these secrets to your repo (Settings → Secrets → Actions):

| Secret | What it is | How to get it |
|--------|-----------|---------------|
| `APPLE_CERTIFICATE_P12` | Distribution cert (base64) | Keychain Access → export .p12 → `base64 -i cert.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Cert password | The password you set during export |
| `APPLE_PROVISIONING_PROFILE` | Provisioning profile (base64) | developer.apple.com → Profiles → download → `base64 -i profile.mobileprovision` |
| `APPLE_KEY_ID` | API key ID | App Store Connect → Users → Keys |
| `APPLE_ISSUER_ID` | API issuer ID | Same page as above |
| `APPLE_KEY_P8` | API private key (base64) | Download .p8 → `base64 -i AuthKey.p8` |

3. Uncomment the `testflight` job in `.github/workflows/build.yml`
4. Push → builds → uploads to TestFlight → testers get a notification

### Level 3: Local Xcode

```bash
open HydroMorph.xcodeproj
# Select your device/simulator, hit ⌘R
```

## What happens on push

```
push to main
  → macos-26 runner (Apple Silicon, latest Xcode)
  → xcodebuild for iOS Simulator
  → .app uploaded as non-zipped artifact (direct download)
  → (optional) Archive → IPA → TestFlight
```

## Project structure

```
├── HydroMorph/
│   ├── HydroMorphApp.swift              # App entry point
│   ├── Info.plist                        # .nii document type declarations
│   ├── Models/
│   │   ├── NiftiReader.swift             # NIfTI-1 parser (gzip via Compression framework)
│   │   ├── Volume.swift                  # Voxel volume model
│   │   ├── PipelineResult.swift          # Results + sanity warnings
│   │   └── MorphometricsPipeline.swift   # Full 9-step async pipeline
│   ├── Views/
│   │   ├── UploadView.swift              # File importer + sample data
│   │   ├── ProcessingView.swift          # Animated progress
│   │   ├── ResultsView.swift             # Full results dashboard
│   │   ├── MetricCardView.swift          # Status-colored cards
│   │   ├── NPHBadgeView.swift            # NPH probability badge
│   │   ├── SliceViewerView.swift         # Canvas-based slice renderer
│   │   └── MeasurementsTableView.swift   # Detailed measurements
│   ├── ViewModels/
│   │   └── PipelineViewModel.swift       # @MainActor ObservableObject
│   ├── Utilities/
│   │   ├── MorphologicalOps.swift        # 3D erosion/dilation/opening/closing
│   │   ├── ConnectedComponents.swift     # BFS 3D labeling
│   │   └── Theme.swift                   # GitHub-dark color tokens
│   └── Resources/
│       └── sample-data.json              # Bundled 64×64 CT demo
├── HydroMorph.xcodeproj/
├── .github/workflows/build.yml           # CI/CD
└── README.md
```

## Requirements

- iOS 16+
- Xcode 15+
- No external dependencies (SPM, CocoaPods, etc.)

## Author

**Matheus Machado Rech**

Research use only — not for clinical diagnosis.
