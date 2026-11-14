// Puts a screenshot into the form of the App Store (docs/apple/release.md), for scripts/screenshots.sh:
// iPhone and iPad keep their size, without transparency; the Mac window goes on a background of 2560 × 1600 pixels,
// with rounded corners and a shadow, as App Store Connect takes 16:10 only.
// Usage: screenshot-image <iphone|ipad|duo|mac> <light|dark> <input.png> <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 5 else {
    FileHandle.standardError.write(Data("usage: screenshot-image <device> <light|dark> <input> <output>\n".utf8))
    exit(2)
}
let (kind, isDark, input, output) = (arguments[1], arguments[2] == "dark", arguments[3], arguments[4])

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    FileHandle.standardError.write(Data("screenshot-image: cannot read \(input)\n".utf8))
    exit(1)
}

/// The Mac's canvas, and the window's corner radius and margin on it, in pixels.
let macCanvas = CGSize(width: 2560, height: 1600)
let cornerRadius: CGFloat = 32
let margin: CGFloat = 80

let size = kind == "mac" ? macCanvas : CGSize(width: image.width, height: image.height)
guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { exit(1) }
// Without alpha: App Store Connect refuses transparent images.
guard
    let context = CGContext(
        data: nil,
        width: Int(size.width),
        height: Int(size.height),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
else { exit(1) }

if kind == "mac" {
    // A calm gradient in the colours of the appearance, behind the window.
    let colors =
        isDark
        ? [
            CGColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1),
            CGColor(red: 0.06, green: 0.06, blue: 0.06, alpha: 1),
        ]
        : [
            CGColor(red: 0.97, green: 0.95, blue: 0.92, alpha: 1),
            CGColor(red: 0.86, green: 0.84, blue: 0.81, alpha: 1),
        ]
    guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1]) else { exit(1) }
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: size.height),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
    // The window as large as fits within the margin, in the middle.
    let room = CGSize(width: size.width - 2 * margin, height: size.height - 2 * margin)
    let scale = min(1, room.width / CGFloat(image.width), room.height / CGFloat(image.height))
    let window = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    let frame = CGRect(
        x: ((size.width - window.width) / 2).rounded(),
        y: ((size.height - window.height) / 2).rounded(),
        width: window.width.rounded(),
        height: window.height.rounded()
    )
    let shape = CGPath(roundedRect: frame, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -16),
        blur: 60,
        color: CGColor(gray: 0, alpha: isDark ? 0.7 : 0.35)
    )
    context.addPath(shape)
    context.setFillColor(CGColor(gray: isDark ? 0.1 : 1, alpha: 1))
    context.fillPath()
    context.restoreGState()
    context.addPath(shape)
    context.clip()
    context.interpolationQuality = .high
    context.draw(image, in: frame)
} else {
    context.setFillColor(CGColor(gray: isDark ? 0 : 1, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    context.draw(image, in: CGRect(origin: .zero, size: size))
}

guard let result = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: output) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else { exit(1) }
CGImageDestinationAddImage(destination, result, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
