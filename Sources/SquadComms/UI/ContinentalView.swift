import SwiftUI
import MapKit

/// The radar, once distance stops being a gym-floor question.
///
/// At 100 miles and beyond, concentric rings are meaningless — everybody sits
/// at the outer edge and the display says nothing. A map does say something:
/// roughly where in the country somebody is. This is the one place a real map
/// beats an abstraction, so the radar hands over to it rather than pretending
/// the rings still work.
struct ContinentalView: View {
    let members: [Member]

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 42, longitudeDelta: 52)
        )
    )

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                ForEach(members.filter { $0.coordinate != nil }) { member in
                    Annotation(member.displayName, coordinate: member.coordinate!) {
                        ZStack {
                            Circle()
                                .fill(member.isSpeaking ? Theme.live : Theme.accent)
                                .frame(width: 12, height: 12)
                            Circle()
                                .strokeBorder(.white, lineWidth: 2)
                                .frame(width: 12, height: 12)
                        }
                    }
                }
            }
            .mapStyle(.hybrid(elevation: .realistic))

            Text("CONTINENTAL")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(10)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .bottom) {
            if members.allSatisfy({ $0.coordinate == nil }) {
                // Location is not collected unless somebody opts in, so at this
                // range the map is often empty. Say why rather than showing a
                // blank continent.
                Text("Nobody is sharing a location")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 12)
            }
        }
    }
}
