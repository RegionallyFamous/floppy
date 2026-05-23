import SwiftUI

struct FloppyMenuBarIcon: View {
    var body: some View {
        FloppyMenuBarSymbol()
            .fill(.primary, style: FillStyle(eoFill: true))
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct FloppyMenuBarSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let t = Transform(rect: rect)

        path.move(to: t.point(3.0, 1.7))
        path.addLine(to: t.point(12.8, 1.7))
        path.addLine(to: t.point(16.3, 5.2))
        path.addLine(to: t.point(16.3, 15.1))
        path.addQuadCurve(to: t.point(15.1, 16.3), control: t.point(16.3, 16.3))
        path.addLine(to: t.point(2.9, 16.3))
        path.addQuadCurve(to: t.point(1.7, 15.1), control: t.point(1.7, 16.3))
        path.addLine(to: t.point(1.7, 3.0))
        path.addQuadCurve(to: t.point(3.0, 1.7), control: t.point(1.7, 1.7))
        path.closeSubpath()

        path.addRoundedRect(
            in: t.rect(x: 5.3, y: 2.9, width: 6.9, height: 3.9),
            cornerSize: t.size(width: 0.45, height: 0.45)
        )

        path.addRoundedRect(
            in: t.rect(x: 10.1, y: 3.7, width: 1.1, height: 2.2),
            cornerSize: t.size(width: 0.2, height: 0.2)
        )

        path.addRoundedRect(
            in: t.rect(x: 4.5, y: 9.0, width: 9.0, height: 4.9),
            cornerSize: t.size(width: 0.65, height: 0.65)
        )

        path.addRoundedRect(
            in: t.rect(x: 5.7, y: 10.2, width: 6.5, height: 0.65),
            cornerSize: t.size(width: 0.2, height: 0.2)
        )

        path.addRoundedRect(
            in: t.rect(x: 3.2, y: 12.8, width: 1.3, height: 1.6),
            cornerSize: t.size(width: 0.25, height: 0.25)
        )

        path.addRoundedRect(
            in: t.rect(x: 13.5, y: 4.3, width: 1.2, height: 1.5),
            cornerSize: t.size(width: 0.25, height: 0.25)
        )

        return path
    }
}

private struct Transform {
    let rect: CGRect

    private var side: CGFloat {
        min(rect.width, rect.height)
    }

    private var origin: CGPoint {
        CGPoint(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2
        )
    }

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(
            x: origin.x + (x / 18) * side,
            y: origin.y + (y / 18) * side
        )
    }

    func rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: point(x, y).x,
            y: point(x, y).y,
            width: (width / 18) * side,
            height: (height / 18) * side
        )
    }

    func size(width: CGFloat, height: CGFloat) -> CGSize {
        CGSize(
            width: (width / 18) * side,
            height: (height / 18) * side
        )
    }
}
