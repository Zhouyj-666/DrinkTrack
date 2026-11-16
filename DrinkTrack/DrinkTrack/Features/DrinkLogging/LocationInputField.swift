import SwiftUI

/// FR-DR-05：地点输入。手动输入、点「用当前位置」或点最近用过的地点。
/// 「用当前位置」会带上这次的坐标；手动输入或点最近地点时，若本机已经有同一名称的坐标，会沿用，不会去按名称估点。
struct LocationInputField: View {
    @Binding var locationName: String
    @Binding var latitude: Double?
    @Binding var longitude: Double?
    @ObservedObject var provider: LocationProvider
    var knownCoordinate: (String) -> (Double, Double)? = { _ in nil }
    var onResolved: (() -> Void)? = nil

    /// The name last filled by 「用当前位置」, so an immediate onChange
    /// does not wipe the fresh coordinates before they settle.
    @State private var resolvedName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(DesignSystem.secondaryInk)
                TextField("例如：家里、三里屯某酒吧", text: $locationName)
                if !locationName.isEmpty {
                    Button {
                        resolvedName = nil
                        locationName = ""
                        latitude = nil
                        longitude = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignSystem.mutedInk)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("清除地点")
                }
            }

            HStack {
                Button {
                    provider.fillCurrentPlace { place in
                        resolvedName = place.name
                        locationName = place.name
                        latitude = place.latitude
                        longitude = place.longitude
                        onResolved?()
                    }
                } label: {
                    if provider.state == .locating {
                        HStack(spacing: 6) {
                            ProgressView()
                            Text("正在定位…")
                        }
                    } else {
                        Label("用当前位置", systemImage: "location")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(provider.state == .locating)
                .font(.footnote)

                Spacer()
            }

            if case .failed(let message) = provider.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DesignSystem.statusWarning)
            }

            let recents = UserPreferences.recentLocations.filter { $0 != locationName }
            if !recents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(recents, id: \.self) { name in
                            Button(name) { applyPlaceName(name) }
                                .font(.caption)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .onChange(of: locationName) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if let resolvedName, resolvedName == trimmed {
                return
            }
            resolvedName = nil
            applyKnownOrClear(trimmed)
        }
    }

    private func applyPlaceName(_ name: String) {
        resolvedName = nil
        locationName = name
        applyKnownOrClear(name)
    }

    private func applyKnownOrClear(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            latitude = nil
            longitude = nil
            return
        }
        if let known = knownCoordinate(trimmed) {
            latitude = known.0
            longitude = known.1
        } else {
            latitude = nil
            longitude = nil
        }
    }
}
