//
//  ContentView.swift
//  offio
//
//  Created by Theo on 12/16/25.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ContentView: View {
    
    @Environment(AudioManager.self) var audioManager

    @State private var isListVisible = false
    @State private var showFileImporter = false
    
    // --- Photo Library States ---
    @State private var showImagePicker = false
    @State private var selectedImageItem: PhotosPickerItem? = nil
    
    // --- CROPPER STATES ---
    @State private var imageToCrop: UIImage? = nil
    @State private var showCropper = false
    @State private var isProcessingImage = false
    
    // --- RENAME STATES ---
    @State private var showRenameAlert = false
    @State private var renameText = ""
    
    // --- HINT STATE ---
    @State private var showHint = true
    
    // Animation States
    @State private var dragOffset: CGFloat = 0
    // Neighbors
    @State private var prevImage: UIImage? = nil
    @State private var nextImage: UIImage? = nil
    
    var body: some View {
        GeometryReader { geo in

            // 1. Main ZStack aligned to bottom for the floating controls
            ZStack(alignment: .bottom) {
                Color(UIColor.systemBackground).ignoresSafeArea()
                
                // 2. Main Content Layout (Top Aligned)
                VStack(spacing: 0) {
                    
                    // MARK: - 1. Image Section (Carousel)
                    let squareSize = geo.size.width - 16
                    imageCarousel(geo: geo, squareSize: squareSize)
                    
                    // MARK: - 2. Content Section
                    // We use ZStack to stack PlayingView and ListView on top of each other
                    ZStack {
                        // A. Playing View (Bottom Layer)
                        // It stays in place but fades out when list covers it
                        playingView
                            .opacity(isListVisible ? 0 : 1)
                            .animation(.easeInOut(duration: 0.3), value: isListVisible)
                        
                        // B. List View (Top Layer)
                        // We use .offset to slide it in/out.
                        // geo.size.height guarantees it moves far enough to clear the screen.
                        listView
                            .offset(y: isListVisible ? 0 : geo.size.height)
                            // Optional: Fade slightly as it leaves
                            .opacity(isListVisible ? 1 : 0)
                            // Use a spring animation for a nice "Drawer" feel
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isListVisible)
                    }
                    .frame(maxHeight: .infinity)
                    // Clip allows the list to slide "under" the carousel if you want,
                    // or keeps it contained in this area.
                    .clipped()
                }
                
                // 3. Global Floating Controls
                floatingControls
                    .padding(.bottom, 20)
                
                // 4. Loading Overlay
                if isProcessingImage {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("Loading Image...")
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(20)
                }
            }
            .statusBarHidden()
            
            // GESTURE LOGIC
            .gesture(dragGesture(geo: geo))
        }
        .onOpenURL { url in audioManager.importFile(from: url) }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [UTType.audio], allowsMultipleSelection: true) { result in
            if let urls = try? result.get() { for u in urls { audioManager.importFile(from: u) } }
        }
        .photosPicker(isPresented: $showImagePicker, selection: $selectedImageItem, matching: .images)
        .onChange(of: selectedImageItem) { _, newItem in
            handleImageSelection(newItem)
        }
        .fullScreenCover(isPresented: $showCropper) {
            if let img = imageToCrop {
                ImageCropper(image: img) { croppedImage in
                    if let currentUrl = audioManager.audioFiles[safe: audioManager.currentTrackIndex ?? -1] {
                        audioManager.saveImage(croppedImage, for: currentUrl)
                    }
                }
            }
        }
        .alert("Rename Track", isPresented: $showRenameAlert) {
            TextField("New Name", text: $renameText)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                withAnimation(.snappy) {
                    audioManager.renameCurrentTrack(to: renameText)
                }
            }
        }
        .onChange(of: audioManager.currentTrackIndex) { _, newIndex in
            updateNeighborImages(currentIndex: newIndex)
        }
        .onChange(of: audioManager.playStrategy) { _, _ in
               updateNeighborImages(currentIndex: audioManager.currentTrackIndex)
           }
        .onAppear {
            updateNeighborImages(currentIndex: audioManager.currentTrackIndex)
        }
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    var floatingControls: some View {
        HStack(spacing: 50) {
            
            // LEFT BUTTON
            Button(action: {
                if isListVisible {
                    withAnimation(.spring()) { isListVisible = false }
                } else {
                    audioManager.cyclePlayStrategy()
                }
            }) {
                let iconName = isListVisible ? "chevron.down" : (audioManager.playStrategy == .shuffle ? "shuffle" : "repeat")
                let color: Color = isListVisible ? .primary : (audioManager.playStrategy == .off ? .primary.opacity(0.1) : .primary)
                
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 60, height: 60)
                    .glassEffect(.regular.interactive())
                    .clipShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .glassEffect(.regular.interactive())
            
            Spacer().frame(width: 64)
            
            // RIGHT BUTTON
            Button(action: {
                if isListVisible {
                    showFileImporter = true
                } else {
                    audioManager.isRepeatOne.toggle()
                }
            }) {
                let iconName = isListVisible ? "plus" : "repeat.1"
                let color: Color = isListVisible ? .primary : (audioManager.isRepeatOne ? .primary : .primary.opacity(0.1))
                
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 60, height: 60)
                    .glassEffect(.regular.interactive())
                    .clipShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .glassEffect(.regular.interactive())
        }
    }

    @ViewBuilder
    func imageCarousel(geo: GeometryProxy, squareSize: CGFloat) -> some View {
        ZStack {
            renderImageView(image: prevImage, size: squareSize, placeHolder: audioManager.getPreviousTrackIndex() == nil ? "No Previous Track": "No Cover")
                .offset(x: -squareSize - 16.0 + dragOffset)
            
            renderImageView(image: nextImage, size: squareSize, placeHolder: audioManager.getNextTrackIndex() == nil ? "No Next Track": "No Cover")
                .offset(x: squareSize + 16.0 + dragOffset)
            
            renderImageView(image: audioManager.trackImage, size: squareSize)
                .overlay(
                    Group {
                        if !audioManager.isPlaying {
                            Image(systemName: "play.circle.fill")
                                .resizable()
                                .frame(width: 80, height: 80)
                                .foregroundColor(.white.opacity(0.8))
                                .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 0)
                        }
                    }
                )
                .offset(x: dragOffset)
                .onLongPressGesture {
                    showImagePicker = true
                }
        }
        .frame(width: geo.size.width, height: squareSize)
        .padding(.vertical, 8)
        .onTapGesture {
            withAnimation { showHint = false }
            audioManager.togglePlayPause()
        }
    }
    
    var listView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 6) {
                
                Color.clear.frame(height: 20)
                
                ForEach(audioManager.audioFiles.indices, id: \.self) { index in
                    let url = audioManager.audioFiles[index]
                    let isCurrent = audioManager.currentTrackIndex == index
                    
                    HStack {
                        Text(audioManager.getDisplayName(for: url))
                            .fontWeight(isCurrent ? .bold : .regular)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(isCurrent ? Color.primary : Color(UIColor.secondarySystemBackground))
                    .cornerRadius(20)
                    .foregroundColor(isCurrent ? Color(UIColor.systemBackground) : .primary)
                    .animation(.easeInOut(duration: 0.3), value: isCurrent)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation { showHint = false }
                        audioManager.playTrack(at: index)
                    }
                }
                
                Color.clear.frame(height: 100)
            }
        }
        // Force the list to take up all available space,
        // ensuring the offset animation works correctly.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mask(
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .black, location: 0.05),
                    .init(color: .black, location: 0.9),
                    .init(color: .clear, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // Note: .transition modifier REMOVED in favor of .offset in the main body
    }
    
    var playingView: some View {
        VStack(spacing: 0) {
            
            Text(audioManager.trackName)
                .font(.title2).fontWeight(.bold)
                .multilineTextAlignment(.leading)
                .id(audioManager.trackName)
                .transition(.push(from: .bottom).combined(with: .opacity))
                .onLongPressGesture {
                    renameText = audioManager.trackName
                    showRenameAlert = true
                }
                .padding(.horizontal)
                .padding(.top, 20)
            
            Spacer()
            
            VStack(spacing: 20) {
                if showHint {
                    VStack(spacing: 5) {
                        Text("Tap to Play • Swipe for Tracks")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .padding(10)
                        
                        Image(systemName: "chevron.compact.up")
                            .foregroundColor(.gray)
                    }
                    .padding(.bottom, 10)
                    .transition(.opacity)
                } else {
                    Color.clear.frame(height: 20)
                }
                
                VStack(spacing: 5) {
                    Slider(
                        value: Binding(
                            get: { audioManager.currentTime },
                            set: { newValue in audioManager.seek(to: newValue) }
                        ),
                        in: 0...audioManager.duration,
                        onEditingChanged: { isEditing in
                            if isEditing {
                                withAnimation { showHint = false }
                                audioManager.startScrubbing()
                            }
                            else { audioManager.endScrubbing() }
                        }
                    )
                    .tint(.primary)
                    
                    HStack {
                        Text(audioManager.currentTime.formattedString())
                        Spacer()
                        Text(audioManager.duration.formattedString())
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                Color.clear.frame(height: 80)
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { showHint = false }
            audioManager.togglePlayPause()
        }
        // Note: Transition removed here, handled in Parent ZStack
    }
    
    // MARK: - Helpers
    
    func dragGesture(geo: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if showHint { withAnimation { showHint = false } }
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                let horizontalAmount = value.translation.width
                let verticalAmount = value.translation.height
                
                // Vertical (List)
                if abs(verticalAmount) > abs(horizontalAmount) {
                    if verticalAmount < -50 && !isListVisible {
                        withAnimation(.spring()) { isListVisible = true }
                    } else if verticalAmount > 50 && isListVisible {
                        withAnimation(.spring()) { isListVisible = false }
                    }
                    withAnimation(.spring()) { dragOffset = 0 }
                    return
                }
                
                // Horizontal (Swipe)
                let screenWidth = geo.size.width
                
                if horizontalAmount < -100 {
                    if audioManager.getNextTrackIndex() != nil {
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = -screenWidth }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            audioManager.nextTrack()
                            var t = Transaction(animation: nil); t.disablesAnimations = true
                            withTransaction(t) { dragOffset = 0 }
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { dragOffset = 0 }
                    }
                } else if horizontalAmount > 100 {
                    if audioManager.getPreviousTrackIndex() != nil {
                        withAnimation(.easeOut(duration: 0.2)) { dragOffset = screenWidth }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            audioManager.previousTrack(force: true)
                            var t = Transaction(animation: nil); t.disablesAnimations = true
                            withTransaction(t) { dragOffset = 0 }
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { dragOffset = 0 }
                    }
                } else {
                    withAnimation(.spring()) { dragOffset = 0 }
                }
            }
    }
    
    func handleImageSelection(_ newItem: PhotosPickerItem?) {
        guard let newItem else { return }
        isProcessingImage = true
        Task {
            if let data = try? await newItem.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                await MainActor.run { selectedImageItem = nil }
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    self.imageToCrop = image
                    self.isProcessingImage = false
                    self.showCropper = true
                }
            } else {
                await MainActor.run { isProcessingImage = false }
            }
        }
    }
    
    @ViewBuilder
    func renderImageView(image: UIImage?, size: CGFloat, placeHolder: String = "No Cover") -> some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.black)
                    .overlay(Text(placeHolder).foregroundColor(.gray).font(.caption))
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .cornerRadius(20)
    }
    
    func updateNeighborImages(currentIndex: Int?) {
        if let nextIdx = audioManager.getNextTrackIndex() {
            nextImage = audioManager.getImage(at: nextIdx)
        } else {
            nextImage = nil
        }
        if let prevIdx = audioManager.getPreviousTrackIndex() {
            prevImage = audioManager.getImage(at: prevIdx)
        } else {
            prevImage = nil
        }
    }
}

struct ImageCropper: View {
    var image: UIImage
    var onCrop: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            VStack {
                Spacer()
                ZStack {
                    Image(uiImage: image).resizable().scaledToFill()
                        .scaleEffect(scale).offset(offset)
                        .frame(width: 300, height: 300).clipped()
                        .gesture(DragGesture().onChanged { v in offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) }.onEnded { _ in lastOffset = offset })
                        .gesture(MagnificationGesture().onChanged { v in scale = lastScale * v }.onEnded { _ in lastScale = scale })
                    Rectangle().stroke(Color.white, lineWidth: 2).frame(width: 300, height: 300).allowsHitTesting(false)
                }
                Spacer()
                Text("Pinch to Zoom • Drag to Move").foregroundColor(.gray).font(.caption)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { cropImage() } }
            }
        }
    }

    @MainActor
    func cropImage() {
        let renderer = ImageRenderer(content: Image(uiImage: image).resizable().scaledToFill().scaleEffect(scale).offset(offset).frame(width: 300, height: 300).clipped())
        renderer.scale = UIScreen.main.scale
        if let croppedImage = renderer.uiImage { onCrop(croppedImage); dismiss() } else { dismiss() }
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
