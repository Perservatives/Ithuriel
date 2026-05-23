import SwiftUI

/// Full-screen takeover that sits behind the LaunchOrb. Arc-style: black with
/// soft fuzzy color blobs that bloom in, drift, and breathe. The color is
/// pulled from `UserPrefs.launchColorHex` (with the system accent as
/// fallback).
struct LaunchBackdropView: View {
    let baseColor: Color

    init(baseColor: Color = .accentColor) {
        self.baseColor = baseColor
    }

    var body: some View {
        LaunchBlobsView(baseColor: baseColor)
            .ignoresSafeArea()
    }
}
