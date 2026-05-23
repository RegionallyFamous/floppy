import SwiftUI

struct FloppyMenuBarIcon: View {
    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let origin = CGPoint(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2
            )
            ZStack {
                FloppyMenuBarSlashMark(origin: origin, side: side)
                    .stroke(.primary, style: StrokeStyle(lineWidth: side * 0.106, lineCap: .round, lineJoin: .round))
                FloppyMenuBarColonMark(origin: origin, side: side)
                    .fill(.primary)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct FloppyMenuBarSlashMark: Shape {
    let origin: CGPoint
    let side: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let t = FloppyIconTransform(origin: origin, side: side)

        path.move(to: t.point(2.4, 14.2))
        path.addLine(to: t.point(5.5, 3.9))
        path.addLine(to: t.point(8.6, 14.2))
        path.move(to: t.point(3.5, 10.5))
        path.addLine(to: t.point(7.5, 10.5))
        path.move(to: t.point(15.6, 4.1))
        path.addLine(to: t.point(12.5, 14.1))

        return path
    }
}

private struct FloppyMenuBarColonMark: Shape {
    let origin: CGPoint
    let side: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let t = FloppyIconTransform(origin: origin, side: side)
        path.addEllipse(in: t.rect(centerX: 10.6, centerY: 7.6, radius: 0.85))
        path.addEllipse(in: t.rect(centerX: 10.6, centerY: 12.0, radius: 0.85))
        return path
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
