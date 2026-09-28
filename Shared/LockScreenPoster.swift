import CoreGraphics
import Foundation
import IOSurface

/// Displays an immutable BGRA snapshot without allocating a second pixel buffer.
enum LockScreenPoster {
  static func image(from surface: IOSurface) -> CGImage? {
    guard surface.pixelFormat == 0x4247_5241, surface.bytesPerElement == 4,
      surface.width > 0, surface.height > 0,
      surface.lock(options: .readOnly, seed: nil) == 0
    else { return nil }

    // The image owns this read lock and retains the surface. Replacing the
    // latest snapshot cannot free the pixels Core Animation still displays.
    let pixels = Data(
      bytesNoCopy: surface.baseAddress, count: surface.bytesPerRow * surface.height,
      deallocator: .custom { [surface] _, _ in
        surface.unlock(options: .readOnly, seed: nil)
      })
    guard let provider = CGDataProvider(data: pixels as CFData) else { return nil }
    return CGImage(
      width: surface.width, height: surface.height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: surface.bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
        | CGBitmapInfo.byteOrder32Little.rawValue), provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }
}
