//
//  PhotoStore.swift
//  game
//
//  Saves, loads and deletes the photos taken in AR.
//  They live in the app's own folder (Documents/Photos), not the iPhone Photos app:
//  no permission popup, and the photos stay inside the game.
//  File name = the moment the photo was taken, in milliseconds (e.g. "1761315065123.jpg");
//  loadAll() reads the date back from that name.
//

import UIKit        // UIImage (the photo) and jpegData (turns it into file bytes)
import Foundation   // FileManager, URL, Date, Data

// One photo in the album
struct AlbumPhoto: Identifiable {
    let url: URL          // where the photo file is on the iPhone
    let dateTaken: Date   // when it was taken (read back from the file name)
    var id: URL { url }   // each file has its own path, so the path works as the id
}

// Saves, loads and deletes photos in the app's own folder (not the iPhone Photos app)
enum PhotoStore {
    // <the app's Documents folder>/Photos
    static let folderURL = URL.documentsDirectory.appending(path: "Photos", directoryHint: .isDirectory)

    // 1. Save one photo; returns true if it was saved
    static func save(_ image: UIImage) -> Bool {
        // a. make sure the Photos folder exists (created on the first photo)
        do {                                                                                           // try something that can fail
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)  // create the folder (no error if it's already there)
        } catch {                                                                                      // creating it failed
            return false                                                                               // no folder → can't save
        }

        // b. turn the picture into JPEG bytes
        let jpegData = image.jpegData(compressionQuality: 0.9)              // Data?: nil if it can't be converted
        if let data = jpegData {                                            // got the bytes?
            // c. file name = this moment in milliseconds, e.g. "1761315065123.jpg"
            let milliseconds = Int(Date.now.timeIntervalSince1970 * 1000)   // seconds since 1970 × 1000, no decimals
            let fileURL = folderURL.appending(path: "\(milliseconds).jpg")  // folder path + file name = the new file's path

            // d. write the bytes into that file
            do {                                                // try something that can fail
                try data.write(to: fileURL, options: .atomic)   // write the photo file in one piece
                return true                                     // runs only if the write worked → saved
            } catch {                                           // the write failed
                return false                                    // e.g. iPhone storage is full
            }
        } else {                                                // no bytes
            return false                                        // couldn't turn the picture into JPEG
        }
    }

    // 2. Load every saved photo, newest first
    static func loadAll() -> [AlbumPhoto] {
        var photos: [AlbumPhoto] = []                                                                               // the list we fill and return

        // a. ask for every file in the Photos folder
        var fileURLs: [URL] = []                                                                                    // paths of the files found
        do {                                                                                                        // try something that can fail
            fileURLs = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)  // list the folder
        } catch {                                                                                                   // it failed
            return photos                                                                                           // no folder yet (no photo taken) → empty album
        }

        // b. turn each photo file into an AlbumPhoto
        for fileURL in fileURLs {                                                // one file at a time
            if fileURL.pathExtension == "jpg" {                                  // only our photo files
                let name = fileURL.deletingPathExtension().lastPathComponent     // "1761315065123.jpg" → "1761315065123"
                if let milliseconds = Double(name) {                             // is the name a number?
                    let date = Date(timeIntervalSince1970: milliseconds / 1000)  // milliseconds → seconds → Date
                    let photo = AlbumPhoto(url: fileURL, dateTaken: date)        // one album entry
                    photos.append(photo)                                         // add it to the list
                }
            }
        }

        // c. newest first
        photos.sort { first, second in                  // "should first come before second?"
            return first.dateTaken > second.dateTaken   // yes, if first was taken later
        }
        return photos                                   // the finished list
    }

    // 3. Delete one photo file (for the album's delete button in Step 4)
    static func delete(_ photo: AlbumPhoto) {
        do {                                                   // try something that can fail
            try FileManager.default.removeItem(at: photo.url)  // delete the photo's file
        } catch {                                              // it failed
            // the file was already gone → nothing to do
        }
    }
}
