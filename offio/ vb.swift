////
////   vb.swift
////  offio
////
////  Created by Theo on 12/16/25.
////
//
//
//    @Namespace private var listViewNamespace
//    var listView: some View {
//        VStack {
//            List {
//                ForEach(audioManager.audioFiles.indices, id: \.self) { index in
//                    let url = audioManager.audioFiles[index]
//                    let isCurrent = audioManager.currentTrackIndex == index
//
//                    HStack {
//                        Text(audioManager.getDisplayName(for: url))
//
//                            .fontWeight(audioManager.currentTrackIndex == index ? .black : .regular)
//                            .lineLimit(1)
//                            .truncationMode(.tail)
//                        Spacer() // Ensures the background fills the width
//                    }
//
//                    // Add padding inside the "bubble"
//                    .padding(.vertical, 12)
//                    .padding(.horizontal)
//
//                    // Background Styling
//                    .background(isCurrent ? Color.primary : Color.clear)
//                    .glassEffect(isCurrent ? .regular.interactive() : .clear.interactive())
//                    .glassEffectID("item_\(index)", in: listViewNamespace)
//                    .cornerRadius(20)
//
//                    // Text Color Styling (Invert color if selected)
//                    .foregroundColor( .primary)
//
//                    .animation(.easeInOut(duration: 0.3), value: isCurrent)
//
//
//                    // Remove the List line separator
//                    .listRowSeparator(.hidden)
//
//                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
//
//
//
//                    .contentShape(Rectangle())
//
//                    .onTapGesture {
//                        withAnimation { showHint = false }
//                        audioManager.playTrack(at: index)
//                    }
//                }
//            }
//            .listStyle(.plain)
//
//            HStack (spacing: 50) {
//                Button(action: { withAnimation(.spring()) { isListVisible = false } }) {
//                    Image(systemName: "chevron.down")
//                        .font(.title2)
//                        .foregroundColor(.primary)
//                        .frame(width: 60, height: 60)
//                    // 2. Glass effect applied to the content
//                        .glassEffect(.regular.interactive())
//                    // 3. Clip the final view into a circle
//                        .clipShape(Circle())
//                }
//                .glassEffect(.regular.interactive())
//                Spacer().frame(width: 64)
//
//                Button(action: { showFileImporter = true }) {
//                    Image(systemName: "plus")
//                        .font(.title2)
//                        .foregroundColor(.primary)
//                        .frame(width: 60, height: 60)
//                    // 2. Glass effect applied to the content
//                        .glassEffect(.regular.interactive())
//                    // 3. Clip the final view into a circle
//                        .clipShape(Circle())
//                }
//
//                .glassEffect(.regular.interactive())
//
//            }
//            .padding()
//
////            .background(Color(UIColor.secondarySystemBackground))
//        }
//        .transition(.move(edge: .bottom))
//    }
