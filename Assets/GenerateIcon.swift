import AppKit

// 使用矢量路径绘制图标，每个尺寸单独渲染。
func render(size: Int, to url: URL) throws {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else { throw NSError(domain: "图标", code: 1) }
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
  let tile = NSBezierPath(
    roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
  NSGradient(
    starting: NSColor(srgbRed: 0.18, green: 0.68, blue: 0.91, alpha: 1),
    ending: NSColor(srgbRed: 0.08, green: 0.27, blue: 0.66, alpha: 1))!.draw(in: tile, angle: -65)
  NSColor(srgbRed: 0.04, green: 0.14, blue: 0.30, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 188, y: 294, width: 648, height: 472), xRadius: 62, yRadius: 62
  ).fill()
  NSColor(srgbRed: 0.83, green: 0.95, blue: 1, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 210, y: 316, width: 604, height: 428), xRadius: 42, yRadius: 42
  ).fill()
  NSColor(srgbRed: 0.05, green: 0.19, blue: 0.38, alpha: 1).setFill()
  NSBezierPath(
    roundedRect: NSRect(x: 234, y: 342, width: 556, height: 376), xRadius: 24, yRadius: 24
  ).fill()
  NSColor(srgbRed: 0.69, green: 0.94, blue: 1, alpha: 1).setFill()
  NSBezierPath(roundedRect: NSRect(x: 476, y: 220, width: 72, height: 84), xRadius: 14, yRadius: 14)
    .fill()
  NSBezierPath(
    roundedRect: NSRect(x: 376, y: 196, width: 272, height: 32), xRadius: 16, yRadius: 16
  ).fill()
  for (x, y, opacity) in [
    (348.0, 462.0, 0.40), (348, 546, 0.65), (432, 462, 0.65), (432, 546, 1.0),
  ] {
    NSColor(srgbRed: 0.35, green: 0.90, blue: 0.85, alpha: opacity).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 62, height: 62), xRadius: 12, yRadius: 12)
      .fill()
  }
  let arrow = NSBezierPath()
  arrow.move(to: NSPoint(x: 548, y: 470))
  arrow.line(to: NSPoint(x: 664, y: 586))
  arrow.move(to: NSPoint(x: 568, y: 586))
  arrow.line(to: NSPoint(x: 664, y: 586))
  arrow.line(to: NSPoint(x: 664, y: 490))
  arrow.lineWidth = 26
  arrow.lineCapStyle = .round
  arrow.lineJoinStyle = .round
  NSColor.white.setStroke()
  arrow.stroke()
  NSGraphicsContext.restoreGraphicsState()
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "图标", code: 2)
  }
  try png.write(to: url)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
  try render(size: points, to: directory.appendingPathComponent("icon_\(points)x\(points).png"))
  try render(
    size: points * 2, to: directory.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
