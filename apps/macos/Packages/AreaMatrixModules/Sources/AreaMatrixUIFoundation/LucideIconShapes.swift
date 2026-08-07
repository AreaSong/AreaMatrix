import SwiftUI

struct LucideFolderShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 20, y: 20))
        path.addArc(tangent1End: CGPoint(x: 22, y: 20), tangent2End: CGPoint(x: 22, y: 18), radius: 2)
        path.addLine(to: CGPoint(x: 22, y: 8))
        path.addArc(tangent1End: CGPoint(x: 22, y: 6), tangent2End: CGPoint(x: 20, y: 6), radius: 2)
        path.addLine(to: CGPoint(x: 12.1, y: 6))
        path.addLine(to: CGPoint(x: 10.41, y: 4.1))
        path.addArc(tangent1End: CGPoint(x: 9.6, y: 3.9), tangent2End: CGPoint(x: 7.93, y: 3), radius: 2)
        path.addLine(to: CGPoint(x: 4, y: 3))
        path.addArc(tangent1End: CGPoint(x: 2, y: 3), tangent2End: CGPoint(x: 2, y: 5), radius: 2)
        path.addLine(to: CGPoint(x: 2, y: 18))
        path.addArc(tangent1End: CGPoint(x: 2, y: 20), tangent2End: CGPoint(x: 4, y: 20), radius: 2)
        path.closeSubpath()
        return path
    }
}

struct LucideShieldCheckShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 12, y: 22))
        path.addCurve(to: CGPoint(x: 20, y: 12), control1: CGPoint(x: 20, y: 18), control2: CGPoint(x: 20, y: 12))
        path.addLine(to: CGPoint(x: 20, y: 5))
        path.addLine(to: CGPoint(x: 12, y: 2))
        path.addLine(to: CGPoint(x: 4, y: 5))
        path.addLine(to: CGPoint(x: 4, y: 12))
        path.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 4, y: 18), control2: CGPoint(x: 12, y: 22))
        path.move(to: CGPoint(x: 9, y: 12))
        path.addLine(to: CGPoint(x: 11, y: 14))
        path.addLine(to: CGPoint(x: 15, y: 10))
        return path
    }
}

struct LucideFilesShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 15.5, y: 2))
        path.addLine(to: CGPoint(x: 8.6, y: 2))
        path.addQuadCurve(to: CGPoint(x: 7, y: 3.6), control: CGPoint(x: 7, y: 2))
        path.addLine(to: CGPoint(x: 7, y: 16.4))
        path.addQuadCurve(to: CGPoint(x: 8.6, y: 18), control: CGPoint(x: 7, y: 18))
        path.addLine(to: CGPoint(x: 18.4, y: 18))
        path.addQuadCurve(to: CGPoint(x: 20, y: 16.4), control: CGPoint(x: 20, y: 18))
        path.addLine(to: CGPoint(x: 20, y: 6.5))
        path.closeSubpath()
        path.move(to: CGPoint(x: 15, y: 2))
        path.addLine(to: CGPoint(x: 15, y: 7))
        path.addLine(to: CGPoint(x: 20, y: 7))
        path.move(to: CGPoint(x: 3, y: 7.6))
        path.addLine(to: CGPoint(x: 3, y: 20.4))
        path.addQuadCurve(to: CGPoint(x: 4.6, y: 22), control: CGPoint(x: 3, y: 22))
        path.addLine(to: CGPoint(x: 14.4, y: 22))
        return path
    }
}

struct LucideArrowRightShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 5, y: 12))
        path.addLine(to: CGPoint(x: 19, y: 12))
        path.move(to: CGPoint(x: 12, y: 5))
        path.addLine(to: CGPoint(x: 19, y: 12))
        path.move(to: CGPoint(x: 12, y: 19))
        path.addLine(to: CGPoint(x: 19, y: 12))
        return path
    }
}

struct LucideArrowLeftShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 19, y: 12))
        path.addLine(to: CGPoint(x: 5, y: 12))
        path.move(to: CGPoint(x: 12, y: 5))
        path.addLine(to: CGPoint(x: 5, y: 12))
        path.move(to: CGPoint(x: 12, y: 19))
        path.addLine(to: CGPoint(x: 5, y: 12))
        return path
    }
}

struct LucideGlobeShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
        path.move(to: CGPoint(x: 2, y: 12))
        path.addLine(to: CGPoint(x: 22, y: 12))
        let ellipse = Path { ellipsePath in
            ellipsePath.addEllipse(in: CGRect(x: 6, y: 2, width: 12, height: 20))
        }
        path.addPath(ellipse)
        return path
    }
}

struct LucideInfoShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
        path.move(to: CGPoint(x: 12, y: 16))
        path.addLine(to: CGPoint(x: 12, y: 12))
        path.move(to: CGPoint(x: 12, y: 8))
        path.addLine(to: CGPoint(x: 12.01, y: 8))
        return path
    }
}

struct LucideCheckCircleShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
        path.move(to: CGPoint(x: 9, y: 12))
        path.addLine(to: CGPoint(x: 11, y: 14))
        path.addLine(to: CGPoint(x: 15, y: 10))
        return path
    }
}

struct LucideXCircleShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
        path.move(to: CGPoint(x: 15, y: 9))
        path.addLine(to: CGPoint(x: 9, y: 15))
        path.move(to: CGPoint(x: 9, y: 9))
        path.addLine(to: CGPoint(x: 15, y: 15))
        return path
    }
}

struct LucideAlertTriangleShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 12, y: 3.5))
        path.addLine(to: CGPoint(x: 2.5, y: 20))
        path.addLine(to: CGPoint(x: 21.5, y: 20))
        path.closeSubpath()
        path.move(to: CGPoint(x: 12, y: 9))
        path.addLine(to: CGPoint(x: 12, y: 14))
        path.move(to: CGPoint(x: 12, y: 17))
        path.addLine(to: CGPoint(x: 12.01, y: 17))
        return path
    }
}

struct LucideMoreHorizontalShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 5, y: 12))
        path.addLine(to: CGPoint(x: 5.01, y: 12))
        path.move(to: CGPoint(x: 12, y: 12))
        path.addLine(to: CGPoint(x: 12.01, y: 12))
        path.move(to: CGPoint(x: 19, y: 12))
        path.addLine(to: CGPoint(x: 19.01, y: 12))
        return path
    }
}

struct LucideHardDriveShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 2, y: 4, width: 20, height: 16), cornerSize: CGSize(width: 2, height: 2))
        path.move(to: CGPoint(x: 2, y: 12))
        path.addLine(to: CGPoint(x: 22, y: 12))
        path.move(to: CGPoint(x: 6, y: 16))
        path.addLine(to: CGPoint(x: 6.01, y: 16))
        path.move(to: CGPoint(x: 10, y: 16))
        path.addLine(to: CGPoint(x: 10.01, y: 16))
        return path
    }
}

struct LucideFolderCogShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 22, y: 19))
        path.addArc(tangent1End: CGPoint(x: 22, y: 20), tangent2End: CGPoint(x: 20, y: 20), radius: 2)
        path.addLine(to: CGPoint(x: 4, y: 20))
        path.addArc(tangent1End: CGPoint(x: 2, y: 20), tangent2End: CGPoint(x: 2, y: 18), radius: 2)
        path.addLine(to: CGPoint(x: 2, y: 5))
        path.addArc(tangent1End: CGPoint(x: 2, y: 3), tangent2End: CGPoint(x: 4, y: 3), radius: 2)
        path.addLine(to: CGPoint(x: 9, y: 3))
        path.addArc(tangent1End: CGPoint(x: 10.6, y: 3.2), tangent2End: CGPoint(x: 12, y: 5), radius: 2)
        path.addLine(to: CGPoint(x: 13, y: 6))
        path.addLine(to: CGPoint(x: 20, y: 6))
        path.addArc(tangent1End: CGPoint(x: 22, y: 6), tangent2End: CGPoint(x: 22, y: 8), radius: 2)
        path.addLine(to: CGPoint(x: 22, y: 12))
        path.addEllipse(in: CGRect(x: 16, y: 14, width: 4, height: 4))
        path.move(to: CGPoint(x: 18, y: 12))
        path.addLine(to: CGPoint(x: 18, y: 13))
        path.move(to: CGPoint(x: 18, y: 19))
        path.addLine(to: CGPoint(x: 18, y: 20))
        path.move(to: CGPoint(x: 14, y: 16))
        path.addLine(to: CGPoint(x: 15, y: 16))
        path.move(to: CGPoint(x: 21, y: 16))
        path.addLine(to: CGPoint(x: 22, y: 16))
        return path
    }
}

struct LucideCloudShape: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 17.5, y: 19))
        path.addArc(tangent1End: CGPoint(x: 22, y: 19), tangent2End: CGPoint(x: 22, y: 14.5), radius: 4.5)
        path.addArc(tangent1End: CGPoint(x: 22, y: 10), tangent2End: CGPoint(x: 17.5, y: 10), radius: 4.5)
        path.addArc(
            center: CGPoint(x: 12, y: 10),
            radius: 6,
            startAngle: .degrees(0),
            endAngle: .degrees(180),
            clockwise: true
        )
        path.addArc(tangent1End: CGPoint(x: 2, y: 10), tangent2End: CGPoint(x: 2, y: 14.5), radius: 4.5)
        path.addArc(tangent1End: CGPoint(x: 2, y: 19), tangent2End: CGPoint(x: 6.5, y: 19), radius: 4.5)
        path.addLine(to: CGPoint(x: 17.5, y: 19))
        return path
    }
}

struct LucideRefreshCcw: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: 12, y: 12),
            radius: 9,
            startAngle: .degrees(45),
            endAngle: .degrees(315),
            clockwise: true
        )
        path.move(to: CGPoint(x: 21, y: 3))
        path.addLine(to: CGPoint(x: 21, y: 9))
        path.addLine(to: CGPoint(x: 15, y: 9))
        return path
    }
}

struct LucideClock: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: 12, y: 12),
            radius: 10,
            startAngle: .zero,
            endAngle: .degrees(360),
            clockwise: false
        )
        path.move(to: CGPoint(x: 12, y: 6))
        path.addLine(to: CGPoint(x: 12, y: 12))
        path.addLine(to: CGPoint(x: 16, y: 14))
        return path
    }
}

struct LucideFilePlus2: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 4, y: 22))
        path.addLine(to: CGPoint(x: 4, y: 2))
        path.addLine(to: CGPoint(x: 14, y: 2))
        path.addLine(to: CGPoint(x: 20, y: 8))
        path.addLine(to: CGPoint(x: 20, y: 22))
        path.closeSubpath()
        path.move(to: CGPoint(x: 14, y: 2))
        path.addLine(to: CGPoint(x: 14, y: 8))
        path.addLine(to: CGPoint(x: 20, y: 8))
        path.move(to: CGPoint(x: 9, y: 15))
        path.addLine(to: CGPoint(x: 15, y: 15))
        path.move(to: CGPoint(x: 12, y: 12))
        path.addLine(to: CGPoint(x: 12, y: 18))
        return path
    }
}

struct LucideFolderOpen: Shape {
    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 2, y: 20))
        path.addLine(to: CGPoint(x: 2, y: 4))
        path.addLine(to: CGPoint(x: 10, y: 4))
        path.addLine(to: CGPoint(x: 12, y: 6))
        path.addLine(to: CGPoint(x: 22, y: 6))
        path.addLine(to: CGPoint(x: 22, y: 10))
        path.move(to: CGPoint(x: 2, y: 20))
        path.addLine(to: CGPoint(x: 5, y: 10))
        path.addLine(to: CGPoint(x: 23, y: 10))
        path.addLine(to: CGPoint(x: 20, y: 20))
        path.closeSubpath()
        return path
    }
}
