//
//  PlantImage.swift
//  plant-alert
//

import Foundation
import UIKit

/// Preparing and decoding plant photos.
///
/// Photos are downscaled before they are ever stored: an iPhone original is
/// 3–8 MB, which is wasteful to keep on device and slow to push through a free
/// Storage tier for an image that is only ever shown in a circle.
enum PlantImage {
    /// Long edge, in pixels, of a stored photo.
    static let maxDimension: CGFloat = 1024
    static let compressionQuality: CGFloat = 0.8

    /// Downscales and re-encodes picked image data, or returns `nil` if the
    /// bytes aren't a decodable image.
    static func prepared(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return encode(downscaled(image))
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longEdge = max(image.size.width, image.size.height)
        guard longEdge > maxDimension else { return image }

        let scale = maxDimension / longEdge
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        // Points, not screen pixels: the size above is already in final pixels.
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private static func encode(_ image: UIImage) -> Data? {
        image.jpegData(compressionQuality: compressionQuality)
    }

    // MARK: - Decoding

    /// Decoded images, keyed by storage path.
    ///
    /// Without this, scrolling the list re-decodes a JPEG for every avatar on
    /// every pass. Paths carry a fresh UUID per photo, so an entry can never go
    /// stale — a replaced photo simply has a different key.
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        return cache
    }()

    static func decoded(data: Data?, key: String?) -> UIImage? {
        guard let data else { return nil }
        guard let key else { return UIImage(data: data) }

        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    /// A fresh storage path for a plant's photo.
    ///
    /// The UUID suffix is what makes a replacement visible to the other phone
    /// and keeps the decode cache honest.
    static func storagePath(plantID: UUID, householdID: String) -> String {
        "\(sanitized(householdID))/\(plantID.uuidString)-\(UUID().uuidString).jpg"
    }

    /// Household codes are user-chosen, so keep them to characters that need no
    /// escaping in a URL path.
    private static func sanitized(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let cleaned = String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return cleaned.isEmpty ? "shared" : cleaned
    }
}
