import SwiftUI
import MapKit
import HuazhouCore

/// 地图上的测点标注
final class PointAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let pointID: UUID
    let index: Int
    let title: String?

    init(coordinate: CLLocationCoordinate2D, pointID: UUID, index: Int, title: String) {
        self.coordinate = coordinate
        self.pointID = pointID
        self.index = index
        self.title = title
    }
}

struct SurveyMapView: NSViewRepresentable {
    @ObservedObject var state: AppState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

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

        @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard state.addMode, let map = mapView else { return }
            let location = recognizer.location(in: map)
            let coordinate = map.convert(location, toCoordinateFrom: map)
            state.addPoint(at: LatLon(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }

        func sync(_ map: MKMapView, force: Bool) {
            applyStyle(map)
            applyTileOverlay(map)

            let newSignature = makeSignature()
            guard force || newSignature != signature else { return }
            signature = newSignature

            map.removeAnnotations(map.annotations)
            for (index, point) in state.chain.orderedPoints.enumerated() {
                let annotation = PointAnnotation(
                    coordinate: CLLocationCoordinate2D(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude),
                    pointID: point.id,
                    index: index + 1,
                    title: point.name
                )
                map.addAnnotation(annotation)
            }

            map.removeOverlays(map.overlays.filter { !($0 is MKTileOverlay) })
            let coordinates = state.chain.orderedPoints.map {
                CLLocationCoordinate2D(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
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
            let points = state.chain.orderedPoints.map {
                "\($0.id)|\($0.name)|\($0.coordinate.latitude)|\($0.coordinate.longitude)"
            }.joined(separator: ";")
            return "\(state.project.chainMode.rawValue)#\(points)"
        }

        // MARK: - MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? PointAnnotation else { return nil }
            let identifier = "surveyPoint"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: point, reuseIdentifier: identifier)
            view.annotation = point
            view.canShowCallout = true
            view.markerTintColor = .systemRed
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
    }
}
