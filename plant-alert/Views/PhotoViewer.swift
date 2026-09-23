//
//  PhotoViewer.swift
//  plant-alert
//

import SwiftUI

/// Full-screen look at a plant's photo, with pinch-to-zoom and swipe-to-dismiss.
struct PhotoViewer: View {
    let image: UIImage
    let title: String

    @Environment(\.dismiss) private var dismiss

    /// Zoom while a pinch is in flight vs. what it settled on.
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var settledPan: CGSize = .zero
    /// How far a dismiss drag has got, used to fade the backdrop out with it.
    @State private var dismissOffset: CGSize = .zero

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 5

    private var isZoomedIn: Bool { zoom > 1.01 }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backdropOpacity)
                .ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Photo of \(title)")
                .scaleEffect(zoom)
                .offset(x: pan.width + dismissOffset.width, y: pan.height + dismissOffset.height)
                .gesture(magnification)
                .simultaneousGesture(drag)
                .onTapGesture(count: 2) { toggleZoom() }

            closeButton
        }
        .statusBarHidden()
        .animation(.snappy(duration: 0.25), value: zoom)
    }

    // MARK: - Chrome

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: .circle)
                }
                .accessibilityLabel("Close photo")
            }
            Spacer()
        }
        .padding(16)
        // Fades out with the backdrop so it doesn't hang over a dismissing photo.
        .opacity(backdropOpacity)
    }

    /// Dims towards transparent as the photo is dragged away.
    private var backdropOpacity: Double {
        let distance = abs(dismissOffset.height)
        return max(0.4, 1 - distance / 400)
    }

    // MARK: - Gestures

    private var magnification: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = clamped(settledZoom * value.magnification)
            }
            .onEnded { _ in
                settledZoom = zoom
                if !isZoomedIn { resetPan() }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                if isZoomedIn {
                    // Zoomed in, a drag pans the photo.
                    pan = CGSize(
                        width: settledPan.width + value.translation.width,
                        height: settledPan.height + value.translation.height
                    )
                } else {
                    // Zoomed out, it's a swipe to dismiss.
                    dismissOffset = value.translation
                }
            }
            .onEnded { value in
                if isZoomedIn {
                    settledPan = pan
                } else if abs(value.translation.height) > 120 {
                    dismiss()
                } else {
                    withAnimation(.snappy) { dismissOffset = .zero }
                }
            }
    }

    private func toggleZoom() {
        if isZoomedIn {
            zoom = 1
            settledZoom = 1
            resetPan()
        } else {
            zoom = 2.5
            settledZoom = 2.5
        }
    }

    private func resetPan() {
        pan = .zero
        settledPan = .zero
    }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, minZoom), maxZoom)
    }
}
