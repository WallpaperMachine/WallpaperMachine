import CoreGraphics
import IOSurface
import XCTest

@testable import WallpaperMachine

final class LockScreenPosterTests: XCTestCase {
  func testPosterKeepsSnapshotPixelsAliveUntilImageIsReleased() throws {
    weak var retainedSurface: IOSurface?
    var poster: CGImage?
    try autoreleasepool {
      let surface = try XCTUnwrap(IOSurface(properties: [
        .width: 2, .height: 2, .bytesPerElement: 4, .pixelFormat: 0x4247_5241,
      ]))
      retainedSurface = surface
      XCTAssertEqual(surface.lock(options: [], seed: nil), 0)
      let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
      for row in 0..<2 {
        for (column, value) in [UInt8(17), 29, 61, 255, 79, 83, 101, 255].enumerated() {
          bytes[row * surface.bytesPerRow + column] = value
        }
      }
      surface.unlock(options: [], seed: nil)
      poster = try XCTUnwrap(LockScreenPoster.image(from: surface))
    }

    // A copied bitmap would let this surface die immediately. Its continued
    // lifetime proves that the provider keeps the original storage alive.
    XCTAssertNotNil(retainedSurface)
    try autoreleasepool {
      let image = try XCTUnwrap(poster)
      let data = try XCTUnwrap(image.dataProvider?.data)
      let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
      XCTAssertEqual(image.width, 2)
      XCTAssertEqual(image.height, 2)
      XCTAssertEqual(Array(UnsafeBufferPointer(start: bytes, count: 8)),
                     [17, 29, 61, 255, 79, 83, 101, 255])
      XCTAssertEqual(bytes[image.bytesPerRow + 4], 79)
    }
    autoreleasepool { poster = nil }
    XCTAssertNil(retainedSurface, "The image must release its surface and read lock")
  }
}
