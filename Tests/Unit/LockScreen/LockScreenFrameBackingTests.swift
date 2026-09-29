import CoreVideo
import IOSurface
import QuartzCore
import XCTest

@testable import WallpaperMachine

final class LockScreenFrameBackingTests: XCTestCase {
  private func frame(_ blue: UInt8) throws -> IOSurface {
    let surface = try XCTUnwrap(IOSurface(properties: [
      .width: 2, .height: 2, .bytesPerElement: 4, .pixelFormat: kCVPixelFormatType_32BGRA,
    ]))
    surface.lock(options: [], seed: nil)
    for row in 0..<2 {
      let pixels = surface.baseAddress.advanced(by: row * surface.bytesPerRow)
        .assumingMemoryBound(to: UInt8.self)
      for column in 0..<2 {
        pixels[column * 4] = blue
        pixels[column * 4 + 1] = 47
        pixels[column * 4 + 2] = 83
        pixels[column * 4 + 3] = 255
      }
    }
    surface.unlock(options: [], seed: nil)
    return surface
  }

  func testAnUnavailableDrawableExposesFramePixelsNotTheHostBackground() throws {
    let root = CALayer()
    root.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
    let metal = CAMetalLayer()
    metal.frame = root.bounds
    metal.isOpaque = false
    root.addSublayer(metal)
    try LockScreenFrameBacking.install(frame(19), on: root)
    let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2,
      bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(root.bounds)
    root.render(in: context)
    let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
    XCTAssertEqual(Array(UnsafeBufferPointer(start: pixels, count: 4)), [19, 47, 83, 255])
    XCTAssertNil(root.animationKeys(), "Installing readiness pixels must not crossfade from an empty frame")
  }

  func testReplacingTheBackingReleasesOldPixelsAndKeepsTheNewFrameAlive() throws {
    let root = CALayer()
    weak var previous: IOSurface?
    weak var current: IOSurface?
    try autoreleasepool {
      let surface = try frame(19)
      previous = surface
      try LockScreenFrameBacking.install(surface, on: root)
    }
    XCTAssertNotNil(previous)
    try autoreleasepool {
      let surface = try frame(101)
      current = surface
      try LockScreenFrameBacking.install(surface, on: root)
    }
    XCTAssertNil(previous)
    XCTAssertNotNil(current)
    let image = try XCTUnwrap(root.contents) as! CGImage
    let bytes = try XCTUnwrap(image.dataProvider?.data)
    XCTAssertEqual(CFDataGetBytePtr(bytes)?[0], 101)
  }
}
