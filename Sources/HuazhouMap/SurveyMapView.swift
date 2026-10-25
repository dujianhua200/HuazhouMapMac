import SwiftUI
import MapKit
import HuazhouCore

/// 地图上的测点标注（coordinate 必须可写，才能被拖动）
final class PointAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let pointID: UUID
    let index: Int
    let title: String?
    let kind: ObjectKind

    init(coordinate: CLLocationCoordinate2D, pointID: UUID, index: Int, title: String, kind: ObjectKind) {
        self.coordinate = coordinate
        self.pointID = pointID
        self.index = index
        self.title = title
        self.kind = kind
    }
}

struct SurveyMapView: NSViewRepresentable {
    @ObservedObject var state: AppState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
        map.isRotateEnabled = false
        map.isPitchEnabled = false

        let center = CLLocationCoordinate2D(latitude: 32.1301, longitude: 114.0814)
        map.setRegion(
            MKCoordinateRegion(center: center, latitudinalMeters: 1200, longitudinalMeters: 1200),
            animated: false
        )

        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        click.delaysPrimaryMouseButtonEvents = false
        map.addGestureRecognizer(click)

        context.coordinator.mapView = map
        context.coordinator.sync(map, force: true)
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.state = state
        context.coordinator.sync(map, force: false)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var state: AppState
        weak var mapView: MKMapView?

        private var signature = ""
        private var appliedStyle: MapStyleChoice?
        private var appliedTileURL: String?
        private var appliedCustomTile = false

        init(state: AppState) {
            self.state = state
        }

        /// 单击地图打点；点在已有标注上时不新增
        @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard state.addMode, let map = mapView else { return }
            let location = recognizer.location(in: map)
            for annotation in map.annotations {
                let point = map.convert(annotation.coordinate, toPointTo: map)
                if hypot(point.x - location.x, point.y - location.y) < 16 { return }
            }
            let coordinate = map.convert(location, toCoordinateFrom: map)
            let wgs84 = state.storageCoordinate(LatLon(latitude: coordinate.latitude, longitude: coordinate.longitude))
            state.addPoint(at: wgs84)
        }

        func sync(_ map: MKMapView, force: Bool) {
            applyStyle(map)
            applyTileOverlay(map)

            let newSignature = makeSignature()
            guard force || newSignature != signature else { return }
            signature = newSignature

            map.removeAnnotations(map.annotations)
            for (index, point) in state.chain.orderedPoints.enumerated() {
                let display = state.displayCoordinate(point.coordinate)
                let annotation = PointAnnotation(
                    coordinate: CLLocationCoordinate2D(latitude: display.latitude, longitude: display.longitude),
                    pointID: point.id,
                    index: index + 1,
                    title: "\(point.name)（\(point.kind.displayName)）",
                    kind: point.kind
                )
                map.addAnnotation(annotation)
            }

            map.removeOverlays(map.overlays.filter { !($0 is MKTileOverlay) })
            let coordinates = state.chain.orderedPoints.map { point -> CLLocationCoordinate2D in
                let display = state.displayCoordinate(point.coordinate)
                return CLLocationCoordinate2D(latitude: display.latitude, longitude: display.longitude)
            }
            if coordinates.count >= 2 {
                map.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
            }
        }

        private func applyStyle(_ map: MKMapView) {
            guard appliedStyle != state.mapStyle else { return }
            appliedStyle = state.mapStyle
            switch state.mapStyle {
            case .standard: map.mapType = .standard
            case .satellite: map.mapType = .satellite
            case .hybrid: map.mapType = .hybrid
            }
        }

        private func applyTileOverlay(_ map: MKMapView) {
            let url = state.customTileURL
            let enabled = state.useCustomTiles
            guard appliedCustomTile != enabled || appliedTileURL != url else { return }
            appliedCustomTile = enabled
            appliedTileURL = url

            map.removeOverlays(map.overlays.filter { $0 is MKTileOverlay })
            guard enabled, !url.isEmpty else { return }
            let overlay = MKTileOverlay(urlTemplate: url)
            overlay.canReplaceMapContent = true
            map.addOverlay(overlay, level: .aboveLabels)
        }

        private func makeSignature() -> String {
            let correction = state.project.applyGCJCorrection ? "gcj" : "wgs"
            let points = state.chain.orderedPoints.map {
                "\($0.id)|\($0.name)|\($0.kind.rawValue)|\($0.coordinate.latitude)|\($0.coordinate.longitude)"
            }.joined(separator: ";")
            return "\(state.project.chainMode.rawValue)#\(correction)#\(points)"
        }

        private func tintColor(for kind: ObjectKind) -> NSColor {
            switch kind {
            case .pole: return .systemRed
            case .manhole: return .systemBlue
            case .joint: return .systemPurple
            case .marker: return .systemOrange
            case .crossing: return .systemTeal
            case .station: return .systemGreen
            case .other: return .systemGray
            }
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? PointAnnotation else { return nil }
            let identifier = "surveyPoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: point, reuseIdentifier: identifier)
            view.annotation = point
            view.canShowCallout = true
            view.isDraggable = true
            view.markerTintColor = tintColor(for: point.kind)
            view.glyphText = "\(point.index)"
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemRed
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let point = view.annotation as? PointAnnotation else { return }
            state.selection = point.pointID
        }

        /// 拖动标注结束后把新位置写回工程
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState,
                     fromOldState oldState: MKAnnotationView.DragState) {
            guard newState == .ending, let point = view.annotation as? PointAnnotation else { return }
            let display = LatLon(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
            let stored = state.storageCoordinate(display)
            DispatchQueue.main.async { [weak self] in
                self?.state.movePoint(id: point.pointID, to: stored)
            }
        }
    }
}
