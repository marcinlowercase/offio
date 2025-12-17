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
    @Environment(\.colorScheme) var colorScheme

    @State private var isListVisible = false
    @State private var showFileImporter = false
    
    // --- SELECTION MODE STATES ---
    @State private var isSelectionMode = false
    @State private var selectedTrackURLs = Set<URL>()
    
    // --- Photo Library States ---
    @State private var showImagePicker = false
    @State private var selectedImageItem: PhotosPickerItem? = nil
    
    // --- CROPPER STATES ---
    @State private var imageToCrop: UIImage? = nil
    @State private var showCropper = false
    @State private var isProcessingImage = false
    
    // --- RENAME STATES (For single tap rename logic if needed later) ---
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var targetTrackIndex: Int? = nil
    @FocusState private var isRenamingFieldFocused: Bool

    
    // --- HINT STATE ---
    @State private var showHint = true

    // Animation States
    @State private var dragOffset: CGFloat = 0
    // Neighbors
    @State private var prevImage: UIImage? = nil
    @State private var nextImage: UIImage? = nil
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if audioManager.audioFiles.isEmpty {
                    landingView
                        .transition(.opacity)
                } else {
                    mainInterface
                        // Apply drag gesture only to main interface to avoid conflicts
                        .gesture(dragGesture(geo: geo))
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
                
            }
            .animation(.easeInOut(duration: 0.4), value: audioManager.audioFiles.isEmpty)
            .statusBarHidden()
            // --- GLOBAL MODIFIERS ---
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
//            .alert("Rename Track", isPresented: $showRenameAlert) {
//                TextField("New Name", text: $renameText)
//                Button("Cancel", role: .cancel) { }
//                Button("Save") {
//                    if let idx = targetTrackIndex {
//                        withAnimation(.snappy) {
//                            audioManager.renameTrack(at: idx, to: renameText)
//                        }
//                    }
//                    targetTrackIndex = nil
//                }
//            }
            .onChange(of: audioManager.currentTrackIndex) { _, newIndex in
                updateNeighborImages(currentIndex: newIndex)
            }
            .onChange(of: audioManager.playStrategy) { _, _ in
                updateNeighborImages(currentIndex: audioManager.currentTrackIndex)
            }
            .onAppear {
                updateNeighborImages(currentIndex: audioManager.currentTrackIndex)
            }
        }        .id(colorScheme)

    }
    
    // MARK: - Views
    
    var landingView: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Tap to Import")
                    .foregroundColor(.primary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showFileImporter = true }
    }
    
    var mainInterface: some View {
        ZStack(alignment: .bottom) {
            Color(UIColor.systemBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                GeometryReader { innerGeo in
                    VStack(spacing: 0) {
                        let squareSize = innerGeo.size.width - 16
                        imageCarousel(geo: innerGeo, squareSize: squareSize)
                        
                        ZStack {
                            playingView
                                .opacity(isListVisible ? 0 : 1)
                                .animation(.easeInOut(duration: 0.3), value: isListVisible)
                                .allowsHitTesting(!isListVisible)
                            
                            listView(geo: innerGeo)
                                .offset(y: isListVisible ? 0 : innerGeo.size.height)
                                .opacity(isListVisible ? 1 : 0)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isListVisible)
                        }
                        .frame(maxHeight: .infinity)
                        .clipped()
                    }
                }
            }
            
            floatingControls.padding(.bottom, 20)
            if isProcessingImage {
                Color.black.opacity(0.4).ignoresSafeArea()
                ProgressView("Loading Image...").padding()
                    .glassEffect(.regular)
                    .cornerRadius(20)
            }
            
         
        }
//        .ignoresSafeArea(.keyboard, edges: showRenameAlert ? [] : .bottom)

    }
    
    // MARK: - Subviews
    
    var customRenameAlert: some View {
        ZStack {
            // 1. Dimmed Background (Tap to cancel)
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation {
                        showRenameAlert = false
                        isRenamingFieldFocused = false
                    }
                }
            
            // 2. The Input Box
            VStack(spacing: 15) {
                Text("Rename Track")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                TextField("Track Name", text: $renameText)
                    .focused($isRenamingFieldFocused) // Auto-focus
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .submitLabel(.done)
                    .onSubmit {
                        saveRename()
                    }
                
                HStack(spacing: 15) {
                    Button(action: {
                        withAnimation {
                            showRenameAlert = false
                            isRenamingFieldFocused = false
                        }
                    }) {
                        Text("Cancel")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(UIColor.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                    }
                    
                    Button(action: {
                        saveRename()
                    }) {
                        Text("Save")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.primary)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .cornerRadius(10)
                    }
                }
            }
            .padding(20)
            .background(.regularMaterial) // Glass effect background
            .cornerRadius(24)
            .padding(.horizontal, 20)
            .padding(.bottom, 10) // Some spacing from the keyboard
            // 👇 KEY: Align to bottom. SwiftUI automatically pushes this up when keyboard appears.
            .frame(maxHeight: .infinity, alignment: .bottom)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .zIndex(200) // Ensure it sits on top of everything
    }
    
    
       func saveRename() {
           if let idx = targetTrackIndex {
               withAnimation(.snappy) {
                   audioManager.renameTrack(at: idx, to: renameText)
               }
           }
           closeRename()
       }
       
       func closeRename() {
           withAnimation {
               showRenameAlert = false
               isRenamingFieldFocused = false
               targetTrackIndex = nil
           }
       }

    @ViewBuilder
    var floatingControls: some View {
        VStack(spacing: 20) {
            
            // MARK: 1. Rename Input Box (Appears on top)
            if showRenameAlert {
                
                TextField("Track Name", text: $renameText)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .cornerRadius(12)
                    .glassEffect(.regular)
                    .padding(.horizontal, 16)

                    .focused($isRenamingFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        saveRename()
                    }
            }
            
            // MARK: 2. The Two Buttons
            HStack(spacing: 50) {
                
                // --- LEFT BUTTON ---
                Button(action: {
                    if showRenameAlert {
                        // Action: CANCEL RENAME
                        closeRename()
                    } else if isSelectionMode {
                        // Action: CANCEL SELECTION
                        withAnimation(.spring()) {
                            isSelectionMode = false
                            selectedTrackURLs.removeAll()
                        }
                    } else {
                        // Action: STRATEGY / LIST
                        if isListVisible {
                            withAnimation(.spring()) { isListVisible = false }
                        } else {
                            audioManager.cyclePlayStrategy()
                        }
                    }
                }) {
                    // Icon Logic
                    let iconName: String = {
                        if showRenameAlert { return "xmark" }
                        if isSelectionMode { return "chevron.left" }
                        if isListVisible { return "chevron.down" }
                        return audioManager.playStrategy == .shuffle ? "shuffle" : "repeat"
                    }()
                    
                    // Color Logic
                    let color: Color = {
                        if showRenameAlert || isSelectionMode || isListVisible { return .primary }
                        return audioManager.playStrategy == .off ? .primary.opacity(0.1) : .primary
                    }()
                    
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
                
                // --- RIGHT BUTTON ---
                Button(action: {
                    if showRenameAlert {
                        // Action: SAVE RENAME
                        saveRename()
                    } else if isSelectionMode {
                        // Action: DELETE SELECTED
                        withAnimation(.spring()) {
                            audioManager.deleteTracks(urls: selectedTrackURLs)
                            isSelectionMode = false
                            selectedTrackURLs.removeAll()
                        }
                    } else {
                        // Action: IMPORT / REPEAT ONE
                        if isListVisible {
                            showFileImporter = true
                        } else {
                            audioManager.isRepeatOne.toggle()
                        }
                    }
                }) {
                    // Icon Logic
                    let iconName: String = {
                        if showRenameAlert { return "checkmark" }
                        if isSelectionMode { return "trash" }
                        if isListVisible { return "plus" }
                        return "repeat.1"
                    }()
                    
                    // Color Logic
                    let color: Color = {
                        if showRenameAlert { return .primary } // Checkmark
                        if isSelectionMode { return .red }     // Trash
                        if isListVisible { return .primary }   // Plus
                        return audioManager.isRepeatOne ? .primary : .primary.opacity(0.1)
                    }()
                    
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
    }
    

    @ViewBuilder
    func imageCarousel(geo: GeometryProxy, squareSize: CGFloat) -> some View {
        ZStack {
            renderImageView(image: prevImage, size: squareSize, placeHolder: audioManager.getPreviousTrackIndex() == nil ? "No Previous Track": "No Cover")
                .offset(x: -squareSize - 16.0 + dragOffset)
            
            renderImageView(image: nextImage, size: squareSize, placeHolder: audioManager.getNextTrackIndex() == nil ? "No Next Track": "No Cover")
                .offset(x: squareSize + 16.0 + dragOffset)
            
            renderImageView(image: audioManager.trackImage, size: squareSize, placeHolder: !showHint ? "No Cover": "Long Press to Add Cover")
                .overlay(alignment: .topLeading) { // 1. Align to top-left
                       Group {
                           if !audioManager.isPlaying {
                               Image(systemName: "play.circle.fill")
                                   .resizable()
                                   .frame(width: 24, height: 24) // Slightly smaller for the corner looks better
                                   .foregroundColor(.white.opacity(0.8))
                                   .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 0)
                                   .padding(8) // 2. Add padding so it's not flush with the edge
                           }
                       }
                   }
                .offset(x: dragOffset)
                .onLongPressGesture {
                    let generator = UIImpactFeedbackGenerator(style: .soft)
                    generator.impactOccurred()
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
    
    func listView(geo: GeometryProxy) -> some View {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    
                    Color.clear.frame(height: 20)
                    
                    ForEach(audioManager.audioFiles, id: \.self) { url in
                        if let index = audioManager.audioFiles.firstIndex(of: url) {
                            
                            let isCurrent = audioManager.currentTrackIndex == index
                            let isSelected = selectedTrackURLs.contains(url)
                            
                            // ROW CONTENT (No Button Wrapper)
                            HStack {
                                // SELECTION INDICATOR
                                if isSelectionMode {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundColor(isSelected ? .primary : .secondary)
                                        .padding(.trailing, 8)
                                        .transition(.scale.combined(with: .opacity))
                                }
                                
                                Text(audioManager.getDisplayName(for: url))
                                    .fontWeight(isCurrent ? .bold : .regular)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer()
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .animation(.easeInOut(duration: 0.3), value: isCurrent)
                            .glassEffect(isCurrent ? .clear : .regular)
                            .cornerRadius(20)
                            .foregroundColor(isCurrent ? .primary : .primary.opacity(0.5))
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle()) // Makes empty space clickable
                            
                            // MARK: - GESTURES
                            // 1. Long Press: Enters Selection Mode
                            .onLongPressGesture {
                                if !isSelectionMode {
                                    let generator = UIImpactFeedbackGenerator(style: .soft)
                                    generator.impactOccurred()
                                    withAnimation(.spring()) {
                                        isSelectionMode = true
                                        selectedTrackURLs.insert(url)
                                    }
                                }
                            }
                            // 2. Tap: Plays (Normal) or Toggles (Selection Mode)
                            // This will NOT fire if the Long Press gesture succeeds.
                            .onTapGesture {
                                if isSelectionMode {
                                    withAnimation(.snappy) {
                                        if isSelected {
                                            selectedTrackURLs.remove(url)
                                            // Optional: Exit mode if nothing left selected
                                            if selectedTrackURLs.isEmpty {
                                                isSelectionMode = false
                                            }
                                        } else {
                                            selectedTrackURLs.insert(url)
                                        }
                                    }
                                } else {
                                    withAnimation { showHint = false }
                                    audioManager.playTrack(at: index)
                                }
                            }
                        }
                    }
                    
                    Color.clear.frame(height: 100)
                }
            }
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
        }
    var playingView: some View {
        VStack(spacing: 0) {
            
            if !showRenameAlert {
                Text(audioManager.trackName)
                    .font(.title2)
                    .multilineTextAlignment(.leading)
                    .id(audioManager.trackName)
                    .transition(.push(from: .bottom).combined(with: .opacity))
                    .onLongPressGesture {
                        let generator = UIImpactFeedbackGenerator(style: .soft)
                        generator.impactOccurred()
                        
                        if let current = audioManager.currentTrackIndex {
                            targetTrackIndex = current
                            renameText = audioManager.trackName
                            withAnimation {
                                showRenameAlert = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    isRenamingFieldFocused = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
            }
            
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
    }
    
    // MARK: - Helpers
    
    func dragGesture(geo: GeometryProxy) -> some Gesture {
        // Minimum distance added to prevent click conflicts
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onChanged { value in
                // Only allow vertical swipes if we are NOT in selection mode
                // (Optional: you might want to block swiping while selecting to avoid confusion)
                guard !isSelectionMode else { return }
                
                if showHint { withAnimation { showHint = false } }
                if abs(value.translation.width) > abs(value.translation.height) {
                    dragOffset = value.translation.width
                }
            }
            .onEnded { value in
                guard !isSelectionMode else { return } // Disable gestures during selection mode
                
                let horizontalAmount = value.translation.width
                let verticalAmount = value.translation.height
                
                if abs(verticalAmount) > abs(horizontalAmount) {
                    if abs(verticalAmount) > 50 {
                        if isListVisible {
                            if verticalAmount > 0 {
                                withAnimation(.spring()) { isListVisible = false }
                            }
                        } else {
                            if verticalAmount < 0 {
                                withAnimation(.spring()) { isListVisible = true }
                            } else {
                                audioManager.seek(to: 0)
                                let generator = UIImpactFeedbackGenerator(style: .soft)
                                generator.impactOccurred()
                               
                            }
                        }
                    }
                    withAnimation(.spring()) { dragOffset = 0 }
                    return
                }
                
                let screenWidth = geo.size.width
                if horizontalAmount < -100 {
                    if audioManager.getNextTrackIndex() != nil {
                        withAnimation(.easeOut(duration: 0.2)) {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            dragOffset = -screenWidth
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            audioManager.nextTrack()
                            var t = Transaction(animation: nil); t.disablesAnimations = true
                            withTransaction(t) { dragOffset = 0 }
                        }
                    } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { dragOffset = 0 } }
                } else if horizontalAmount > 100 {
                    if audioManager.getPreviousTrackIndex() != nil {
                        withAnimation(.easeOut(duration: 0.2)) {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            dragOffset = screenWidth
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            audioManager.previousTrack(force: true)
                            var t = Transaction(animation: nil); t.disablesAnimations = true
                            withTransaction(t) { dragOffset = 0 }
                        }
                    } else { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { dragOffset = 0 } }
                } else { withAnimation(.spring()) { dragOffset = 0 } }
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
            } else { await MainActor.run { isProcessingImage = false } }
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
        if let nextIdx = audioManager.getNextTrackIndex() { nextImage = audioManager.getImage(at: nextIdx) } else { nextImage = nil }
        if let prevIdx = audioManager.getPreviousTrackIndex() { prevImage = audioManager.getImage(at: prevIdx) } else { prevImage = nil }
    }
}

struct ImageCropper: View {
    var image: UIImage
    var onCrop: (UIImage) -> Void
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.displayScale) var displayScale
    @Environment(\.colorScheme) var colorScheme
    
    // State variables
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    let cropSize: CGFloat = 300
    
    // 👇 NEW: Calculate the actual size of the image when 'scaledToFill' fits it into the box.
    // This accounts for aspect ratio (Portrait/Landscape) so we know how much we can drag.
    var imageSizeInFrame: CGSize {
        let widthRatio = cropSize / image.size.width
        let heightRatio = cropSize / image.size.height
        
        // scaledToFill uses the larger ratio to ensure the crop box is completely covered
        let ratio = max(widthRatio, heightRatio)
        
        return CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            
            // 1. Background
            Color(UIColor.systemBackground).ignoresSafeArea()

            // 2. Cropping Content
            VStack {
                Spacer()
                
                // Crop Area
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cropSize, height: cropSize)
                        .scaleEffect(scale)
                        .offset(offset)
                        // 👇 GESTURES
                        .gesture(
                            DragGesture()
                                .onChanged { v in
                                    let tempWidth = lastOffset.width + v.translation.width
                                    let tempHeight = lastOffset.height + v.translation.height
                                    
                                    // 1. Calculate actual current size of the image
                                    let currentWidth = imageSizeInFrame.width * scale
                                    let currentHeight = imageSizeInFrame.height * scale
                                    
                                    // 2. Calculate how much "overhang" exists (divided by 2 because it's centered)
                                    // This allows dragging even at scale 1.0 if the image is rectangular
                                    let rangeX = (currentWidth - cropSize) / 2
                                    let rangeY = (currentHeight - cropSize) / 2
                                    
                                    // 3. Clamp the drag so we don't see black bars
                                    // If range is positive (overhang), allow drag. If negative or zero, lock to 0.
                                    let clampedX = rangeX > 0 ? min(rangeX, max(-rangeX, tempWidth)) : 0
                                    let clampedY = rangeY > 0 ? min(rangeY, max(-rangeY, tempHeight)) : 0
                                    
                                    offset = CGSize(width: clampedX, height: clampedY)
                                }
                                .onEnded { _ in lastOffset = offset }
                                // Combine with Zoom
                                .simultaneously(with: MagnificationGesture()
                                    .onChanged { v in
                                        let newScale = lastScale * v
                                        scale = newScale >= 1.0 ? newScale : 1.0
                                        
                                        // Recalculate bounds while zooming out to ensure image snaps back if needed
                                        let currentWidth = imageSizeInFrame.width * scale
                                        let currentHeight = imageSizeInFrame.height * scale
                                        
                                        let rangeX = (currentWidth - cropSize) / 2
                                        let rangeY = (currentHeight - cropSize) / 2
                                        
                                        let clampedX = rangeX > 0 ? min(rangeX, max(-rangeX, offset.width)) : 0
                                        let clampedY = rangeY > 0 ? min(rangeY, max(-rangeY, offset.height)) : 0
                                        
                                        offset = CGSize(width: clampedX, height: clampedY)
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                        lastOffset = offset
                                    }
                                )
                        )
                    
                    // White Border
                    Rectangle()
                        .stroke(Color.primary, lineWidth: 2)
                        .frame(width: cropSize, height: cropSize)
                        .allowsHitTesting(false)
                }
                .mask(Rectangle().frame(width: cropSize, height: cropSize))
                // Ensure the gesture area catches touches
                .contentShape(Rectangle())
                
                Spacer()
                
                Text("Pinch to Zoom • Drag to Move")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .padding(.bottom, 120)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // 3. Floating Buttons
            HStack(spacing: 50) {
                
                // Cancel
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .frame(width: 60, height: 60)
                        .glassEffect(.regular.interactive())
                        .clipShape(Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .glassEffect(.regular.interactive())
                
                Spacer().frame(width: 64)
                
                // Done
                Button(action: { cropImage() }) {
                    Image(systemName: "checkmark")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .frame(width: 60, height: 60)
                        .glassEffect(.regular.interactive())
                        .clipShape(Circle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .glassEffect(.regular.interactive())
            }
            .padding(.bottom, 20)
        }
        .id(colorScheme)
        .statusBarHidden()
    }

    @MainActor
    func cropImage() {
        let renderer = ImageRenderer(content:
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: cropSize, height: cropSize)
                .scaleEffect(scale)
                .offset(offset)
                .clipped()
        )
        
        renderer.scale = displayScale
        
        if let croppedImage = renderer.uiImage {
            onCrop(croppedImage)
            dismiss()
        } else {
            dismiss()
        }
    }
}
extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
