import SwiftUI
import MapKit
import UIKit

/// Branded 饮酒地图 share card: title, date range, named stops, and a map overview.
/// Place names are labeled on the map so a shop is recognizable; latitude and
/// longitude numbers are never drawn or printed on the card.
struct RouteJournalShareCardView: View {
    static let renderWidth: CGFloat = 360

    let payload: RouteJournalExport
    var mapImage: UIImage? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text(payload.recapLine)
                .font(.subheadline)
                .foregroundStyle(DesignSystem.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            mapBlock

            if !payload.items.isEmpty {
                stopList
            }

            Text(payload.privacyLine)
                .font(.caption2)
                .foregroundStyle(DesignSystem.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: Self.renderWidth, alignment: .leading)
        .background(DesignSystem.chartSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DesignSystem.gridline))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("小酌场 饮酒地图")
                    .font(.headline)
                    .foregroundStyle(DesignSystem.primaryInk)
                Text("\(payload.rangeTitle) · \(payload.dateRangeText)")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.secondaryInk)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var mapBlock: some View {
        if let mapImage {
            Image(uiImage: mapImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if payload.mappedStopCount == 0 && payload.nameOnlyCount > 0 {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "mappin.slash")
                    .foregroundStyle(Color("AccentColor"))
                Text("这些地点还没有坐标，饮酒地图上暂不标点。")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.pagePlane)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var stopList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleItems) { item in
                HStack(alignment: .top, spacing: 8) {
                    if let pin = item.pinNumber {
                        SharePinBadge(number: pin)
                    } else {
                        Image(systemName: "mappin.slash.circle")
                            .font(.body)
                            .foregroundStyle(DesignSystem.mutedInk)
                            .frame(width: 24, height: 24)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignSystem.primaryInk)
                        Text(itemLine(item))
                            .font(.caption)
                            .foregroundStyle(DesignSystem.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
            }
            if payload.items.count > visibleItems.count {
                Text("……还有 \(payload.items.count - visibleItems.count) 站")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.mutedInk)
            }
        }
    }

    private var visibleItems: [RouteJournalExport.StopItem] {
        Array(payload.items.prefix(16))
    }

    private func itemLine(_ item: RouteJournalExport.StopItem) -> String {
        if item.isNameOnly {
            return "\(item.dateText) · 仅名称，图上未标点"
        }
        return "\(item.dateText) · \(item.kindLabel)"
    }
}

private struct SharePinBadge: View {
    let number: Int

    var body: some View {
        ZStack {
            Circle()
                .fill(Color("AccentColor"))
                .frame(width: 24, height: 24)
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .accessibilityLabel("第 \(number) 站")
    }
}

// MARK: - Export sheet

struct RouteJournalExportSheet: View {
    let payload: RouteJournalExport
    let mappedStops: [RouteStop]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var mapImage: UIImage?
    @State private var cardImage: UIImage?
    @State private var pngURL: URL?
    @State private var pdfURL: URL?
    @State private var isPreparing = true
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let cardImage {
                        Image(uiImage: cardImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    } else {
                        RouteJournalShareCardView(payload: payload, mapImage: mapImage)
                            .frame(maxWidth: .infinity)
                    }

                    Text(payload.privacyLine)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.secondaryInk)
                    Text("可保存为图片或 PDF，也可发到微信、朋友圈或其他应用。图上按店名标点，不附带经纬度数字。")
                        .font(.caption)
                        .foregroundStyle(DesignSystem.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        showShare = true
                    } label: {
                        Label("分享到其他应用", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPreparing || (cardImage == nil && pngURL == nil))
                    .accessibilityLabel("分享到其他应用")
                }
                .padding()
            }
            .background(DesignSystem.pagePlane)
            .navigationTitle("导出饮酒地图")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showShare) {
                ActivityShareItemsView(items: shareItems)
            }
            .task { await prepare() }
        }
    }

    private var shareItems: [Any] {
        var items: [Any] = [payload.shareableText]
        if let pngURL {
            items.append(pngURL)
        } else if let cardImage {
            items.append(cardImage)
        }
        if let pdfURL {
            items.append(pdfURL)
        }
        return items
    }

    @MainActor
    private func prepare() async {
        isPreparing = true
        let scheme = colorScheme
        if payload.mappedStopCount > 0 {
            mapImage = await RouteJournalMapOverview.render(
                stops: mappedStops,
                size: CGSize(width: RouteJournalShareCardView.renderWidth - 36, height: 200),
                colorScheme: scheme
            )
        }
        let rendered = RouteJournalExportRenderer.makeImage(payload: payload, mapImage: mapImage, colorScheme: scheme)
        cardImage = rendered
        if let rendered {
            let name = RouteJournalExportRenderer.fileStem(for: payload)
            pngURL = RouteJournalExportRenderer.writePNG(rendered, suggestedName: name)
            pdfURL = RouteJournalExportRenderer.writePDF(image: rendered, suggestedName: name)
        }
        isPreparing = false
    }
}

// MARK: - Map overview (snapshot, with schematic fallback)

enum RouteJournalMapOverview {
    /// Renders a map overview with numbered, named pins. Exact coordinates are
    /// never written into the image.
    @MainActor
    static func render(stops: [RouteStop], size: CGSize, colorScheme: ColorScheme) async -> UIImage? {
        let snapshot = await mapSnapshot(stops: stops, size: size, colorScheme: colorScheme)
        if let snapshot {
            return snapshot
        }
        return schematicImage(stops: stops, size: size, colorScheme: colorScheme)
    }

    private static func mapSnapshot(stops: [RouteStop], size: CGSize, colorScheme: ColorScheme) async -> UIImage? {
        guard !stops.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let options = MKMapSnapshotter.Options()
        options.region = RouteJournal.fitRegion(for: stops.map(\.coordinate))
        options.size = size
        options.scale = 3
        options.traitCollection = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light),
            UITraitCollection(displayScale: 3)
        ])
        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            return annotate(snapshot: snapshot, stops: stops, colorScheme: colorScheme)
        } catch {
            return nil
        }
    }

    private static func annotate(snapshot: MKMapSnapshotter.Snapshot, stops: [RouteStop], colorScheme: ColorScheme) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size, format: format)
        return renderer.image { context in
            snapshot.image.draw(at: .zero)
            let points = stops.map { snapshot.point(for: $0.coordinate) }
            drawRoute(points, in: context.cgContext)
            let pins = RouteJournal.numberedPins(from: stops)
            for item in pins {
                let point = snapshot.point(for: item.stop.coordinate)
                drawPin(number: item.number, name: item.stop.name, at: point, colorScheme: colorScheme)
            }
        }
    }

    static func schematicImage(stops: [RouteStop], size: CGSize, colorScheme: ColorScheme) -> UIImage? {
        guard !stops.isEmpty, size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let points = schematicPoints(from: stops, size: size)
        return renderer.image { context in
            fillSchematicBackground(size: size, colorScheme: colorScheme, context: context.cgContext)
            drawRoute(points, in: context.cgContext)
            let pins = RouteJournal.numberedPins(from: stops)
            let pinPoints = schematicPinPoints(pins: pins, stops: stops, size: size)
            for (item, point) in zip(pins, pinPoints) {
                drawPin(number: item.number, name: item.stop.name, at: point, colorScheme: colorScheme)
            }
        }
    }

    private static func schematicPoints(from stops: [RouteStop], size: CGSize) -> [CGPoint] {
        guard let first = stops.first else { return [] }
        let lats = stops.map(\.latitude)
        let lons = stops.map(\.longitude)
        let minLat = lats.min() ?? first.latitude
        let maxLat = lats.max() ?? first.latitude
        let minLon = lons.min() ?? first.longitude
        let maxLon = lons.max() ?? first.longitude
        let midLat = (minLat + maxLat) / 2
        let lonScale = max(cos(midLat * .pi / 180), 0.2)
        let rawWidth = max((maxLon - minLon) * lonScale, 1e-6)
        let rawHeight = max(maxLat - minLat, 1e-6)
        let padX = size.width * 0.14
        let padY = size.height * 0.18
        let usableW = max(size.width - padX * 2, 1)
        let usableH = max(size.height - padY * 2, 1)
        let scale = min(usableW / rawWidth, usableH / rawHeight)
        let usedW = rawWidth * scale
        let usedH = rawHeight * scale
        let originX = padX + (usableW - usedW) / 2
        let originY = padY + (usableH - usedH) / 2
        return stops.map { stop in
            let x = originX + ((stop.longitude - minLon) * lonScale) * scale
            let y = originY + (maxLat - stop.latitude) * scale
            return CGPoint(x: x, y: y)
        }
    }

    private static func schematicPinPoints(
        pins: [(number: Int, stop: RouteStop)],
        stops: [RouteStop],
        size: CGSize
    ) -> [CGPoint] {
        let points = schematicPoints(from: stops, size: size)
        var latestIndex: [String: Int] = [:]
        for (index, stop) in stops.enumerated() {
            latestIndex[stop.name] = index
        }
        return pins.compactMap { item in
            guard let index = latestIndex[item.stop.name], index < points.count else { return nil }
            return points[index]
        }
    }

    private static func fillSchematicBackground(size: CGSize, colorScheme: ColorScheme, context: CGContext) {
        let bg = colorScheme == .dark ? UIColor(red: 0.12, green: 0.12, blue: 0.11, alpha: 1) : UIColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1)
        bg.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        let grid = colorScheme == .dark ? UIColor.white.withAlphaComponent(0.06) : UIColor.black.withAlphaComponent(0.06)
        grid.setStroke()
        context.setLineWidth(1)
        let step: CGFloat = 28
        var x: CGFloat = 0
        while x <= size.width {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y: CGFloat = 0
        while y <= size.height {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        context.strokePath()
    }

    private static func drawRoute(_ points: [CGPoint], in context: CGContext) {
        guard points.count >= 2 else { return }
        context.setStrokeColor(UIColor(named: "AccentColor")?.cgColor ?? UIColor(red: 0.66, green: 0.16, blue: 0.14, alpha: 1).cgColor)
        context.setLineWidth(3)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setAlpha(0.85)
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
        context.setAlpha(1)
    }

    private static func drawPin(number: Int, name: String, at point: CGPoint, colorScheme: ColorScheme) {
        let radius: CGFloat = 11
        let accent = UIColor(named: "AccentColor") ?? UIColor(red: 0.66, green: 0.16, blue: 0.14, alpha: 1)
        let circle = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        accent.setFill()
        UIColor.black.withAlphaComponent(0.25).setStroke()
        let path = UIBezierPath(ovalIn: circle)
        path.lineWidth = 1
        path.fill()
        path.stroke()

        let numberText = "\(number)" as NSString
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let numberSize = numberText.size(withAttributes: numberAttrs)
        numberText.draw(
            at: CGPoint(x: point.x - numberSize.width / 2, y: point.y - numberSize.height / 2),
            withAttributes: numberAttrs
        )

        let label = name as NSString
        let labelColor: UIColor = colorScheme == .dark ? .white : UIColor(white: 0.08, alpha: 1)
        let bubbleColor: UIColor = colorScheme == .dark ? UIColor.black.withAlphaComponent(0.62) : UIColor.white.withAlphaComponent(0.88)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: labelColor
        ]
        let labelSize = label.size(withAttributes: labelAttrs)
        let padding = CGSize(width: 5, height: 2)
        var labelOrigin = CGPoint(x: point.x + radius + 4, y: point.y - labelSize.height / 2 - padding.height)
        // Keep the name on-canvas without printing any coordinate numbers.
        let bubbleSize = CGSize(width: labelSize.width + padding.width * 2, height: labelSize.height + padding.height * 2)
        if labelOrigin.x + bubbleSize.width > (point.x + 160) {
            // still fine; clamp later using a generous canvas
        }
        let bubble = CGRect(origin: labelOrigin, size: bubbleSize)
        bubbleColor.setFill()
        UIBezierPath(roundedRect: bubble, cornerRadius: 4).fill()
        label.draw(
            at: CGPoint(x: labelOrigin.x + padding.width, y: labelOrigin.y + padding.height),
            withAttributes: labelAttrs
        )
    }
}

// MARK: - Image / PDF renderer

enum RouteJournalExportRenderer {
    @MainActor
    static func makeImage(payload: RouteJournalExport, mapImage: UIImage?, colorScheme: ColorScheme) -> UIImage? {
        let content = RouteJournalShareCardView(payload: payload, mapImage: mapImage)
            .frame(width: RouteJournalShareCardView.renderWidth)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(width: RouteJournalShareCardView.renderWidth, height: nil)
        return renderer.uiImage
    }

    static func fileStem(for payload: RouteJournalExport) -> String {
        "小酌场饮酒地图-\(payload.rangeTitle)"
    }

    static func writePNG(_ image: UIImage, suggestedName: String) -> URL? {
        guard let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(suggestedName).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func writePDF(image: UIImage, suggestedName: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(suggestedName).pdf")
        let margin: CGFloat = 24
        let bounds = CGRect(x: 0, y: 0, width: image.size.width + margin * 2, height: image.size.height + margin * 2)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                image.draw(in: CGRect(x: margin, y: margin, width: image.size.width, height: image.size.height))
            }
            return url
        } catch {
            return nil
        }
    }
}

/// System share sheet that can carry a 饮酒地图 image, PDF, and caption together.
struct ActivityShareItemsView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
