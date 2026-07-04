import AppKit
import Foundation

struct IconStyle {
    static let size: CGFloat = 1024
    static let cornerRadius: CGFloat = 94
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: x, y: y, width: width, height: height)
}

func ellipse(_ center: CGPoint, _ radius: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: rect(center.x - radius, center.y - radius, radius * 2, radius * 2))
}

func strokeEllipse(center: CGPoint, radius: CGFloat, color: NSColor, width: CGFloat) {
    color.setStroke()
    let path = ellipse(center, radius)
    path.lineWidth = width
    path.stroke()
}

func drawSoftShadow(path: NSBezierPath, color: NSColor, blur: CGFloat, offset: CGSize) {
    NSGraphicsContext.saveGraphicsState()
    NSShadow().apply {
        $0.shadowColor = color
        $0.shadowBlurRadius = blur
        $0.shadowOffset = offset
    }
    NSColor.black.withAlphaComponent(0.001).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
}

extension NSShadow {
    func apply(_ configure: (NSShadow) -> Void) {
        configure(self)
        set()
    }
}

let output = CommandLine.arguments.dropFirst().first ?? "icon-master.png"
let size = IconStyle.size
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Could not create drawing context")
}
context.setShouldAntialias(true)
context.setAllowsAntialiasing(true)

let canvas = rect(0, 0, size, size)
let roundedCanvas = NSBezierPath(roundedRect: canvas, xRadius: IconStyle.cornerRadius, yRadius: IconStyle.cornerRadius)
roundedCanvas.addClip()

NSGradient(colors: [
    NSColor(calibratedRed: 0.93, green: 0.88, blue: 0.82, alpha: 1),
    NSColor(calibratedRed: 0.77, green: 0.74, blue: 0.77, alpha: 1),
    NSColor(calibratedRed: 0.50, green: 0.49, blue: 0.53, alpha: 1)
])?.draw(in: canvas, angle: -42)

let halo = NSBezierPath(ovalIn: rect(-140, 520, 650, 650))
NSGradient(colors: [
    NSColor.white.withAlphaComponent(0.48),
    NSColor.white.withAlphaComponent(0.00)
])?.draw(in: halo, relativeCenterPosition: NSPoint(x: -0.25, y: 0.2))

let base = NSBezierPath(roundedRect: rect(110, 118, 804, 760), xRadius: 178, yRadius: 178)
drawSoftShadow(path: base, color: NSColor.black.withAlphaComponent(0.28), blur: 46, offset: CGSize(width: 0, height: -26))
NSGradient(colors: [
    NSColor(calibratedRed: 0.98, green: 0.94, blue: 0.88, alpha: 1),
    NSColor(calibratedRed: 0.75, green: 0.72, blue: 0.74, alpha: 1)
])?.draw(in: base, angle: -58)
NSColor.white.withAlphaComponent(0.80).setStroke()
base.lineWidth = 7
base.stroke()

let recordCenter = CGPoint(x: 508, y: 502)
let platter = ellipse(recordCenter, 323)
drawSoftShadow(path: platter, color: NSColor.black.withAlphaComponent(0.38), blur: 34, offset: CGSize(width: 0, height: -16))
NSGradient(colors: [
    NSColor(calibratedWhite: 0.50, alpha: 1),
    NSColor(calibratedWhite: 0.20, alpha: 1),
    NSColor(calibratedWhite: 0.72, alpha: 1)
])?.draw(in: platter, relativeCenterPosition: NSPoint(x: -0.28, y: 0.38))

let record = ellipse(recordCenter, 286)
NSGradient(colors: [
    NSColor(calibratedWhite: 0.03, alpha: 1),
    NSColor(calibratedWhite: 0.18, alpha: 1),
    NSColor(calibratedWhite: 0.02, alpha: 1)
])?.draw(in: record, relativeCenterPosition: NSPoint(x: -0.33, y: 0.42))

for index in 0..<54 {
    let radius = CGFloat(84 + index * 4)
    let alpha = index % 3 == 0 ? 0.20 : 0.10
    strokeEllipse(center: recordCenter, radius: radius, color: NSColor.white.withAlphaComponent(alpha), width: 1)
}

for index in 0..<38 {
    let radius = CGFloat(92 + index * 6)
    strokeEllipse(center: recordCenter, radius: radius, color: NSColor.black.withAlphaComponent(0.27), width: 0.7)
}

let highlight = NSBezierPath()
highlight.move(to: NSPoint(x: 265, y: 640))
highlight.curve(to: NSPoint(x: 602, y: 776), controlPoint1: NSPoint(x: 338, y: 735), controlPoint2: NSPoint(x: 501, y: 794))
NSColor.white.withAlphaComponent(0.18).setStroke()
highlight.lineWidth = 20
highlight.lineCapStyle = .round
highlight.stroke()

let label = ellipse(recordCenter, 98)
NSGradient(colors: [
    NSColor(calibratedRed: 0.99, green: 0.95, blue: 0.88, alpha: 1),
    NSColor(calibratedRed: 0.73, green: 0.70, blue: 0.66, alpha: 1)
])?.draw(in: label, angle: -55)
strokeEllipse(center: recordCenter, radius: 98, color: NSColor.black.withAlphaComponent(0.24), width: 3)

let spindle = ellipse(recordCenter, 18)
NSGradient(colors: [
    NSColor.white,
    NSColor(calibratedWhite: 0.08, alpha: 1)
])?.draw(in: spindle, relativeCenterPosition: NSPoint(x: -0.25, y: 0.3))
strokeEllipse(center: recordCenter, radius: 18, color: NSColor.black.withAlphaComponent(0.35), width: 2)

let pivotCenter = CGPoint(x: 788, y: 742)
for radius in stride(from: CGFloat(28), through: CGFloat(62), by: CGFloat(15)) {
    strokeEllipse(center: pivotCenter, radius: radius, color: NSColor.white.withAlphaComponent(0.58), width: 2.4)
    strokeEllipse(center: pivotCenter, radius: radius - 4, color: NSColor.black.withAlphaComponent(0.18), width: 1.2)
}

let armShadow = NSBezierPath()
armShadow.move(to: NSPoint(x: pivotCenter.x, y: pivotCenter.y))
armShadow.curve(to: NSPoint(x: 654, y: 385), controlPoint1: NSPoint(x: 768, y: 628), controlPoint2: NSPoint(x: 743, y: 453))
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.34)
shadow.shadowBlurRadius = 16
shadow.shadowOffset = CGSize(width: 8, height: -8)
shadow.set()
NSColor.black.withAlphaComponent(0.001).setStroke()
armShadow.lineWidth = 26
armShadow.lineCapStyle = .round
armShadow.stroke()
NSGraphicsContext.restoreGraphicsState()

let arm = NSBezierPath()
arm.move(to: NSPoint(x: pivotCenter.x, y: pivotCenter.y))
arm.curve(to: NSPoint(x: 654, y: 385), controlPoint1: NSPoint(x: 768, y: 626), controlPoint2: NSPoint(x: 744, y: 454))
NSColor(calibratedRed: 0.82, green: 0.79, blue: 0.76, alpha: 1).setStroke()
arm.lineWidth = 29
arm.lineCapStyle = .round
arm.stroke()
NSColor.white.withAlphaComponent(0.86).setStroke()
arm.lineWidth = 11
arm.stroke()

let head = NSBezierPath(roundedRect: rect(584, 333, 112, 78), xRadius: 10, yRadius: 10)
var transform = AffineTransform()
transform.translate(x: 640, y: 372)
transform.rotate(byDegrees: -39)
transform.translate(x: -640, y: -372)
head.transform(using: transform)
drawSoftShadow(path: head, color: NSColor.black.withAlphaComponent(0.30), blur: 12, offset: CGSize(width: 5, height: -6))
NSColor(calibratedRed: 0.78, green: 0.73, blue: 0.69, alpha: 1).setFill()
head.fill()
NSColor.black.withAlphaComponent(0.22).setStroke()
head.lineWidth = 2
head.stroke()

for point in [NSPoint(x: 613, y: 369), NSPoint(x: 645, y: 371), NSPoint(x: 676, y: 372)] {
    let dot = NSBezierPath(ovalIn: rect(point.x - 9, point.y - 9, 18, 18))
    var dotTransform = AffineTransform()
    dotTransform.translate(x: 640, y: 372)
    dotTransform.rotate(byDegrees: -39)
    dotTransform.translate(x: -640, y: -372)
    dot.transform(using: dotTransform)
    NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
    dot.fill()
}

let stylus = NSBezierPath()
stylus.move(to: NSPoint(x: 589, y: 319))
stylus.line(to: NSPoint(x: 620, y: 340))
stylus.line(to: NSPoint(x: 573, y: 286))
stylus.close()
NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
stylus.fill()

let topShine = NSBezierPath(roundedRect: rect(116, 135, 792, 738), xRadius: 171, yRadius: 171)
NSColor.white.withAlphaComponent(0.13).setStroke()
topShine.lineWidth = 3
topShine.stroke()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Could not encode PNG")
}

try png.write(to: URL(fileURLWithPath: output))
