import Foundation
import Observation
import ImageIO

/// Normalized offsets keep preview, exported photo and refreshed portraits framed identically.
struct PhotoFraming: Codable, Equatable {
    var zoom: Double = 1
    var x: Double = 0
    var y: Double = 0
    var bounded: PhotoFraming {
        let z = zoom.isFinite ? min(3,max(1,zoom)) : 1
        let limit = z * 0.45
        return PhotoFraming(zoom:z,x:x.isFinite ? min(limit,max(-limit,x)) : 0,y:y.isFinite ? min(limit,max(-limit,y)) : 0)
    }
    func dragged(x dx: Double, y dy: Double) -> PhotoFraming {
        PhotoFraming(zoom:zoom,x:x+dx,y:y+dy).bounded
    }
}

struct EmberCreation: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date()
    let sessionID: UUID
    let name: String
    let paint: PaintChoice?
    let scales: [ScaleDecoration]
    let backdrop: PhotoBackdrop
    let yaw: Float
    var framing: PhotoFraming? = nil
    var regionPaint: [PaintRegion:PaintChoice]? = nil
    var imageName: String { id.uuidString + ".png" }
}

enum PhotoBackdrop: String, Codable, CaseIterable {
    case forest = "Forest", sunset = "Sunset", moonlight = "Moonlight"

}

@MainActor @Observable
final class EmberGalleryStore {
    private(set) var entries: [EmberCreation] = []
    var errorMessage: String?
    private var canWrite = true
    private let folder: URL
    init(folder: URL? = nil) {
        self.folder = folder ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("EmberGallery",isDirectory:true)
        do {
            try FileManager.default.createDirectory(at:self.folder,withIntermediateDirectories:true)
            let index = self.folder.appendingPathComponent("gallery.json")
            if FileManager.default.fileExists(atPath:index.path) {
                let loaded = try JSONDecoder().decode([EmberCreation].self,from:Data(contentsOf:index))
                guard loaded.allSatisfy({ ScaleDesignLayout.valid($0.scales) }), Set(loaded.map(\.id)).count == loaded.count else { throw CocoaError(.fileReadCorruptFile) }
                entries = loaded
            }
        } catch { canWrite = false; errorMessage = "The gallery could not be opened. Existing saves have been left untouched. \(error.localizedDescription)" }
    }
    func imageURL(_ entry: EmberCreation) -> URL { folder.appendingPathComponent(entry.imageName) }
    func replacePortrait(_ entry: EmberCreation, png: Data) throws {
        guard canWrite, entries.contains(where: { $0.id == entry.id }), let source = CGImageSourceCreateWithData(png as CFData,nil), CGImageSourceCreateImageAtIndex(source,0,nil) != nil else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to:imageURL(entry),options:.atomic)
    }
    func save(_ entry: EmberCreation, png: Data) throws {
        guard canWrite, ScaleDesignLayout.valid(entry.scales), let source = CGImageSourceCreateWithData(png as CFData,nil), CGImageSourceCreateImageAtIndex(source,0,nil) != nil else { throw CocoaError(.fileWriteUnknown) }
        guard !entries.contains(where: { $0.id == entry.id }) else { return }
        let updated = [entry] + entries
        let index = try JSONEncoder().encode(updated)
        let photo = imageURL(entry)
        try png.write(to:photo,options:.atomic)
        do { try index.write(to:folder.appendingPathComponent("gallery.json"),options:.atomic) }
        catch { try? FileManager.default.removeItem(at:photo); throw error }
        entries = updated
    }
}

