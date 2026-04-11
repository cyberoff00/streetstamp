//
//  PhotoEditorView.swift
//  StreetStamps
//
//  Pure crop editor: 3:4 (portrait) or 4:3 (landscape) with rule-of-thirds grid.
//  Pinch to zoom, drag to pan.
//

import SwiftUI
import UIKit

// MARK: - PhotoInputFlow

enum PhotoInputMode: Identifiable {
    case camera(mirrorSelfie: Bool)
    case library(selectionLimit: Int)

    var id: String {
        switch self {
        case .camera: return "camera"
        case .library: return "library"
        }
    }
}

/// Single fullScreenCover that transitions picker → crop editor in-place.
struct PhotoInputFlowView: View {
    let mode: PhotoInputMode
    let onComplete: ([UIImage]) -> Void
    let onCancel: () -> Void

    @State private var pickedImages: [UIImage]? = nil

    var body: some View {
        if let images = pickedImages {
            PhotoEditorView(
                images: images,
                onComplete: onComplete,
                onCancel: onCancel
            )
            .transition(.opacity)
        } else {
            switch mode {
            case .camera:
                FilmCameraView(
                    onCapture: { image in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            pickedImages = [image]
                        }
                    },
                    onDismiss: onCancel,
                    availablePresets: FilmCameraDropManager.availablePresets()
                )
                .ignoresSafeArea()
            case .library(let limit):
                PhotoLibraryPicker(
                    selectionLimit: limit,
                    skipDismiss: true,
                    onImages: { images in
                        guard !images.isEmpty else {
                            onCancel()
                            return
                        }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            pickedImages = images
                        }
                    },
                    onCancel: onCancel
                )
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - PhotoEditorView (Queue Entry Point)

struct PhotoEditorView: View {
    let images: [UIImage]
    let onComplete: ([UIImage]) -> Void
    let onCancel: () -> Void

    @State private var currentIndex = 0
    @State private var results: [UIImage] = []

    var body: some View {
        if currentIndex < images.count {
            PhotoCropEditor(
                image: images[currentIndex],
                queueLabel: images.count > 1 ? "\(currentIndex + 1)/\(images.count)" : nil,
                onDone: { cropped in
                    results.append(cropped)
                    advance()
                },
                onCancel: onCancel
            )
            .id(currentIndex)
        }
    }

    private func advance() {
        if currentIndex + 1 < images.count {
            currentIndex += 1
        } else {
            onComplete(results)
        }
    }
}

// MARK: - Single-Image Crop Editor

private struct PhotoCropEditor: View {
    let image: UIImage
    let queueLabel: String?
    let onDone: (UIImage) -> Void
    let onCancel: () -> Void

    // Layout
    private var imgSize: CGSize { image.size }
    private var isPortrait: Bool { imgSize.height >= imgSize.width }
    private var cropAspect: CGFloat { isPortrait ? 3.0 / 4.0 : 4.0 / 3.0 }

    private var canvasWidth: CGFloat {
        let sw = UIScreen.main.bounds.width
        let sh = UIScreen.main.bounds.height
        let maxH = sh - 180
        let naturalH = sw / cropAspect
        return naturalH > maxH ? maxH * cropAspect : sw
    }
    private var canvasHeight: CGFloat { canvasWidth / cropAspect }

    private var baseScale: CGFloat {
        guard imgSize.width > 0, imgSize.height > 0 else { return 1 }
        return max(canvasWidth / imgSize.width, canvasHeight / imgSize.height)
    }

    // Crop state
    @State private var zoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    // Computed
    private var displayW: CGFloat { imgSize.width * baseScale * zoom }
    private var displayH: CGFloat { imgSize.height * baseScale * zoom }
    private var maxOffX: CGFloat { max(0, (displayW - canvasWidth) / 2) }
    private var maxOffY: CGFloat { max(0, (displayH - canvasHeight) / 2) }

    private func clamped(_ off: CGSize) -> CGSize {
        CGSize(
            width:  min(max(off.width,  -maxOffX), maxOffX),
            height: min(max(off.height, -maxOffY), maxOffY)
        )
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                Spacer(minLength: 12)

                canvas

                Spacer(minLength: 12)
            }
        }
        .statusBarHidden()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button(action: onCancel) {
                Text(L10n.t("cancel"))
                    .font(.system(size: 17))
                    .foregroundColor(.white)
            }

            Spacer()

            if let label = queueLabel {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            Button {
                onDone(renderCroppedImage())
            } label: {
                Text(L10n.t("done"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        let vis = clamped(offset)

        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: displayW, height: displayH)
                .offset(vis)

            cropGrid
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .clipped()
        .contentShape(Rectangle())
        .gesture(cropGesture)
        .overlay(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Crop Grid (Rule of Thirds)

    private var cropGrid: some View {
        ZStack {
            ForEach(1..<3, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 0.5)
                    .offset(x: canvasWidth * CGFloat(i) / 3.0 - canvasWidth / 2)
            }
            ForEach(1..<3, id: \.self) { i in
                Rectangle()
                    .fill(Color.white.opacity(0.25))
                    .frame(height: 0.5)
                    .offset(y: canvasHeight * CGFloat(i) / 3.0 - canvasHeight / 2)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Gesture

    private var cropGesture: some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width:  lastOffset.width  + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                offset = clamped(offset)
                lastOffset = offset
            }

        let magnify = MagnificationGesture()
            .onChanged { value in
                zoom = min(max(1.0, lastZoom * value), 5.0)
            }
            .onEnded { value in
                zoom = min(max(1.0, lastZoom * value), 5.0)
                lastZoom = zoom
                offset = clamped(offset)
                lastOffset = offset
            }

        return SimultaneousGesture(drag, magnify)
    }

    // MARK: - Render

    private func renderCroppedImage() -> UIImage {
        let clampedOff = clamped(offset)
        let totalScale = baseScale * zoom

        let centerX = imgSize.width  / 2 - clampedOff.width  / totalScale
        let centerY = imgSize.height / 2 - clampedOff.height / totalScale

        let visW = canvasWidth  / totalScale
        let visH = canvasHeight / totalScale

        let maxDim: CGFloat = 2048
        let cap = min(maxDim / max(visW, visH), 1.0)
        let finalSize = CGSize(width: ceil(visW * cap), height: ceil(visH * cap))

        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true

        return UIGraphicsImageRenderer(size: finalSize, format: fmt).image { _ in
            let drawScale = finalSize.width / visW
            let drawW = imgSize.width  * drawScale
            let drawH = imgSize.height * drawScale
            let drawX = finalSize.width  / 2 - centerX * drawScale
            let drawY = finalSize.height / 2 - centerY * drawScale

            image.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        }
    }
}
