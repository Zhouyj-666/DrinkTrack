import SwiftUI
import CoreLocation

/// Sheet for explicitly marking a place on the 路书 map.
/// Creates a PlaceMark (not a drink session) and can back-fill same-name rows.
struct MarkPlaceSheet: View {
    @EnvironmentObject private var drinkRepository: DrinkRepository
    @Environment(\.dismiss) private var dismiss

    let initialCoordinate: CLLocationCoordinate2D?
    let initialName: String
    var mode: Mode = .newMark

    enum Mode {
        case newMark
        case fillExisting
    }

    @StateObject private var locationProvider = LocationProvider()
    @State private var name: String = ""
    @State private var note: String = ""
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var errorMessage: String?
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("地点名称", text: $name)
                    if mode == .newMark {
                        TextField("备注（可选）", text: $note)
                    }
                } header: {
                    Text(mode == .fillExisting ? "给已有地点补上坐标" : "标记地点")
                } footer: {
                    Text(mode == .fillExisting
                        ? "只会给同名的记录补上坐标，不会新增一场饮酒。打开地图本身不会申请定位。"
                        : "这是路书上的一个地点标记，不会算成一场饮酒。分享卡片也不会带上坐标。")
                }

                Section {
                    Button {
                        locationProvider.fillCurrentPlace { place in
                            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                name = place.name
                            }
                            latitude = place.latitude
                            longitude = place.longitude
                            if place.latitude == nil {
                                errorMessage = "拿到了位置名称，但没有可用坐标，请稍后再试或长按地图选点。"
                            } else {
                                errorMessage = nil
                            }
                        }
                    } label: {
                        if locationProvider.state == .locating {
                            HStack {
                                ProgressView()
                                Text("正在定位…")
                            }
                        } else {
                            Label("用当前位置", systemImage: "location")
                        }
                    }
                    .disabled(locationProvider.state == .locating)

                    if let latitude, let longitude {
                        Text(String(format: "已选坐标 %.4f, %.4f", latitude, longitude))
                            .font(.caption)
                            .foregroundStyle(DesignSystem.secondaryInk)
                    } else if initialCoordinate != nil {
                        Text("已从地图选点")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.secondaryInk)
                    } else {
                        Text("还没有坐标：可用当前位置，或先在地图上长按选点。")
                            .font(.caption)
                            .foregroundStyle(DesignSystem.mutedInk)
                    }

                    if case .failed(let message) = locationProvider.state {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.statusWarning)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(DesignSystem.statusWarning)
                    }
                } header: {
                    Text("坐标")
                }
            }
            .navigationTitle(mode == .fillExisting ? "补点" : "标记地点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if name.isEmpty { name = initialName }
                if latitude == nil, let initialCoordinate {
                    latitude = initialCoordinate.latitude
                    longitude = initialCoordinate.longitude
                }
            }
        }
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && latitude != nil && longitude != nil && !didSave
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let latitude, let longitude else { return }
        didSave = true
        if mode == .fillExisting {
            drinkRepository.applyCoordinatesToPlaceName(trimmed, latitude: latitude, longitude: longitude)
        } else {
            _ = drinkRepository.addPlaceMark(
                name: trimmed,
                latitude: latitude,
                longitude: longitude,
                note: note
            )
        }
        dismiss()
    }
}