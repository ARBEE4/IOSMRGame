//
//  PhotoViewer.swift
//  game
//
//  Shows one album photo full screen, like the iPhone Photos app.
//  Opened by tapping a photo in AlbumView (when not in select mode).
//    - pinch with two fingers to zoom in (up to 4×) or out
//    - double-tap to zoom in, double-tap again to go back
//    - drag to move around while zoomed in
//    - swipe down (when not zoomed) or tap Done to close
//

import SwiftUI  // SwiftUI views and gestures
import UIKit    // UIImage

struct PhotoViewer: View {
    let photo: AlbumPhoto                              // which photo to show
    @Environment(\.dismiss) private var dismiss        // closes this full-screen view

    @State private var image: UIImage?                 // the full-size picture; nil until it's loaded
    @State private var scale: CGFloat = 1              // zoom right now (1 = the whole photo fits the screen)
    @State private var scaleAtStart: CGFloat = 1       // zoom when the current pinch started
    @State private var offset: CGSize = .zero          // how far the zoomed photo is moved
    @State private var offsetAtStart: CGSize = .zero   // the move when the current drag started

    private let maxScale: CGFloat = 4                  // biggest zoom
    private let doubleTapScale: CGFloat = 2.5          // zoom after a double tap

    var body: some View {
        ZStack {
            Color.black                                // black background, like Photos
                .ignoresSafeArea()

            if let image {                             // loaded?
                GeometryReader { geo in                // geo.size = the screen size (needed to limit the drag)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()                 // at 1× the whole photo fits the screen
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)            // zoom
                        .offset(offset)                // move while zoomed
                        .gesture(pinchGesture(in: geo.size).simultaneously(with: dragGesture(in: geo.size)))  // pinch and drag can happen together
                        .onTapGesture(count: 2) {      // double tap
                            toggleZoom()
                        }
                }
                .ignoresSafeArea()                     // the photo may use the whole screen, like Photos
            } else {                                   // still loading
                ProgressView()
                    .tint(.white)
            }
        }
        .overlay(alignment: .top) {                    // the bar at the top: date + Done
            topBar
        }
        .task {                                        // runs once when the viewer opens
            await loadImage()
        }
    }

    // The bar at the top: when the photo was taken, and Done
    private var topBar: some View {
        HStack {
            Text(photo.dateTaken.formatted(date: .abbreviated, time: .shortened))  // e.g. "27 Oct 2026, 14:05"
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Button("Done") {                           // close button
                dismiss()
            }
            .font(.headline)
            .foregroundStyle(.white)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.5))        // see-through dark strip, so the text stays readable on any photo
    }

    // Two fingers: zoom
    private func pinchGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in                                   // while pinching
                var newScale = scaleAtStart * value.magnification   // zoom at the start × how far the fingers spread
                if newScale > maxScale {                            // not bigger than 4×
                    newScale = maxScale
                }
                if newScale < 0.8 {                                 // a little smaller than 1× is allowed while pinching (it springs back)
                    newScale = 0.8
                }
                scale = newScale
                offset = clampedOffset(offset, scale: newScale, in: size)   // keep the photo on the screen
            }
            .onEnded { _ in                                         // fingers lifted
                withAnimation(.easeOut(duration: 0.2)) {
                    if scale < 1 {                                  // smaller than the screen → spring back
                        scale = 1
                        offset = .zero
                    }
                }
                scaleAtStart = scale                                // the next pinch starts from here
                offsetAtStart = offset
            }
    }

    // One finger: move the zoomed photo, or swipe down to close when not zoomed
    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in                                   // while dragging
                if scale > 1 {                                      // only when zoomed in
                    let proposed = CGSize(width: offsetAtStart.width + value.translation.width,
                                          height: offsetAtStart.height + value.translation.height)  // where the finger moved it
                    offset = clampedOffset(proposed, scale: scale, in: size)                       // but not off the screen
                }
            }
            .onEnded { value in                                     // finger lifted
                if scale <= 1 && value.translation.height > 120 {   // not zoomed + swiped down far enough
                    dismiss()                                       // close, like Photos
                }
                offsetAtStart = offset                              // the next drag starts from here
            }
    }

    // Double tap: zoomed in → back to 1×; not zoomed → zoom in to 2.5×
    private func toggleZoom() {
        withAnimation(.easeInOut(duration: 0.25)) {
            if scale > 1 {                                          // zoomed in?
                scale = 1                                           // → back to the whole photo
                offset = .zero
            } else {                                                // not zoomed
                scale = doubleTapScale                              // → zoom in
            }
        }
        scaleAtStart = scale                                        // the next pinch starts from here
        offsetAtStart = offset
    }

    // Keep the zoomed photo from being dragged off the screen.
    // At 2× the photo is twice as big, so it may move half a screen each way; at 1× it may not move at all.
    private func clampedOffset(_ proposed: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let maxX = (scale - 1) * size.width / 2             // how far it may move left / right
        let maxY = (scale - 1) * size.height / 2            // how far it may move up / down
        var result = proposed
        if maxX <= 0 {                                      // not zoomed in
            result.width = 0
        } else if result.width > maxX {
            result.width = maxX
        } else if result.width < -maxX {
            result.width = -maxX
        }
        if maxY <= 0 {
            result.height = 0
        } else if result.height > maxY {
            result.height = maxY
        } else if result.height < -maxY {
            result.height = -maxY
        }
        return result
    }

    // Read the photo file, then decode it in the background before showing it (so opening stays smooth)
    private func loadImage() async {
        if let full = UIImage(contentsOfFile: photo.url.path(percentEncoded: false)) {   // read the file
            if let ready = await full.byPreparingForDisplay() {                      // decode it in the background
                image = ready
            } else {                                                                 // couldn't prepare → show it as it is
                image = full
            }
        }
    }
}
