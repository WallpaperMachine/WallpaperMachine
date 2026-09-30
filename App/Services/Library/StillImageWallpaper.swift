import Foundation
import ImageIO

/// A still picture packaged as a wallpaper. The renderer plays scene, video and web projects
/// only, so a picture becomes a `web` project: the image beside a small page that shows it,
/// with an Image fit and a Background color property the inspector edits. Pages saved from
/// pixiv and images imported from disk share this shape.
enum StillImageWallpaper {
    /// How the page meets the screen; the values of the manifest's `fit` combo.
    enum Fit: String, CaseIterable, Sendable {
        case fill, fillTop = "fill-top", blur, fit, center

        /// The option's label in the manifest. It stays English there, like every property
        /// label a wallpaper ships, and the panel translates these few.
        var label: String {
            switch self {
            case .fill: "Fill"
            case .fillTop: "Fill, keep the top"
            case .blur: "Fit with blurred backdrop"
            case .fit: "Fit"
            case .center: "Original size"
            }
        }

        /// Wide images fill the screen; anything squarer or taller is shown whole over a
        /// blurred copy of itself instead of losing most of its height.
        static func preferred(width: Int, height: Int) -> Fit {
            width * 5 >= height * 6 ? .fill : .blur
        }
    }

    static let entryFile = "index.html"
    static let previewFile = "preview.jpg"
    static let displayFile = "display.jpg"
    static let previewPixels = 512
    /// A web view decodes the whole image, so a picture larger than this on its long side is
    /// shown from a scaled copy and kept alongside it untouched.
    static let displayPixels = 8192

    /// The manifest's `general.properties`: the fit the page opens with and a black backdrop.
    static func properties(fit: Fit) -> [String: Any] {
        [
            "fit": [
                "order": 0, "text": "Image fit", "type": "combo", "value": fit.rawValue,
                "options": Fit.allCases.map { ["label": $0.label, "value": $0.rawValue] },
            ],
            "background": [
                "order": 1, "text": "Background color", "type": "color", "value": "0 0 0",
            ],
        ]
    }

    /// Width and height as the picture is shown, with its EXIF orientation applied; nil when
    /// ImageIO cannot read a size from the bytes.
    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0
        else { return nil }
        // Orientations 5 to 8 turn the picture a quarter, so its sides swap on screen.
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ? (height, width) : (width, height)
    }

    /// The wallpaper page. It holds no text from the picture's source; the only name in it is
    /// the image file the packager chose. The host replays `applyUserProperties` to a listener
    /// registered after load, and `data-fit` covers the first paint before that.
    static func page(showing file: String, fit: Fit) -> String {
        let original = legacyPage(showing: file, fit: fit)
        guard let start = original.range(of: "<script>"),
              let end = original.range(of: "</script>") else {
            preconditionFailure("The frozen still-image template must contain its property listener.")
        }
        let script = """
        <script>
        (() => {
          const fits = new Set(\(fitList));
          const art = document.getElementById('art');
          let placement = null;
          function renderPlacement() {
            art.style.cssText = '';
            if (!placement || !art.naturalWidth || !art.naturalHeight) return;
            const width = window.innerWidth, height = window.innerHeight;
            const fit = document.body.dataset.fit;
            const base = fit === 'center' ? 1 : Math[fit === 'fit' || fit === 'blur' ? 'min' : 'max'](
              width / art.naturalWidth, height / art.naturalHeight);
            const w = art.naturalWidth * base * placement.zoom;
            const h = art.naturalHeight * base * placement.zoom;
            Object.assign(art.style, {
              inset: 'auto', width: `${w}px`, height: `${h}px`, objectFit: 'fill',
              left: `${(width - w) * placement.x}px`, top: `${(height - h) * placement.y}px`,
            });
          }
          art.addEventListener('load', renderPlacement);
          window.addEventListener('resize', renderPlacement);
          window.wallpaperPropertyListener = {
            applyUserProperties(properties) {
              const fit = properties.fit && String(properties.fit.value);
              if (fits.has(fit)) document.body.dataset.fit = fit;
              const rgb = properties.background && String(properties.background.value).trim().split(/\\s+/).map(Number);
              if (rgb && rgb.length === 3 && rgb.every(Number.isFinite)) {
                document.body.style.background = `rgb(${rgb.map(part => Math.round(Math.min(1, Math.max(0, part)) * 255)).join(', ')})`;
              }
              const p = properties.\(StillImagePlacement.propertyKey)?.value;
              if (p) {
                placement = p.customized === true && [p.x, p.y, p.zoom].every(Number.isFinite)
                  && p.x >= 0 && p.x <= 1 && p.y >= 0 && p.y <= 1 && p.zoom >= 1 && p.zoom <= 3 ? p : null;
              }
              renderPlacement();
            },
          };
        })();
        </script>
        """
        return original.replacingCharacters(in: start.lowerBound..<end.upperBound, with: script)
    }

    /// Recognition of old app-generated pages is exact, not a substring or an ID-prefix
    /// heuristic. Keep this template frozen so an author's edited page is never rewritten.
    static func legacyPage(showing file: String, fit: Fit) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Still image</title>
        <style>
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: #000; }
        img { position: fixed; display: block; }
        #art { inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: 50% 50%; }
        #backdrop { display: none; inset: -8vmax; width: calc(100% + 16vmax); height: calc(100% + 16vmax); object-fit: cover; filter: blur(5vmax) brightness(0.72); }
        body[data-fit="fill-top"] #art { object-position: 50% 0; }
        body[data-fit="blur"] #art, body[data-fit="fit"] #art { object-fit: contain; }
        body[data-fit="blur"] #backdrop { display: block; }
        body[data-fit="center"] #art { object-fit: none; }
        </style>
        </head>
        <body data-fit="\(fit.rawValue)">
        <img id="backdrop" src="\(escapedAttribute(file))" alt="">
        <img id="art" src="\(escapedAttribute(file))" alt="">
        <script>
        (() => {
          const fits = new Set(\(fitList));
          window.wallpaperPropertyListener = {
            applyUserProperties(properties) {
              const fit = properties.fit && String(properties.fit.value);
              if (fits.has(fit)) document.body.dataset.fit = fit;
              const rgb = properties.background && String(properties.background.value).trim().split(/\\s+/).map(Number);
              if (rgb && rgb.length === 3 && rgb.every(Number.isFinite)) {
                document.body.style.background = `rgb(${rgb.map(part => Math.round(Math.min(1, Math.max(0, part)) * 255)).join(', ')})`;
              }
            },
          };
        })();
        </script>
        </body>
        </html>

        """
    }
    private static func escapedAttribute(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }


    private static var fitList: String {
        "[" + Fit.allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ") + "]"
    }
}
