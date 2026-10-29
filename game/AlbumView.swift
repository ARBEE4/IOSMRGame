//
//  AlbumView.swift
//  game
//
//  The photo album ("memories"), opened by the Album button in CatDetailView.
//  Shows the photos saved by PhotoStore, grouped by day (newest day first).
//  Like the iPhone Photos app: tap Select, tick photos, then delete them together (trash, right button).
//  The Save button (left) is only the button for now; saving to the iPhone comes later.
//  Long-press a single photo to delete just that one.
//  Tap a photo (not in select mode) to open it full screen and zoom (PhotoViewer.swift).
//
//  TEMPORARY: the "Add test photo" button saves a sample picture, so the album can be
//  tested before the AR camera exists (Step B). Remove it (and makeTestImage) after Step B.
//

import SwiftUI  // SwiftUI views
import UIKit    // UIImage, UIColor, UIFont, UIGraphicsImageRenderer

// All the photos taken on one calendar day
struct PhotoDay: Identifiable {
    let day: Date               // that day (the moment it started, at midnight)
    var photos: [AlbumPhoto]    // the photos taken that day, newest first
    var id: Date { day }        // each day appears only once, so the day works as the id
}

// The photo album: shows the photos taken in AR, grouped by day
struct AlbumView: View {
    @Environment(\.dismiss) private var dismiss  // closes this sheet

    // the photos this screen shows (starts empty, filled from PhotoStore)
    @State private var photos: [AlbumPhoto] = []

    // ── Select mode (like the iPhone Photos app) ──
    @State private var isSelecting = false               // true = tapping a photo ticks it
    @State private var selectedIDs: Set<URL> = []         // the ticked photos' ids (a Set never holds the same id twice)
    @State private var showDeleteConfirm = false         // true = show the "Delete N photos?" question
    @State private var deleteCount = 0                   // how many photos the delete box asks about (remembered when the box opens)
    @State private var viewingPhoto: AlbumPhoto?         // the photo opened full screen (nil = none)

    // grid columns: as many as fit, each at least 100 points wide, 4 points apart
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        NavigationStack {                                                                  // gives a title bar with buttons
            Group {                                                                        // lets both branches below share the same modifiers
                if photos.isEmpty {                                                        // no photos yet
                    ContentUnavailableView(                                                // Apple's ready-made "nothing here yet" screen
                        "No memories yet",                                                 // big title
                        systemImage: "photo.on.rectangle.angled",                          // SF Symbol icon
                        description: Text("Take a photo in AR and it will show up here.")  // small text under the title
                    )
                } else {                                                                   // there are photos
                    ScrollView {                                                           // scrolls when there are many photos
                        LazyVStack(alignment: .leading, spacing: 16) {                     // one block per day, top to bottom
                            ForEach(photoDays) { photoDay in                               // one day at a time (newest day first)
                                Text(photoDay.day.formatted(date: .long, time: .omitted))  // the day as a heading, e.g. "26 October 2026"
                                    .font(.headline)
                                    .padding(.horizontal)

                                LazyVGrid(columns: columns, spacing: 4) {                  // that day's photos in a grid
                                    ForEach(photoDay.photos) { photo in                    // one photo at a time
                                        PhotoThumbnail(photo: photo, isSelected: selectedIDs.contains(photo.id))  // the small square; ticked if its id is in the Set
                                            .onTapGesture {                                // a normal tap on the square
                                                if isSelecting {                           // select mode
                                                    toggleSelection(photo)                 // tick / untick the photo that was tapped
                                                } else {                                   // normal mode
                                                    viewingPhoto = photo                   // open it full screen (PhotoViewer)
                                                }
                                            }
                                            .contextMenu {                                 // menu that appears on a long press
                                                Button("Delete", systemImage: "trash", role: .destructive) {  // red Delete item
                                                    PhotoStore.delete(photo)               // delete this photo's file
                                                    photos = PhotoStore.loadAll()          // reload the list
                                                }
                                            }
                                    }
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle(titleText)                                                    // "Memories", or "2 Selected" in select mode
            .navigationBarTitleDisplayMode(.inline)                                        // small title in the bar, like Photos
            .toolbar {                                                                     // buttons in the title bar
                if isSelecting {                                                           // ── select mode ──
                    ToolbarItem(placement: .topBarTrailing) {                              // top right
                        Button("Cancel") {                                                 // leave select mode
                            isSelecting = false                                            // leave select mode
                            selectedIDs = []                                               // untick everything (an empty Set)
                        }
                    }
                    ToolbarItemGroup(placement: .bottomBar) {                              // bar at the bottom of the screen
                        Button("Save", systemImage: "square.and.arrow.down") {             // LEFT: save to the iPhone Photos app
                            // coming later: copy the ticked photos into the iPhone Photos app
                        }
                        .disabled(selectedIDs.isEmpty)                                     // grey until something is ticked

                        Spacer()                                                           // space between Save and the text
                        Text(selectedCountText)                                            // MIDDLE: e.g. "已選擇 1張相片"
                            .font(.subheadline)                                            // a bit smaller than the buttons, like Photos
                        Spacer()                                                           // space between the text and the trash

                        Button("Delete", systemImage: "trash", role: .destructive) {       // RIGHT: trash button
                            deleteCount = selectedIDs.count                                // remember the number for the box's text
                            showDeleteConfirm = true                                       // ask "Delete N photos?" first
                        }
                        .disabled(selectedIDs.isEmpty)                                     // greyed out until something is ticked
                    }
                } else {                                                                   // ── normal mode ──
                    ToolbarItem(placement: .topBarLeading) {                               // top left (TEMPORARY, remove after Step B)
                        Button("Add test photo") {                                         // makes a sample photo
                            let saved = PhotoStore.save(makeTestImage())                   // save a sample picture (true = it worked)
                            if saved {                                                     // did it work?
                                photos = PhotoStore.loadAll()                              // yes → reload the list, so the new photo shows
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {                              // top right
                        Button("Select") {                                                 // enter select mode
                            isSelecting = true                                             // turn select mode on
                        }
                        .disabled(photos.isEmpty)                                          // nothing to select in an empty album
                    }
                    ToolbarItem(placement: .topBarTrailing) {                              // top right
                        Button("Done") {                                                   // close button
                            dismiss()                                                      // close the album
                        }
                    }
                }
            }
            .alert(                                                                        // the "are you sure?" box in the middle of the screen
                deleteTitle,                                                               // e.g. "Delete 2 Photos?"
                isPresented: $showDeleteConfirm                                            // shown while this switch is true
            ) {
                Button("Cancel", role: .cancel) {                                          // left button: just close the box
                }
                Button("Delete", role: .destructive) {                                     // right button, in red
                    deleteSelected()                                                       // really delete them
                }
            } message: {
                Text("They will be removed from this album. This can't be undone.")       // small text under the title
            }
            .onAppear { photos = PhotoStore.loadAll()}                                     // load the saved photos every time the album opens
            .fullScreenCover(item: $viewingPhoto) { photo in                               // tapping a photo opens it full screen
                PhotoViewer(photo: photo)                                                  // zoom, move, double-tap (PhotoViewer.swift)
            }
        }
    }

    // The title: "Memories" normally; in select mode "Select Items" (nothing ticked) or "2 Selected"
    private var titleText: String {
        if isSelecting {                                   // in select mode?
            if selectedIDs.isEmpty {                       // nothing ticked yet
                return "Select Items"
            } else {                                       // something is ticked
                return "\(selectedIDs.count) Selected"     // e.g. "2 Selected"
            }
        } else {                                           // normal mode
            return "Memories"
        }
    }

    // The delete box's title: "Delete This Photo?" for one photo, "Delete 3 Photos?" for more.
    // Uses deleteCount (remembered when the box opened), so the text doesn't change while the box disappears.
    private var deleteTitle: String {
        if deleteCount == 1 {                              // exactly one photo
            return "Delete This Photo?"
        } else {                                           // two or more
            return "Delete \(deleteCount) Photos?"
        }
    }

    // The text in the middle of the bottom bar (Chinese):
    // nothing ticked → "選擇相片", otherwise → "已選擇 3張相片" (Chinese needs no plural form)
    private var selectedCountText: String {
        if selectedIDs.count == 0 {                        // nothing ticked yet
            return "選擇相片"
        } else {                                           // one or more
            return "已選擇 \(selectedIDs.count)張相片"
        }
    }

    // Tick a photo if it isn't ticked yet; untick it if it is
    private func toggleSelection(_ photo: AlbumPhoto) {
        if selectedIDs.contains(photo.id) {                // already ticked?
            selectedIDs.remove(photo.id)                   // yes → untick it
        } else {                                           // not ticked
            selectedIDs.insert(photo.id)                   // → tick it
        }
    }

    // Delete every ticked photo, then reload the list and leave select mode
    private func deleteSelected() {
        for photo in photos {                              // every photo in the album
            if selectedIDs.contains(photo.id) {            // is it ticked?
                PhotoStore.delete(photo)                   // yes → delete its file
            }
        }
        photos = PhotoStore.loadAll()                      // reload the list (deleted ones are gone)
        selectedIDs = []                                   // untick everything
        isSelecting = false                                // back to normal mode
    }

    // The photos grouped by day, newest day first.
    // `photos` is already sorted newest first, so photos from the same day sit next to each other:
    // walk through them once, and start a new group whenever the day changes.
    private var photoDays: [PhotoDay] {
        var days: [PhotoDay] = []                                           // the groups we build
        for photo in photos {                                               // one photo at a time (newest first)
            let day = Calendar.current.startOfDay(for: photo.dateTaken)     // the start (midnight) of the day it was taken
            if days.isEmpty == false && days[days.count - 1].day == day {   // same day as the last group?
                days[days.count - 1].photos.append(photo)                   // yes → add this photo to that group
            } else {                                                        // no (or no group yet)
                days.append(PhotoDay(day: day, photos: [photo]))            // → start a new group holding just this photo
            }
        }
        return days                                                         // the finished groups
    }

    // TEMPORARY (remove after Step B): draws a picture in a random colour with the current time on it
    private func makeTestImage() -> UIImage {
        let size = CGSize(width: 600, height: 800)                                        // picture size (portrait, like a phone screen)
        let renderer = UIGraphicsImageRenderer(size: size)                               // draws a new picture
        return renderer.image { context in                                               // everything drawn here ends up in the picture
            let color = UIColor(hue: CGFloat.random(in: 0...1), saturation: 0.5, brightness: 0.9, alpha: 1)  // a random colour
            color.setFill()                                                               // paint with that colour
            context.fill(CGRect(origin: .zero, size: size))                               // fill the whole picture
            let time = Date.now.formatted(date: .omitted, time: .standard) as NSString    // the time now, e.g. "14:05:31"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 60),                                 // big bold text
                .foregroundColor: UIColor.white                                           // white text
            ]
            time.draw(at: CGPoint(x: 60, y: 360), withAttributes: attributes)             // write the time near the middle
        }
    }
}

// One square thumbnail in the grid.
// Loads a small copy of the photo instead of the full picture, so the album uses little memory.
struct PhotoThumbnail: View {
    let photo: AlbumPhoto                  // which photo to show
    let isSelected: Bool                   // true = this photo is ticked (select mode)
    @State private var image: UIImage?     // the small copy; nil until it's loaded

    var body: some View {
        Color.gray.opacity(0.2)                           // grey square while the picture loads
            .aspectRatio(1, contentMode: .fit)            // always a square
            .overlay {                                    // the picture goes on top of the square
                if let image {                            // loaded yet?
                    Image(uiImage: image)
                        .resizable()                      // allowed to change size
                        .scaledToFill()                   // fill the square (the edges get cut off)
                }
            }
            .clipped()                                    // cut off whatever sticks out of the square
            .contentShape(Rectangle())                    // only the square can be tapped (clipped() only hides the cut-off parts; they could still be tapped)
            .overlay {                                    // a light veil over ticked photos
                if isSelected {
                    Color.white.opacity(0.3)
                }
            }
            .overlay(alignment: .bottomTrailing) {        // the tick in the bottom-right corner, like Photos
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)    // lets the tick and the circle have different colours
                        .foregroundStyle(.white, .blue)   // white tick on a blue circle
                        .padding(4)
                }
            }
            .task {                                       // runs once when the square appears on screen
                // read the photo file, then make a small copy that keeps the photo's shape
                if let full = UIImage(contentsOfFile: photo.url.path(percentEncoded: false)) {
                    let ratio = full.size.height / full.size.width          // tall photo → bigger than 1
                    let smallSize = CGSize(width: 300, height: 300 * ratio)  // 300 wide, height to match
                    image = full.preparingThumbnail(of: smallSize)          // the small copy
                }
            }
    }
}

#Preview {
    AlbumView()  // shows the album in Xcode's canvas
}
