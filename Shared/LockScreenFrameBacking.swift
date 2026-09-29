import CoreGraphics
import CoreVideo
import Foundation
import IOSurface
import QuartzCore

/// Keeps actual frame pixels in the remote layer tree when no Metal drawable is available.
enum LockScreenFrameBacking {
  static func install(_ surface: IOSurface, on root: CALayer) throws {
    guard surface.pixelFormat == kCVPixelFormatType_32BGRA, surface.bytesPerElement == 4,
      surface.width > 0, surface.height > 0,
      surface.lock(options: .readOnly, seed: nil) == 0
    else { throw CocoaError(.fileReadCorruptFile) }
    // The image retains the immutable snapshot and its read lock without another bitmap copy.
    let pixels = Data(bytesNoCopy: surface.baseAddress,
      count: surface.bytesPerRow * surface.height,
      deallocator: .custom { [surface] _, _ in surface.unlock(options: .readOnly, seed: nil) })
    guard let provider = CGDataProvider(data: pixels as CFData),
      let image = CGImage(width: surface.width, height: surface.height,
        bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: surface.bytesPerRow,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue), provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { throw CocoaError(.fileReadCorruptFile) }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    root.contents = image
    root.contentsGravity = .resize
    CATransaction.commit()
    // Readiness is a committed frame, not just a GPU readback. Waiting for
    // scanout here would deadlock: the host has not received this context yet.
    CATransaction.flush()
  }
}
