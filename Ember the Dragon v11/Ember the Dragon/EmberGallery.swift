import SwiftUI
import UIKit
import ImageIO
import RealityKit

extension PhotoBackdrop {
    var colors: [Color] {
        switch self {
        case .forest: [Color(red:0.06,green:0.20,blue:0.20),Color(red:0.30,green:0.48,blue:0.38)]
        case .sunset: [Color(red:0.32,green:0.17,blue:0.34),Color(red:0.91,green:0.58,blue:0.39)]
        case .moonlight: [Color(red:0.08,green:0.10,blue:0.24),Color(red:0.34,green:0.38,blue:0.60)]
        }
    }
}

struct EmberPostcard: View {
    let image: UIImage
    let name: String
    let backdrop: PhotoBackdrop
    var capturedAt: Date? = nil
    var framing = PhotoFraming()
    var onDrag: ((CGSize, CGSize, Bool) -> Void)? = nil
    var body: some View {
        ZStack {
            LinearGradient(colors:backdrop.colors,startPoint:.topLeading,endPoint:.bottomTrailing)
            Circle().fill(.white.opacity(0.09)).frame(width:300,height:300).offset(x:100,y:-135)
            Circle().stroke(.white.opacity(0.12),lineWidth:1).frame(width:390,height:390).offset(x:-110,y:100)
            VStack(spacing:0) {
                HStack { Text("EMBER").tracking(2); Spacer(); Image(systemName:"camera") }
                    .font(.system(size:12,weight:.bold,design:.rounded)).foregroundStyle(.white.opacity(0.8)).padding(24)
                GeometryReader { geometry in
                    Image(uiImage:image).resizable().scaledToFit()
                        .frame(width:geometry.size.width,height:geometry.size.height)
                        .scaleEffect(framing.bounded.zoom)
                        .offset(x:framing.bounded.x*geometry.size.width,y:framing.bounded.y*geometry.size.height)
                        .frame(width:geometry.size.width,height:geometry.size.height)
                        .clipped().contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance:3)
                            .onChanged { onDrag?($0.translation,geometry.size,false) }
                            .onEnded { onDrag?($0.translation,geometry.size,true) })
                        .accessibilityLabel("Ember photo. Drag to adjust framing.")
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
                VStack(spacing:6) {
                    Text(name.isEmpty ? "My Ember" : name).font(.system(size:28,weight:.heavy,design:.rounded)).lineLimit(1).minimumScaleFactor(0.6)
                    Text(capturedAt.map { $0.formatted(date:.abbreviated,time:.shortened) } ?? "Photobooth").font(.system(size:14,weight:.medium,design:.rounded)).opacity(0.75)
                }.foregroundStyle(.white).padding(.bottom,28)
            }
        }.frame(width:480,height:640).clipShape(RoundedRectangle(cornerRadius:28))
    }
}

struct EmberPhotoBooth: View {
    @Environment(GameModel.self) private var model
    @Environment(EmberGalleryStore.self) private var gallery
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var name = "My Ember"
    @State private var backdrop: PhotoBackdrop = .forest
    @State private var yaw: Float = -0.25
    @State private var framing = PhotoFraming()
    @State private var dragOrigin: PhotoFraming?
    @State private var preview: UIImage?
    @State private var portrait: UIImage?
    @State private var snapshot: EmberCreation?
    @State private var saved = false
    @State private var flashOpacity: Double = 0
    @State private var message = ""
    @State private var busy = false
    @State private var renderer: EmberPortraitRenderer?
    @Environment(\.scenePhase) private var scenePhase
    private var finished: Bool { model.activePhase == .complete || model.activePhase == .celebration }
    var body: some View {
        HStack(spacing:28) {
            ZStack {
                if let preview { EmberPostcard(image:preview,name:name,backdrop:backdrop,capturedAt:snapshot?.createdAt,framing:framing,onDrag:reframe) }
                else {
                    VStack(spacing:16) {
                        if message.isEmpty { ProgressView("Setting up the studio…") }
                        else {
                            Image(systemName:"camera.aperture").font(.largeTitle)
                            Text(message).multilineTextAlignment(.center)
                            Button("Try studio again") { prepareStudio() }
                        }
                    }.frame(width:480,height:640)
                }
                RoundedRectangle(cornerRadius:EmberUI.panelRadius).fill(.white.opacity(flashOpacity)).frame(width:480,height:640).allowsHitTesting(false)
            }
            VStack(alignment:.leading,spacing:16) {
                HStack {
                    Text("Photobooth").font(.system(size:28,weight:.semibold,design:.rounded))
                    Spacer()
                    Button { model.isPhotoBoothPresented = false; dismissWindow(id:"EmberPhotoBooth") } label: { Image(systemName:"xmark") }.accessibilityLabel("Back to Ember")
                }
                TextField("Companion name",text:$name).textFieldStyle(.plain).padding(14)
                    .background(.thinMaterial,in:RoundedRectangle(cornerRadius:EmberUI.controlRadius))
                    .onChange(of:name) { _, value in name = String(value.prefix(28)); invalidateShot() }
                Picker("Backdrop",selection:$backdrop) { ForEach(PhotoBackdrop.allCases,id:\.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    .onChange(of:backdrop) { _, _ in invalidateShot() }
                HStack(spacing:12) {
                    Button("Left",systemImage:"arrow.counterclockwise") { turn(-Float.pi/6) }
                    Button("Right",systemImage:"arrow.clockwise") { turn(Float.pi/6) }
                }
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        Text("Zoom").font(.callout)
                        Spacer()
                        Text(String(format:"%.1f×",framing.zoom)).font(.callout.monospacedDigit())
                        Button("Reset") { framing = PhotoFraming(); dragOrigin = nil; invalidateShot() }
                            .buttonStyle(.plain).padding(.vertical,4)
                            .accessibilityLabel("Reset zoom and photo position")
                    }
                    Slider(value:$framing.zoom,in:1...3).accessibilityLabel("Photo zoom")
                        .onChange(of:framing.zoom) { _, _ in framing = framing.bounded; invalidateShot() }
                    Text("Drag Ember’s picture to frame your photo.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength:8)
                Button(action: { Task { await snap() } }) {
                    Label(snapshot == nil ? "Take photo" : "Retake photo",systemImage:"camera.fill").frame(maxWidth:.infinity)
                }.buttonStyle(EmberActionStyle(prominent:true)).disabled(preview == nil || busy || !finished)
                HStack(spacing:12) {
                    Button(saved ? "Saved" : "Save to gallery",systemImage:saved ? "checkmark" : "square.and.arrow.down") { save() }
                        .disabled(snapshot == nil || saved || busy || !finished)
                    Button("Gallery",systemImage:"square.grid.2x2") { openWindow(id:"EmberGallery") }
                    Spacer(minLength:0)
                }
                HStack(alignment:.center,spacing:12) {
                    Text(message.isEmpty ? "Photos are saved on this headset." : message)
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                    if let snapshot, saved { ShareLink("Export",item:gallery.imageURL(snapshot)) }
                }.frame(minHeight:44,alignment:.topLeading)
                if !finished { Text("Finish an Ember to take a photo.").foregroundStyle(.secondary) }
            }.frame(width:410,height:640).disabled(busy)
        }.padding(28).modifier(EmberGlassPanel()).foregroundStyle(.white).buttonStyle(EmberActionStyle()).environment(\.colorScheme,.dark)
        .onAppear { model.isPhotoBoothPresented = true }
        .task(id:model.photoSessionID.uuidString + model.activePhase.rawValue) {
            invalidateShot(); preview = nil; renderer = nil
            guard finished else { message = "Finish an Ember, then reopen the booth."; return }
            await Task.yield()
            prepareStudio()
        }
        .onDisappear { model.isPhotoBoothPresented = false; renderer = nil; preview = nil; portrait = nil; PebblePaintTextures.clearCache() }
        .onChange(of:scenePhase) { _, phase in
            if phase == .background { renderer = nil }
        }
        .onChange(of:model.activePhase) { _, phase in
            if phase != .complete && phase != .celebration { invalidateShot(); preview = nil; renderer = nil }
        }
    }
    private func reframe(_ translation: CGSize, _ size: CGSize, _ ended: Bool) {
        guard !busy, size.width > 0, size.height > 0 else { return }
        if dragOrigin == nil { dragOrigin = framing; invalidateShot() }
        framing = (dragOrigin ?? framing).dragged(x:translation.width/size.width,y:translation.height/size.height)
        if ended { dragOrigin = nil }
    }
    private func prepareStudio() {
        guard finished else { return }
        message = ""
        do { renderer = try EmberPortraitRenderer(paint:model.appliedPaint,scales:model.scaleDesign,regions:model.regionPaint); try render() }
        catch { message = "Could not prepare the portrait. \(error.localizedDescription)" }
    }
    private func invalidateShot() { snapshot = nil; portrait = nil; saved = false; message = "" }
    private func turn(_ amount: Float) { yaw += amount; invalidateShot(); do { try render() } catch { message = error.localizedDescription } }
    private func render() throws {
        if renderer == nil { renderer = try EmberPortraitRenderer(paint:model.appliedPaint,scales:model.scaleDesign,regions:model.regionPaint) }
        preview = try renderer?.render(yaw:yaw)
        // The preview is a flat image; release the second 3D renderer immediately.
        renderer = nil
    }
    private func snap() async {
        guard let preview, finished, !busy else { return }
        busy = true; defer { busy = false; flashOpacity = 0 }
        let session = model.photoSessionID
        do {
            guard finished, session == model.photoSessionID else { return }
            let title = name.trimmingCharacters(in:.whitespacesAndNewlines)
            let entry = EmberCreation(sessionID:session,name:title.isEmpty ? "My Ember" : title,paint:model.appliedPaint,scales:model.scaleDesign,backdrop:backdrop,yaw:yaw,framing:framing.bounded,regionPaint:model.regionPaint)
            let image = ImageRenderer(content:EmberPostcard(image:preview,name:entry.name,backdrop:backdrop,capturedAt:entry.createdAt,framing:entry.framing ?? PhotoFraming())); image.scale = 2
            guard let photo = image.uiImage else { throw CocoaError(.fileWriteUnknown) }
            GameAudio.shared.play(.shutter)
            portrait = photo; snapshot = entry; saved = false; message = "Photo captured. Save to keep it."
            flashOpacity = 0.55
            try await Task.sleep(for:.milliseconds(70))
            withAnimation(.easeOut(duration:0.18)) { flashOpacity = 0 }
            try await Task.sleep(for:.milliseconds(180))
        } catch { message = "The photo could not be captured. Please try again." }
    }
    private func save() {
        guard let snapshot, let data = portrait?.pngData() else { return }
        do { try gallery.save(snapshot,png:data); GameAudio.shared.play(.success); saved = true; message = "Saved to this headset’s gallery." }
        catch { message = "Could not save. Your photo is still here; please try again. \(error.localizedDescription)" }
    }
}

struct EmberGalleryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(EmberGalleryStore.self) private var gallery
    @State private var selected: EmberCreation?
    @State private var showModel = false
    @State private var portraitRevision = 0
    @State private var refreshing = false
    @State private var refreshError: String?
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            Label("Gallery",systemImage:"sparkles.rectangle.stack.fill").font(.system(size:32,weight:.heavy,design:.rounded))
            Text("Different colours. Different patterns. All made on this headset.").foregroundStyle(.secondary)
            if let error = gallery.errorMessage { Text(error).foregroundStyle(.orange) }
            if gallery.entries.isEmpty {
                ContentUnavailableView("The first Ember could be yours",systemImage:"camera.on.rectangle",description:Text("Finish the activities, visit the photobooth and save a creation. Other children using this headset can add theirs too."))
            } else {
                ScrollView {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:180),spacing:18)],spacing:18) {
                        ForEach(gallery.entries) { entry in
                            Button { showModel = false; selected = entry } label: {
                                VStack(alignment:.leading,spacing:8) {
                                    GalleryThumbnail(url:gallery.imageURL(entry)).id(portraitRevision).frame(height:220).clipShape(RoundedRectangle(cornerRadius:18))
                                    Text(entry.name).font(.headline).lineLimit(1)
                                    Text(entry.createdAt,style:.date).font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.padding(28).frame(minWidth:760,minHeight:560)
        .modifier(EmberGlassPanel()).foregroundStyle(.white)
        .buttonStyle(EmberActionStyle())
        .sheet(item:$selected) { entry in
            VStack(spacing:16) {
                Text(entry.name).font(.title.bold())
                if showModel && scenePhase == .active { SavedEmberModel(entry:entry).frame(width:500,height:440) }
                else { GalleryThumbnail(url:gallery.imageURL(entry),pixelSize:900).id(portraitRevision).frame(height:440) }
                Button(showModel ? "View portrait" : "Meet this Ember in 3D",systemImage:showModel ? "photo" : "cube.transparent") { showModel.toggle() }
                Text("\(entry.regionPaint?.isEmpty == false ? "Personal colours" : (entry.paint?.rawValue ?? "Pearl grey")) · \(entry.scales.count) personal scales").foregroundStyle(.secondary)
                if let refreshError { Text(refreshError).foregroundStyle(.orange) }
                Button(refreshing ? "Refreshing…" : "Refresh portrait lighting") {
                    refreshing = true; refreshError = nil
                    Task { @MainActor in
                        await Task.yield()
                        do {
                            let renderer = try EmberPortraitRenderer(paint:entry.paint,scales:entry.scales,regions:entry.regionPaint ?? [:])
                            let preview = try renderer.render(yaw:entry.yaw)
                            let card = ImageRenderer(content:EmberPostcard(image:preview,name:entry.name,backdrop:entry.backdrop,capturedAt:entry.createdAt,framing:entry.framing ?? PhotoFraming())); card.scale = 2
                            guard let png = card.uiImage?.pngData() else { throw CocoaError(.fileWriteUnknown) }
                            try gallery.replacePortrait(entry,png:png); portraitRevision += 1
                        } catch { refreshError = "The portrait could not be refreshed. Your saved creation is unchanged." }
                        refreshing = false
                    }
                }.disabled(refreshing || showModel)
                HStack { ShareLink("Export photo",item:gallery.imageURL(entry)); Button("Done") { selected = nil } }
            }.padding(24).modifier(EmberGlassPanel()).foregroundStyle(.white).buttonStyle(EmberActionStyle())
        }
    }
}

private struct GalleryThumbnail: View {
    let url: URL
    var pixelSize: Int = 360
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage:image).resizable().scaledToFit() }
            else { Image(systemName:"photo").font(.largeTitle).accessibilityLabel("Portrait unavailable") }
        }.task(id:url) {
            // Decode thumbnails at display size instead of retaining full-resolution exports for the grid.
            guard let source = CGImageSourceCreateWithURL(url as CFURL,nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:pixelSize] as CFDictionary) else { return }
            image = UIImage(cgImage:cg)
        }.onDisappear { image = nil }
    }
}


private struct SavedEmberModel: View {
    let entry: EmberCreation
    @State private var subject: Entity?
    @State private var assetOwner = UUID().uuidString
    @State private var yaw: Float = 0
    @State private var message = "Loading Ember…"
    var body: some View {
        VStack {
            RealityView { content in
                do { try await GameAssetLibrary.shared.prepare(AssetResidency.portrait,owner:assetOwner) }
                catch { message = "This Ember’s model could not load."; GameAssetLibrary.shared.release(owner:assetOwner); return }
                guard !Task.isCancelled else { GameAssetLibrary.shared.release(owner:assetOwner); return }
                let root = Entity()
                guard let body = GameAssetLibrary.shared.cloneVisual(named:PebbleForm.complete.assetName,target:PebbleForm.complete.target,canonicalName:"SavedEmber") else { message = "This Ember’s model could not load."; GameAssetLibrary.shared.release(owner:assetOwner); return }
                body.position = PebbleForm.complete.offset
                if let paint = entry.paint { PebblePaintTextures.apply(to:body,asset:PebbleForm.complete.assetName,colour:paint) }
                if let regions = entry.regionPaint, !regions.isEmpty { RegionalPaintTextures.apply(to:body,asset:PebbleForm.complete.assetName,regions:regions) }
                root.addChild(body)
                for item in entry.scales {
                    let scale = makePatternScale(item)
                    scale.position = item.position(complete:true)
                    scale.orientation = simd_quatf(from:[0,0,1],to:item.normal(complete:true))
                    root.addChild(scale)
                }
                root.scale = [0.42,0.42,0.42]
                await RenderedStyle.install(on:root)
                content.add(root); subject = root; message = ""
                GameAssetLibrary.shared.release(owner:assetOwner)
            } update: { _ in subject?.orientation = simd_quatf(angle:yaw,axis:[0,1,0]) }
            if !message.isEmpty { Text(message).font(.caption) }
            HStack {
                Button("Turn left",systemImage:"arrow.counterclockwise") { yaw -= .pi/6 }
                Button("Right",systemImage:"arrow.clockwise") { yaw += .pi/6 }
            }
        }
        .onDisappear {
            subject?.removeAllChildren(); subject?.removeFromParent(); subject = nil
            GameAssetLibrary.shared.release(owner:assetOwner)
            PebblePaintTextures.clearCache()
        }
    }
}
