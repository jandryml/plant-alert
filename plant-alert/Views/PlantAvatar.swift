//
//  PlantAvatar.swift
//  plant-alert
//

import SwiftUI

/// The circle that stands in for a plant everywhere in the app: its photo when
/// it has one, otherwise a tinted symbol.
struct PlantAvatar: View {
    let symbolName: String
    let colorName: String
    var imageData: Data?
    /// Storage path, used only as the decode cache key.
    var imageKey: String?
    var size: CGFloat = 46

    private var tint: Color { PlantAppearance.color(named: colorName) }

    var body: some View {
        Group {
            if let photo = PlantImage.decoded(data: imageData, key: imageKey) {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(tint.gradient.opacity(0.18))
                    .overlay {
                        Image(systemName: PlantAppearance.symbol(named: symbolName))
                            .font(.system(size: size * 0.44, weight: .medium))
                            .foregroundStyle(tint)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay {
            Circle().strokeBorder(tint.opacity(0.28), lineWidth: 1)
        }
    }
}

/// Convenience for the common case of showing a stored plant.
extension PlantAvatar {
    init(plant: Plant, size: CGFloat = 46) {
        self.init(
            symbolName: plant.symbolName,
            colorName: plant.colorName,
            imageData: plant.imageData,
            imageKey: plant.imagePath,
            size: size
        )
    }
}

/// Small coloured pill describing when a plant is next due.
struct StatusBadge: View {
    let status: WateringStatus

    private var tint: Color {
        switch status {
        case .overdue: return .red
        case .dueToday: return .orange
        case .upcoming: return .secondary
        }
    }

    var body: some View {
        Text(status.shortText)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(status.needsWater ? 0.12 : 0.08), in: Capsule())
    }
}

#Preview {
    VStack(spacing: 16) {
        PlantAvatar(symbolName: "leaf.fill", colorName: "green")
        PlantAvatar(symbolName: "camera.macro", colorName: "pink", size: 72)
        StatusBadge(status: .overdue(days: 2))
        StatusBadge(status: .dueToday)
        StatusBadge(status: .upcoming(days: 3))
    }
    .padding()
}
