import SwiftUI

struct FloppyMenuBarIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let origin = CGPoint(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2
            )
            FloppyMenuBarMark(origin: origin, side: side)
                .fill(.primary, style: FillStyle(eoFill: true))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct FloppyMenuBarMark: Shape {
    let origin: CGPoint
    let side: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let t = FloppyIconTransform(origin: origin, side: side)

        addPolygon([
            t.point(0.92, 15.25),
            t.point(4.62, 2.85),
            t.point(6.88, 2.85),
            t.point(10.62, 15.25),
            t.point(7.72, 15.25),
            t.point(7.08, 12.78),
            t.point(4.36, 12.78),
            t.point(3.7, 15.25)
        ], to: &path)
        addPolygon([
            t.point(4.52, 10.45),
            t.point(6.92, 10.45),
            t.point(5.72, 6.45)
        ], to: &path)
        path.addEllipse(in: t.rect(centerX: 11.65, centerY: 7.05, radius: 0.92))
        path.addEllipse(in: t.rect(centerX: 11.65, centerY: 12.28, radius: 0.92))
        addPolygon([
            t.point(16.02, 2.85),
            t.point(17.5, 2.85),
            t.point(14.02, 15.25),
            t.point(12.54, 15.25)
        ], to: &path)

        return path
    }

    private func addPolygon(_ points: [CGPoint], to path: inout Path) {
        guard let first = points.first else {
            return
        }

        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
    }
}

private struct FloppyIconTransform {
    let origin: CGPoint
    let side: CGFloat

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + (x / 18) * side,
            y: origin.y + (y / 18) * side
        )
    }

    func rect(centerX: CGFloat, centerY: CGFloat, radius: CGFloat) -> CGRect {
        let center = point(centerX, centerY)
        let scaledRadius = (radius / 18) * side
        return CGRect(
            x: center.x - scaledRadius,
            y: center.y - scaledRadius,
            width: scaledRadius * 2,
            height: scaledRadius * 2
        )
    }
}
