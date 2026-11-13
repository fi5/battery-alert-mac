import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let destination = CommandLine.arguments[1]
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setAllowsAntialiasing(true)
let panel = CGPath(roundedRect: CGRect(x: 80, y: 80, width: 864, height: 864), cornerWidth: 194, cornerHeight: 194, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.18))
context.addPath(panel)
context.setFillColor(CGColor(gray: 0.95, alpha: 1))
context.fillPath()
context.restoreGState()
context.saveGState()
context.addPath(panel)
context.clip()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(gray: 0.99, alpha: 1), CGColor(gray: 0.88, alpha: 1)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 944), end: CGPoint(x: 512, y: 80), options: [])
context.restoreGState()
context.setStrokeColor(CGColor(gray: 0.28, alpha: 1))
context.setLineWidth(38)
context.addPath(CGPath(roundedRect: CGRect(x: 171, y: 355, width: 637, height: 314), cornerWidth: 58, cornerHeight: 58, transform: nil))
context.strokePath()
context.setFillColor(CGColor(gray: 0.28, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 834, y: 446, width: 39, height: 132), cornerWidth: 17, cornerHeight: 17, transform: nil))
context.fillPath()
context.setFillColor(CGColor(red: 0.96, green: 0.22, blue: 0.20, alpha: 1))
context.addPath(CGPath(roundedRect: CGRect(x: 205, y: 389, width: 81, height: 246), cornerWidth: 27, cornerHeight: 27, transform: nil))
context.fillPath()
let image = context.makeImage()!
let output = CGImageDestinationCreateWithURL(URL(fileURLWithPath: destination) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, image, nil)
guard CGImageDestinationFinalize(output) else { exit(1) }
