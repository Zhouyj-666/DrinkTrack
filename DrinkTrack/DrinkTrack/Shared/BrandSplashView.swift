import SwiftUI

/// In-app branded splash shown after process launch so the composed
/// SipSession / 小酌场 art is actually visible on a cold start.
///
/// The system launch storyboard can be cached by iOS across Sideloadly
/// reinstalls of the same bundle id, or can flash by so quickly that it
/// reads as "no splash". This view uses the same composed portrait art
/// (not the 720p delivery JPG upscaled) and then fades to the real root.
struct BrandSplashView: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()
            Image("LaunchPortrait")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("小酌场 SipSession")
    }
}
