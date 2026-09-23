//
//  PlantCard.swift
//  plant-alert
//

import SwiftUI

/// One plant in the main list.
///
/// The tap-to-open area and the water button are deliberately separate hit
/// targets rather than a `NavigationLink` wrapping a `Button`, which swallows
/// the button's taps.
struct PlantCard: View {
    let plant: Plant
    let onOpen: () -> Void
    let onWater: () -> Void

    private var status: WateringStatus { plant.status() }
    private var tint: Color { PlantAppearance.color(named: plant.colorName) }

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onOpen) {
                HStack(spacing: 14) {
                    PlantAvatar(plant: plant)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(plant.name.isEmpty ? "Unnamed plant" : plant.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        StatusBadge(status: status)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            WaterButton(tint: tint, isHighlighted: status.needsWater, action: onWater)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .overlay {
            // Only nudge attention when something actually needs doing.
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(status.needsWater ? tint.opacity(0.35) : .clear, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var subtitle: String {
        [plant.room, plant.species]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// Circular droplet button used on the card and in the detail header.
struct WaterButton: View {
    let tint: Color
    var isHighlighted: Bool = true
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "drop.fill")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(isHighlighted ? .white : tint)
                .frame(width: size, height: size)
                .background {
                    Circle().fill(isHighlighted ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.14)))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Water this plant")
    }
}
