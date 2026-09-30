import MapKit
import SwiftUI

/// Bible places on a map, with Paul's journeys and a traditional Exodus route.
struct BibleMapView: View {
    @Environment(\.studyData) private var studyData
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette

    @State private var places: [PlaceSummary] = []
    @State private var routes: [Route] = []
    @State private var route: Route?
    @State private var selection: Int?
    @State private var position: MapCameraPosition = .region(BibleMapView.biblicalWorld)

    /// Egypt to Mesopotamia, Israel in the middle.
    static let biblicalWorld = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 32.0, longitude: 35.5),
        span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 16)
    )

    var body: some View {
        Map(position: $position, selection: $selection) {
            if let route {
                MapPolyline(coordinates: route.stops.compactMap(\.coordinate))
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [8, 5]))
                ForEach(Array(route.stops.enumerated()), id: \.offset) { index, stop in
                    if let coordinate = stop.coordinate {
                        Marker(stop.name, monogram: Text("\(index + 1)"), coordinate: coordinate)
                            .tint(palette.accent)
                            .tag(stop.id)
                    }
                }
            } else {
                ForEach(places) { place in
                    if let coordinate = place.coordinate {
                        Marker(place.name, systemImage: place.symbol, coordinate: coordinate)
                            .tint(palette.accent)
                            .tag(place.id)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top) { journeyPicker }
        .safeAreaInset(edge: .bottom) {
            if let selected = selectedPlace {
                placeCard(selected)
            }
        }
        .accessibilityIdentifier("map.view")
        .task { load() }
    }

    private var selectedPlace: PlaceSummary? {
        guard let selection else { return nil }
        return (route?.stops ?? places).first { $0.id == selection }
    }

    private var journeyPicker: some View {
        HStack {
            Menu {
                Button("All Places") { show(nil) }
                ForEach(routes) { item in
                    Button(item.title) { show(item) }
                }
            } label: {
                Label(route?.title ?? "Journeys", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassEffect(.regular, in: Capsule())
            }
            .accessibilityIdentifier("map.journeys")
            Spacer()
            if let route {
                Button {
                    router.read(route.firstVerse)
                } label: {
                    Label(route.passage, systemImage: "book")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassEffect(.regular, in: Capsule())
                }
                .accessibilityIdentifier("map.readRoute")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func placeCard(_ place: PlaceSummary) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                    .font(.headline)
                    .foregroundStyle(palette.text)
                Text(place.verseCount == 1 ? "\(place.kindTitle) \u{00B7} 1 mention" : "\(place.kindTitle) \u{00B7} \(place.verseCount) mentions")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            Button("Details") { router.explore(.place(place.id)) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("map.placeDetails")
        }
        .padding(14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func show(_ newRoute: Route?) {
        selection = nil
        route = newRoute
        withAnimation {
            position = newRoute == nil ? .region(Self.biblicalWorld) : .automatic
        }
    }

    private func load() {
        guard places.isEmpty, let studyData else { return }
        // The best-attested places keep the map readable; all of them are in search.
        places = (try? studyData.mappedPlaces(minimumMentions: 3, limit: 400)) ?? []
        routes = (try? studyData.routes()) ?? []
    }
}

extension PlaceSummary {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var symbol: String {
        switch kind {
        case "City": "building.2"
        case "Mountain", "Valley": "mountain.2"
        case "Water": "water.waves"
        case "Region": "map"
        case "Landmark": "building.columns"
        case "Island": "circle.dashed"
        default: "mappin"
        }
    }

    /// "City", "Region", …; "Place" where the dataset doesn't say.
    var kindTitle: String { kind.isEmpty ? "Place" : kind }
}

/// A small map of a few places, for detail screens.
struct PlacesMap: View {
    let places: [PlaceSummary]
    @Environment(\.palette) private var palette

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
            ForEach(places) { place in
                if let coordinate = place.coordinate {
                    Marker(place.name, coordinate: coordinate)
                        .tint(palette.accent)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .accessibilityLabel("Map of \(places.map(\.name).formatted(.list(type: .and)))")
    }
}

/// One place: where it is, what happened there, and the verses that name it.
struct PlaceDetailView: View {
    let placeID: Int

    @Environment(\.studyData) private var studyData
    @Environment(AppRouter.self) private var router
    @Environment(\.palette) private var palette

    var body: some View {
        if let studyData, let place = try? studyData.place(id: placeID) {
            let events = (try? studyData.events(atPlace: placeID)) ?? []
            let verses = (try? studyData.verses(forPlace: placeID)) ?? []
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(place.name)
                            .font(.system(.title2, design: .serif, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .accessibilityIdentifier("place.name")
                        Text([place.summary.kindTitle, place.aliases.isEmpty ? nil : "Also \(place.aliases)"].compactMap { $0 }.joined(separator: " \u{00B7} "))
                            .font(.subheadline)
                            .foregroundStyle(palette.secondaryText)
                    }
                    if place.summary.isMapped {
                        VStack(alignment: .leading, spacing: 6) {
                            PlacesMap(places: [place.summary])
                                .frame(height: 220)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            if !place.isPrecise {
                                Label("The exact location is uncertain.", systemImage: "questionmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                    if !place.description.isEmpty {
                        DetailSection(title: "About") { DictionaryText(text: place.description) }
                    }
                    if !events.isEmpty {
                        DetailSection(title: "Events Here") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(events) { event in
                                    Button { router.explore(.event(event.id)) } label: { EventRow(event: event) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    if !verses.isEmpty {
                        DetailSection(title: "Mentioned In") { VerseMentionList(verses: verses) }
                    }
                    Text(StudyRepository.attribution)
                        .font(.caption2)
                        .foregroundStyle(palette.secondaryText)
                }
                .padding(20)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .themedScreen()
            .navigationTitle(place.name)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            StudyDataMissingView()
        }
    }
}
