import AppKit
import CryptoKit
import Foundation
import PerchCore

/// Decodes album art off the main thread, downsampled to the size actually drawn.
///
/// Artwork arrives as a few hundred kilobytes of JPEG at whatever resolution the player felt like
/// — commonly 600x600 or larger, for a view perhaps 40 points across. Handing that straight to
/// SwiftUI decodes it at full size on the main thread, on every track change. This decodes once,
/// at the size needed, away from the main actor.
///
/// The cache is keyed on a hash of the bytes rather than the track title: the same album art can
/// arrive under different metadata, and different art can share a title.
public actor ArtworkCache {

    public static let shared = ArtworkCache()

    /// How many decoded covers to keep.
    ///
    /// Small on purpose: album art is only ever needed for what is playing now and perhaps what
    /// just played, so holding more is holding megabytes for no reason.
    private static let capacity = 8

    private var entries: [String: NSImage] = [:]
    private var order: [String] = []

    public init() {}

    /// Decode artwork, downsampled so its longest edge is `maximumDimension` points.
    ///
    /// - Returns: the image, or nil if the data is not an image at all.
    public func image(for data: Data, maximumDimension: CGFloat, scale: CGFloat) -> NSImage? {
        let pixels = max(1, Int((maximumDimension * scale).rounded()))
        let key = "\(Self.digest(data)):\(pixels)"

        if let cached = entries[key] {
            touch(key)
            return cached
        }

        guard let image = Self.decode(data, maximumPixelSize: pixels) else { return nil }
        store(image, for: key)
        return image
    }

    // MARK: - Decoding

    private static func decode(_ data: Data, maximumPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        // ImageIO downsamples during decode rather than after, so a 3000px JPEG never becomes a
        // 3000px bitmap in memory in the first place.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]

        guard
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        return NSImage(
            cgImage: thumbnail,
            size: NSSize(width: thumbnail.width, height: thumbnail.height)
        )
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Eviction

    private func store(_ image: NSImage, for key: String) {
        entries[key] = image
        order.append(key)
        while order.count > Self.capacity, let oldest = order.first {
            order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }

    private func touch(_ key: String) {
        guard let index = order.firstIndex(of: key) else { return }
        order.remove(at: index)
        order.append(key)
    }
}
