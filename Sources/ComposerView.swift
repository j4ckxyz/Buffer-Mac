import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ComposerView: View {
    let onLogout: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isComposerFocused: Bool
    
    // Core Composer State
    @State private var postText = Storage.draftText {
        didSet {
            Storage.draftText = postText
        }
    }
    @State private var channels: [Storage.CachedChannel] = Storage.cachedChannels
    @State private var selectedChannels: Set<String> = Storage.selectedChannelIds
    @State private var attachments: [Attachment] = []
    
    // UI states
    @State private var isChannelSelectorExpanded = false
    @State private var isLoadingChannels = false
    @State private var isPosting = false
    @State private var postingStatus: String? = nil
    @State private var statusIsError = false
    @State private var isDragTargeted = false
    
    // New Feature States
    @State private var clipboardImage: NSImage? = nil
    @State private var clipboardFileUrl: URL? = nil
    @State private var clipboardWebUrl: String? = nil
    @State private var selectedAttachmentId: UUID? = nil
    @State private var postMode: String = UserDefaults.standard.string(forKey: "default_post_mode") ?? "shareNow"
    @State private var detectedLinkURL: URL? = nil
    @State private var linkPreview: LinkPreviewMetadata? = nil
    @State private var isFetchingLinkPreview = false
    @State private var linkPreviewTask: Task<Void, Never>? = nil
    
    // Emoji Autocomplete State
    @State private var emojiSearchQuery: String? = nil
    
    @ObservedObject private var publisher = BackgroundPublisher.shared
    @ObservedObject private var updater = AppUpdater.shared
    
    struct Attachment: Identifiable {
        let id = UUID()
        let localURL: URL
        var uploadedURL: String?
        var progress: Double = 0.0
        var isVideo: Bool
        var error: String? = nil
        var altText: String = ""
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Navigation Header
            HStack {
                Menu {
                    Button(action: openSettings) {
                        Label("Settings...", systemImage: "slider.horizontal.3")
                    }
                    Button(action: openAbout) {
                        Label("About Buffer Composer", systemImage: "info.circle")
                    }
                    Button(action: triggerCheckForUpdates) {
                        Label("Check for Updates...", systemImage: "arrow.down.circle")
                    }
                    Divider()
                    Button(action: refreshChannels) {
                        Label("Refresh Profiles", systemImage: "arrow.clockwise")
                    }
                    Button(action: onLogout) {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Divider()
                    Button(action: { NSApp.terminate(nil) }) {
                        Label("Quit Buffer Composer", systemImage: "power")
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                }
                .menuStyle(BorderlessButtonMenuStyle())
                .menuIndicator(.hidden)
                .frame(width: 24, height: 24)
                .padding(.leading, 8)
                
                Spacer()
                
                // Active Profiles Pill Button
                Button(action: {
                    withAnimation(layoutAnimation) {
                        isChannelSelectorExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        if selectedChannels.isEmpty {
                            Text("No Profiles Selected")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.orange)
                        } else {
                            HStack(spacing: 3) {
                                ForEach(Array(selectedChannels.prefix(4)), id: \.self) { chanId in
                                    if let channel = channels.first(where: { $0.id == chanId }) {
                                        ChannelBadge(service: channel.service)
                                    }
                                }
                            }
                            
                            Text("\(selectedChannels.count) Profile\(selectedChannels.count > 1 ? "s" : "")")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.gray)
                            .rotationEffect(.degrees(isChannelSelectorExpanded ? 180 : 0))
                            .animation(feedbackAnimation, value: isChannelSelectorExpanded)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .modifier(ProfilePillModifier())
                }
                .buttonStyle(ScaleButtonStyle())
                
                Spacer()
                
                // Active Status indicator (Loading profiles)
                if isLoadingChannels {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 24, height: 24)
                } else {
                    Spacer().frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Group {
                    if #available(macOS 26, *) {
                        Color.clear
                    } else {
                        Color(NSColor.windowBackgroundColor).opacity(0.4)
                    }
                }
            )
            
            // MARK: - Expanded Channel Checklist Dropdown
            if isChannelSelectorExpanded {
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 2) {
                            if channels.isEmpty {
                                Text("No profiles found. Refresh to load.")
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundColor(.gray)
                                    .padding(.vertical, 12)
                            } else {
                                ForEach(channels, id: \.id) { channel in
                                    Button(action: { toggleChannel(channel.id) }) {
                                        HStack {
                                            ChannelBadge(service: channel.service)
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(channel.name)
                                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                                    .foregroundColor(.primary)
                                                Text(channel.service.capitalized)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.gray)
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: selectedChannels.contains(channel.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(selectedChannels.contains(channel.id) ? .blue : Color(NSColor.tertiaryLabelColor))
                                                .font(.system(size: 14))
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                        .background(selectedChannels.contains(channel.id) ? Color.blue.opacity(0.08) : Color.clear)
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 140)
                    
                    Divider()
                        .background(Color(NSColor.separatorColor))
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // MARK: - App Updater Status Banner
            if let updateStatus = updater.statusMessage {
                HStack(spacing: 8) {
                    if updater.isChecking {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }
                    Text(updateStatus)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if !updater.isChecking {
                        Button(action: {
                            withAnimation {
                                AppUpdater.shared.statusMessage = nil
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.blue.opacity(0.08))
                .overlay(
                    Rectangle()
                        .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // MARK: - Scrollable Composer Area
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // MARK: - Clipboard Suggestion Banner (Removed for native Cmd+V flow)
                    
                    // MARK: - Link Card Preview (for URL posts)
                    if let preview = linkPreview {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                if let imageURL = preview.imageURL {
                                    AsyncImage(url: imageURL) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        case .failure:
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(NSColor.controlBackgroundColor))
                                                .overlay(Image(systemName: "photo").foregroundColor(.gray))
                                        case .empty:
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(NSColor.controlBackgroundColor))
                                                .overlay(ProgressView().scaleEffect(0.6))
                                        @unknown default:
                                            EmptyView()
                                        }
                                    }
                                    .frame(width: 46, height: 46)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preview.title)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    if let siteName = preview.siteName {
                                        Text(siteName)
                                            .font(.system(size: 10, design: .rounded))
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                    
                                    if let source = preview.imageSource {
                                        Text("Card image source: \(source)")
                                            .font(.system(size: 9, weight: .medium, design: .rounded))
                                            .foregroundColor(.blue.opacity(0.9))
                                    }
                                }
                                
                                Spacer(minLength: 0)
                            }
                            
                            if shouldShowBlueskyLinkCardAssist {
                                Text("Bluesky card assist: this link will be sent as a rich card instead of a photo attachment.")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundColor(.gray)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue.opacity(0.18), lineWidth: 1)
                        )
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    // MARK: - Composer Text & Attachment Editor Area
                    ZStack(alignment: .topLeading) {
                        // Drag Backdrop Highlight
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDragTargeted ? Color.blue.opacity(0.08) : Color.primary.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        isDragTargeted
                                        ? Color.blue
                                        : (isComposerFocused ? Color.primary.opacity(0.2) : Color.primary.opacity(0.06)),
                                        lineWidth: isDragTargeted ? 2 : (isComposerFocused ? 1.5 : 1)
                                    )
                            )
                            .animation(feedbackAnimation, value: isDragTargeted)
                            .animation(feedbackAnimation, value: isComposerFocused)
                        
                        VStack(spacing: 8) {
                            ZStack(alignment: .topLeading) {
                                // Interactive Text Area
                                TextEditor(text: $postText)
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.primary)
                                    .padding(.top, 12)
                                    .padding(.horizontal, 12)
                                    .frame(height: 120)
                                    .scrollContentBackground(.hidden)
                                    .focused($isComposerFocused)
                                .onChange(of: postText) { newValue in
                                    Storage.draftText = newValue
                                    scheduleLinkPreviewUpdate(for: newValue)
                                    updateEmojiSuggestions(for: newValue)
                                }
                                
                                if postText.isEmpty {
                                    Text("What would you like to share?")
                                        .font(.system(size: 13, design: .rounded))
                                        .foregroundColor(.gray.opacity(0.8))
                                        .padding(.top, 12)
                                        .padding(.horizontal, 17)
                                        .allowsHitTesting(false)
                                }
                            }
                            
                            // MARK: - Media Thumbnails Drawer
                            if !attachments.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(attachments) { item in
                                            ZStack(alignment: .topTrailing) {
                                                // Thumbnail image or video icon with custom selection frame
                                                ZStack {
                                                    if item.isVideo {
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(Color.gray.opacity(0.2))
                                                            .frame(width: 60, height: 60)
                                                        
                                                        Image(systemName: "video.fill")
                                                            .font(.system(size: 18))
                                                            .foregroundColor(.secondary)
                                                    } else if let image = NSImage(contentsOf: item.localURL) {
                                                        Image(nsImage: image)
                                                            .resizable()
                                                            .aspectRatio(contentMode: .fill)
                                                            .frame(width: 60, height: 60)
                                                            .clipped()
                                                            .cornerRadius(8)
                                                    } else {
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .fill(Color.gray.opacity(0.2))
                                                            .frame(width: 60, height: 60)
                                                        
                                                        Image(systemName: "photo")
                                                            .font(.system(size: 18))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    
                                                    // Progress overlay
                                                    if item.uploadedURL == nil && item.error == nil {
                                                        ZStack {
                                                            Color.black.opacity(0.5)
                                                                .cornerRadius(8)
                                                            
                                                            VStack(spacing: 2) {
                                                                ProgressView(value: item.progress)
                                                                    .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                                                    .padding(.horizontal, 8)
                                                                    .scaleEffect(y: 0.8)
                                                                
                                                                Text("\(Int(item.progress * 100))%")
                                                                    .font(.system(size: 8, weight: .bold))
                                                                    .foregroundColor(.white)
                                                            }
                                                        }
                                                    }
                                                    
                                                    // Error Badge
                                                    if let _ = item.error {
                                                        ZStack {
                                                            Color.black.opacity(0.6)
                                                                .cornerRadius(8)
                                                            Image(systemName: "exclamationmark.triangle.fill")
                                                                .foregroundColor(.red)
                                                                .font(.system(size: 16))
                                                        }
                                                    }
                                                    
                                                    // ALT Text Badge
                                                    if !item.isVideo && item.uploadedURL != nil {
                                                        VStack {
                                                            Spacer()
                                                            HStack {
                                                                Text("ALT")
                                                                    .font(.system(size: 7, weight: .black))
                                                                    .foregroundColor(.white)
                                                                    .padding(.horizontal, 4)
                                                                    .padding(.vertical, 2)
                                                                    .background(item.altText.isEmpty ? Color.black.opacity(0.6) : Color.blue)
                                                                    .cornerRadius(4)
                                                                Spacer()
                                                            }
                                                        }
                                                        .padding(3)
                                                    }
                                                }
                                                .frame(width: 60, height: 60)
                                                .shadow(radius: 2)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(selectedAttachmentId == item.id ? Color.blue : Color.clear, lineWidth: 2)
                                                )
                                                .contentShape(Rectangle())
                                                .onTapGesture {
                                                    withAnimation(feedbackAnimation) {
                                                        if selectedAttachmentId == item.id {
                                                            selectedAttachmentId = nil
                                                        } else {
                                                            selectedAttachmentId = item.id
                                                        }
                                                    }
                                                }
                                                
                                                // Remove Item Button
                                                Button(action: {
                                                    if selectedAttachmentId == item.id {
                                                        selectedAttachmentId = nil
                                                    }
                                                    removeAttachment(item.id)
                                                }) {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .foregroundColor(.white)
                                                        .background(Color.black.clipShape(Circle()))
                                                        .font(.system(size: 14))
                                                }
                                                .buttonStyle(ScaleButtonStyle())
                                                .offset(x: 5, y: -5)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 12)
                                }
                                .frame(height: 72)
                            }
                            
                            // MARK: - Inline Alt Text Editor
                            if let selectedId = selectedAttachmentId,
                               let index = attachments.firstIndex(where: { $0.id == selectedId }),
                               !attachments[index].isVideo {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ALT TEXT FOR SELECTED IMAGE")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundColor(.blue)
                                        .tracking(1.0)
                                    
                                    TextField("Describe this image for screen readers...", text: Binding(
                                        get: { attachments[index].altText },
                                        set: { attachments[index].altText = $0 }
                                    ))
                                    .textFieldStyle(PlainTextFieldStyle())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                                    )
                                    .foregroundColor(.primary)
                                    .font(.system(size: 11, design: .rounded))
                                }
                                .padding(.horizontal, 24)
                                .padding(.bottom, 12)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .padding(12)
                    .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDragTargeted) { providers in
                        handleFileDrop(providers: providers)
                    }
                    
                    // MARK: - Character count and Add buttons panel
                    HStack {
                        // Media Add Utilities
                        #if compiler(<6.2)
                        HStack(spacing: 12) {
                            Button(action: { selectLocalMedia(isVideo: false) }) {
                                Image(systemName: "photo")
                                    .font(.system(size: 15))
                                    .foregroundColor(canAddImages ? .blue : Color(NSColor.disabledControlTextColor))
                                    .help("Attach images (up to 4)")
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .disabled(!canAddImages)
                            
                            Button(action: { selectLocalMedia(isVideo: true) }) {
                                Image(systemName: "video")
                                    .font(.system(size: 15))
                                    .foregroundColor(canAddVideo ? .blue : Color(NSColor.disabledControlTextColor))
                                    .help("Attach a video (up to 1)")
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .disabled(!canAddVideo)
                            
                            if hasClipboardSuggestion {
                                Button(action: attachFromClipboard) {
                                    Image(systemName: "doc.on.clipboard.fill")
                                        .font(.system(size: 15))
                                        .foregroundColor(.blue)
                                        .help("Paste media from clipboard (Cmd+V) - \(clipboardMessage)")
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .keyboardShortcut("v", modifiers: [.command])
                                .transition(.opacity.combined(with: .scale))
                            }
                        }
                        .padding(.horizontal, 6)
                        #else
                        if #available(macOS 26, *) {
                            GlassEffectContainer {
                                HStack(spacing: 12) {
                                    Button(action: { selectLocalMedia(isVideo: false) }) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 15))
                                            .foregroundColor(canAddImages ? .blue : Color(NSColor.disabledControlTextColor))
                                            .help("Attach images (up to 4)")
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                    .disabled(!canAddImages)
                                    
                                    Button(action: { selectLocalMedia(isVideo: true) }) {
                                        Image(systemName: "video")
                                            .font(.system(size: 15))
                                            .foregroundColor(canAddVideo ? .blue : Color(NSColor.disabledControlTextColor))
                                            .help("Attach a video (up to 1)")
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                    .disabled(!canAddVideo)
                                    
                                    if hasClipboardSuggestion {
                                        Button(action: attachFromClipboard) {
                                            Image(systemName: "doc.on.clipboard.fill")
                                                .font(.system(size: 15))
                                                .foregroundColor(.blue)
                                                .help("Paste media from clipboard (Cmd+V) - \(clipboardMessage)")
                                        }
                                        .buttonStyle(ScaleButtonStyle())
                                        .keyboardShortcut("v", modifiers: [.command])
                                        .transition(.opacity.combined(with: .scale))
                                    }
                                }
                            }
                            .padding(.horizontal, 6)
                        } else {
                            HStack(spacing: 12) {
                                Button(action: { selectLocalMedia(isVideo: false) }) {
                                    Image(systemName: "photo")
                                        .font(.system(size: 15))
                                        .foregroundColor(canAddImages ? .blue : Color(NSColor.disabledControlTextColor))
                                        .help("Attach images (up to 4)")
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .disabled(!canAddImages)
                                
                                Button(action: { selectLocalMedia(isVideo: true) }) {
                                    Image(systemName: "video")
                                        .font(.system(size: 15))
                                        .foregroundColor(canAddVideo ? .blue : Color(NSColor.disabledControlTextColor))
                                        .help("Attach a video (up to 1)")
                                }
                                .buttonStyle(ScaleButtonStyle())
                                .disabled(!canAddVideo)
                                
                                if hasClipboardSuggestion {
                                    Button(action: attachFromClipboard) {
                                        Image(systemName: "doc.on.clipboard.fill")
                                            .font(.system(size: 15))
                                            .foregroundColor(.blue)
                                            .help("Paste media from clipboard (Cmd+V) - \(clipboardMessage)")
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                    .keyboardShortcut("v", modifiers: [.command])
                                    .transition(.opacity.combined(with: .scale))
                                }
                            }
                            .padding(.horizontal, 6)
                        }
                        #endif
                        
                        Spacer()
                        
                        // Character Count
                        let count = postText.count
                        let limit = characterLimit
                        if isThreaded {
                            HStack(spacing: 4) {
                                Text("🧵 Thread: \(threadSegments.count) posts")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(.blue)
                                Text("(\(count) / \(limit))")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundColor(.gray)
                            }
                        } else {
                            Text("\(count) / \(limit)")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(count > limit ? .red : (count > limit - 20 ? .orange : .gray))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
            }
            
            // MARK: - Emoji Autocomplete Suggestions
            if let query = emojiSearchQuery {
                let matches = getEmojiMatches(for: query)
                if !matches.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(query.isEmpty ? "SUGGESTED EMOJIS" : "EMOJI MATCHES FOR :\(query)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                            .tracking(1.0)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(matches, id: \.shortcode) { item in
                                    Button(action: { selectEmoji(item.shortcode, emoji: item.emoji) }) {
                                        HStack(spacing: 4) {
                                            Text(item.emoji)
                                                .font(.system(size: 16))
                                            Text(":\(item.shortcode):")
                                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(Color.primary.opacity(0.06))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                        }
                    }
                    .background(Color.primary.opacity(0.04))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // MARK: - Bottom Actions & Status Pane
            VStack(spacing: 8) {
                if let status = postingStatus {
                    HStack(spacing: 6) {
                        if isPosting || isUploadingMedia {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundColor(statusIsError ? .red : .green)
                                .font(.system(size: 12))
                        }
                        
                        Text(status)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(statusIsError ? .red : (isPosting || isUploadingMedia ? .gray : .green))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                
                // Standard single action button (decluttered and FOSS)
                Button(action: postToQueue) {
                    HStack {
                        if isPosting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Text(buttonLabelText)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(canSubmit ? .white : .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Group {
                            if #available(macOS 26, *) {
                                Color.clear
                            } else {
                                canSubmit ? Color.blue : Color.primary.opacity(0.1)
                            }
                        }
                    )
                    .cornerRadius(10)
                }
                .modifier(GlassButtonModifier())
                .buttonStyle(ScaleButtonStyle())
                .disabled(!canSubmit || isPosting)
                .keyboardShortcut(.return, modifiers: [.command])
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(Color.clear)
        }
        .onAppear {
            loadInitialSetup()
            scheduleLinkPreviewUpdate(for: postText)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Automatically scan clipboard whenever popover active state changes
            checkClipboard()
        }
        .onChange(of: publisher.isPosting) { newValue in
            isPosting = newValue
            if newValue {
                postingStatus = publisher.postingStatus
                statusIsError = false
            }
        }
        .onChange(of: publisher.lastStatusMessage) { newValue in
            if !newValue.isEmpty {
                showStatus(newValue, isError: publisher.statusIsError)
            }
        }
        .onChange(of: publisher.triggerClearComposer) { newValue in
            if newValue {
                postText = ""
                attachments = []
                Storage.draftText = ""
                selectedAttachmentId = nil
                linkPreview = nil
                detectedLinkURL = nil
                linkPreviewTask?.cancel()
                publisher.triggerClearComposer = false
            }
        }
        .onDisappear {
            linkPreviewTask?.cancel()
        }
        .animation(layoutAnimation, value: isChannelSelectorExpanded)
        .animation(layoutAnimation, value: hasClipboardSuggestion)
        .animation(layoutAnimation, value: selectedAttachmentId)
        .animation(layoutAnimation, value: postingStatus)
        .animation(layoutAnimation, value: emojiSearchQuery)
        .onPasteCommand(of: [UTType.fileURL, UTType.image]) { providers in
            handlePasteProviders(providers)
        }
    }
    
    // MARK: - State Logic & Constraints Helpers
    
    private var hasClipboardSuggestion: Bool {
        clipboardImage != nil || clipboardFileUrl != nil || clipboardWebUrl != nil
    }
    
    private var isBlueskySelected: Bool {
        selectedChannels.contains { channelId in
            channels.first(where: { $0.id == channelId })?.service.lowercased() == "bluesky"
        }
    }
    
    private var shouldShowBlueskyLinkCardAssist: Bool {
        isBlueskySelected && (linkPreview?.imageURL != nil)
    }
    
    private var shouldFetchLinkPreview: Bool {
        isBlueskySelected && attachments.isEmpty
    }
    
    private var feedbackAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.25, 1, 0.5, 1, duration: 0.14)
    }
    
    private var layoutAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.25, 1, 0.5, 1, duration: 0.28)
    }
    
    private var isUploadingMedia: Bool {
        attachments.contains(where: { $0.uploadedURL == nil && $0.error == nil })
    }
    
    private var canAddImages: Bool {
        // Can add image if no video is attached AND total images < 4
        !attachments.contains(where: { $0.isVideo }) && attachments.count < 4
    }
    
    private var canAddVideo: Bool {
        // Can add video if NO attachments are currently present
        attachments.isEmpty
    }
    
    private var canSubmit: Bool {
        // Must have at least one channel selected AND text composer holds content (or media is present)
        // AND not currently posting, not currently uploading
        !selectedChannels.isEmpty &&
        (!postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) &&
        !isPosting &&
        !isUploadingMedia
    }
    
    private var characterLimit: Int {
        // Dynamic character limit check. Finds the lowest limit among selected social services
        if selectedChannels.isEmpty { return 500 }
        
        var minLimit = 60000
        for chanId in selectedChannels {
            if let service = channels.first(where: { $0.id == chanId })?.service {
                switch service.lowercased() {
                case "twitter", "x": minLimit = min(minLimit, 280)
                case "bluesky": minLimit = min(minLimit, 300)
                case "mastodon": minLimit = min(minLimit, 500)
                case "threads": minLimit = min(minLimit, 500)
                case "pinterest": minLimit = min(minLimit, 500)
                case "instagram": minLimit = min(minLimit, 2200)
                case "tiktok": minLimit = min(minLimit, 2200)
                case "linkedin": minLimit = min(minLimit, 3000)
                default: minLimit = min(minLimit, 500)
                }
            }
        }
        return minLimit
    }
    
    // MARK: - Setup and Synchronization
    
    private func loadInitialSetup() {
        // Apply persisted defaults and load cached state immediately.
        let persistedMode = UserDefaults.standard.string(forKey: "default_post_mode") ?? "shareNow"
        self.postMode = (persistedMode == "addToQueue") ? "addToQueue" : "shareNow"
        self.channels = Storage.cachedChannels
        self.selectedChannels = Storage.selectedChannelIds
        
        // Refresh channel profiles from API in the background ONLY if our local cache is empty
        if self.channels.isEmpty {
            refreshChannels()
        }
    }
    
    private func refreshChannels() {
        guard let token = KeychainHelper.getToken() else { return }
        
        isLoadingChannels = true
        
        Task {
            do {
                let account = try await BufferAPI.shared.verifyTokenAndGetOrganizations(token: token)
                var allChannels: [Storage.CachedChannel] = []
                
                for org in account.organizations {
                    let orgChannels = try await BufferAPI.shared.fetchChannels(forOrganizationId: org.id, token: token)
                    for item in orgChannels {
                        allChannels.append(Storage.CachedChannel(id: item.id, name: item.name, service: item.service))
                    }
                }
                
                await MainActor.run {
                    self.channels = allChannels
                    Storage.cachedChannels = allChannels
                    
                    // If selection is empty, auto-check the first available profile
                    if self.selectedChannels.isEmpty, let first = allChannels.first {
                        self.selectedChannels.insert(first.id)
                        Storage.selectedChannelIds = self.selectedChannels
                    }
                    
                    isLoadingChannels = false
                }
            } catch {
                await MainActor.run {
                    isLoadingChannels = false
                    showStatus("Failed to update channels: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }
    
    private func toggleChannel(_ id: String) {
        if selectedChannels.contains(id) {
            selectedChannels.remove(id)
        } else {
            selectedChannels.insert(id)
        }
        Storage.selectedChannelIds = selectedChannels
        scheduleLinkPreviewUpdate(for: postText)
    }
    
    // MARK: - Attachment Manager & Drag/Drop
    
    private func selectLocalMedia(isVideo: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = !isVideo && (4 - attachments.count) > 1
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if isVideo {
            panel.allowedContentTypes = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        } else {
            panel.allowedContentTypes = [.image, .jpeg, .png, .gif, .webP]
        }
        
        let appDelegate = NSApp.delegate as? AppDelegate
        appDelegate?.isShowingOpenPanel = true
        
        // Activate the application so the file selection dialog is displayed on top immediately
        NSApp.activate(ignoringOtherApps: true)
        
        panel.begin { response in
            appDelegate?.isShowingOpenPanel = false
            
            if response == .OK {
                for url in panel.urls {
                    addMediaAttachment(url: url, isVideo: isVideo)
                }
            }
        }
    }
    
    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    guard let data = item as? Data,
                          let fileURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    
                    let ext = fileURL.pathExtension.lowercased()
                    let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv"]
                    let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
                    
                    DispatchQueue.main.async {
                        if videoExtensions.contains(ext) {
                            if canAddVideo {
                                addMediaAttachment(url: fileURL, isVideo: true)
                            } else {
                                showStatus("Cannot add video: media list is not empty", isError: true)
                            }
                        } else if imageExtensions.contains(ext) {
                            if canAddImages {
                                addMediaAttachment(url: fileURL, isVideo: false)
                            } else {
                                showStatus("Cannot add image: reached image limit (4) or video is attached", isError: true)
                            }
                        } else {
                            showStatus("Unsupported file type: .\(ext)", isError: true)
                        }
                    }
                }
            }
        }
        return true
    }
    
    private func addMediaAttachment(url: URL, isVideo: Bool) {
        let attachment = Attachment(localURL: url, uploadedURL: nil, progress: 0.0, isVideo: isVideo)
        attachments.append(attachment)
        scheduleLinkPreviewUpdate(for: postText)
        
        let itemId = attachment.id
        
        // Start uploading to Catbox in the background
        Task {
            do {
                let uploadedURL = try await CatboxUploader.shared.uploadFile(at: url) { progress in
                    DispatchQueue.main.async {
                        if let idx = attachments.firstIndex(where: { $0.id == itemId }) {
                            attachments[idx].progress = progress
                        }
                    }
                }
                
                await MainActor.run {
                    if let idx = attachments.firstIndex(where: { $0.id == itemId }) {
                        attachments[idx].uploadedURL = uploadedURL
                        showStatus("Media uploaded successfully!", isError: false)
                    }
                }
            } catch {
                await MainActor.run {
                    if let idx = attachments.firstIndex(where: { $0.id == itemId }) {
                        attachments[idx].error = error.localizedDescription
                        showStatus("Upload failed: \(error.localizedDescription)", isError: true)
                    }
                }
            }
        }
    }
    
    private func removeAttachment(_ id: UUID) {
        attachments.removeAll(where: { $0.id == id })
        scheduleLinkPreviewUpdate(for: postText)
    }
    
    // MARK: - Post Execution
    
    private func postToQueue() {
        guard let token = KeychainHelper.getToken(), canSubmit, !isPosting, !publisher.isPosting else { return }
        
        isPosting = true
        postingStatus = "Preparing post..."
        statusIsError = false
        
        // Build mediaItems matching [["url": "...", "altText": "..."]]
        var mediaItems: [[String: String]] = []
        for item in attachments {
            guard let url = item.uploadedURL else { continue }
            mediaItems.append([
                "url": url,
                "altText": item.altText
            ])
        }
        
        let linkAsset = mediaItems.isEmpty ? blueskyLinkAsset() : nil
        
        let isVideo = attachments.first?.isVideo ?? false
        
        // Map cached channels to standard channels structure
        let apiChannels = channels.map { chan in
            BufferAPI.ChannelsResponse.Channel(id: chan.id, name: chan.name, service: chan.service)
        }
        
        let textsToPublish = isThreaded ? threadSegments : [postText]
        
        // Dispatch to background publisher!
        let didStartPublishing = BackgroundPublisher.shared.publish(
            texts: textsToPublish,
            mediaItems: mediaItems,
            linkAsset: linkAsset,
            isVideo: isVideo,
            selectedChannels: Array(selectedChannels),
            channels: apiChannels,
            postMode: postMode,
            token: token
        )
        
        if !didStartPublishing {
            isPosting = false
            postingStatus = nil
        }
        
        // Keep popover open so background publish state/errors remain visible and reliable.
        // Users can close it manually when they are done.
    }
    
    private func blueskyLinkAsset() -> [String: String]? {
        guard isBlueskySelected,
              let url = (linkPreview?.canonicalURL ?? detectedLinkURL)?.absoluteString,
              !url.isEmpty else {
            return nil
        }
        
        var asset = ["url": url]
        if let title = linkPreview?.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            asset["title"] = title
        }
        if let description = linkPreview?.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            asset["description"] = description
        }
        if let thumbnailUrl = linkPreview?.imageURL?.absoluteString, !thumbnailUrl.isEmpty {
            asset["thumbnailUrl"] = thumbnailUrl
        }
        return asset
    }
    

    
    // MARK: - Clipboard and Auto-Paste Utilities
    
    private func scheduleLinkPreviewUpdate(for text: String) {
        let detectedURL = firstDetectedURL(in: text)
        detectedLinkURL = detectedURL
        
        guard let detectedURL, shouldFetchLinkPreview else {
            isFetchingLinkPreview = false
            linkPreviewTask?.cancel()
            withAnimation(layoutAnimation) {
                linkPreview = nil
            }
            return
        }
        
        if linkPreview?.canonicalURL == detectedURL {
            return
        }
        
        linkPreviewTask?.cancel()
        isFetchingLinkPreview = true
        let currentURL = detectedURL
        
        linkPreviewTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let preview = await LinkMetadataService.shared.fetchPreview(for: currentURL)
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                isFetchingLinkPreview = false
                guard detectedLinkURL == currentURL else { return }
                withAnimation(layoutAnimation) {
                    linkPreview = preview
                }
            }
        }
    }
    
    private func firstDetectedURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .first
    }
    
    private var clipboardMessage: String {
        if let file = clipboardFileUrl {
            return "File in clipboard: \(file.lastPathComponent)"
        } else if clipboardImage != nil {
            return "Image in clipboard"
        } else if let url = clipboardWebUrl {
            return "Web Image URL: \(url.components(separatedBy: "/").last ?? "image")"
        }
        return "Clipboard media detected"
    }
    
    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        
        // 1. Check if there is a file URL in clipboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let url = urls.first {
            let ext = url.pathExtension.lowercased()
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
            let videoExtensions = ["mp4", "mov", "m4v"]
            
            if imageExtensions.contains(ext) || videoExtensions.contains(ext) {
                debugLog("📋 Clipboard scan: media file URL detected")
                self.clipboardFileUrl = url
                self.clipboardImage = nil
                self.clipboardWebUrl = nil
                return
            }
        }
        
        // 2. Check if there is a raw NSImage object in clipboard
        if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            debugLog("📋 Clipboard scan: raw image object detected")
            self.clipboardImage = image
            self.clipboardFileUrl = nil
            self.clipboardWebUrl = nil
            return
        }
        
        // 3. Check if there is a web URL string in clipboard
        if let string = pasteboard.string(forType: .string), let url = URL(string: string) {
            let ext = url.pathExtension.lowercased()
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp"]
            if imageExtensions.contains(ext) {
                debugLog("📋 Clipboard scan: web image URL detected")
                self.clipboardWebUrl = string
                self.clipboardImage = nil
                self.clipboardFileUrl = nil
                return
            }
        }
        
        // Clear all if none match
        self.clipboardImage = nil
        self.clipboardFileUrl = nil
        self.clipboardWebUrl = nil
    }
    
    private func attachFromClipboard() {
        if let file = clipboardFileUrl {
            let ext = file.pathExtension.lowercased()
            let videoExtensions = ["mp4", "mov", "m4v"]
            debugLog("📎 Attaching file URL from clipboard")
            addMediaAttachment(url: file, isVideo: videoExtensions.contains(ext))
        } else if let image = clipboardImage {
            debugLog("📎 Attaching raw image from clipboard")
            if let url = saveClipboardImage(image) {
                addMediaAttachment(url: url, isVideo: false)
            } else {
                showStatus("Failed to process clipboard image", isError: true)
            }
        } else if let webUrl = clipboardWebUrl {
            debugLog("📎 Attaching web image URL directly from clipboard")
            // Attach a direct web URL as a mock local URL but pre-uploaded
            let dummyURL = URL(string: webUrl) ?? URL(fileURLWithPath: "")
            let attachment = Attachment(
                localURL: dummyURL,
                uploadedURL: webUrl,
                progress: 1.0,
                isVideo: false,
                error: nil,
                altText: ""
            )
            attachments.append(attachment)
            showStatus("Web image attached!", isError: false)
        }
        
        // Reset clipboard suggestion after attaching
        self.clipboardImage = nil
        self.clipboardFileUrl = nil
        self.clipboardWebUrl = nil
    }
    
    private func saveClipboardImage(_ image: NSImage) -> URL? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("clipboard_\(UUID().uuidString).png")
        do {
            try pngData.write(to: fileURL)
            return fileURL
        } catch {
            debugLog("❌ Failed to write clipboard image data: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Simplified Helper Methods
    
    private var buttonLabelText: String {
        if postMode == "shareNow" {
            return isThreaded ? "Post Thread Now" : "Post Now to Buffer"
        } else {
            return isThreaded ? "Schedule Thread to Buffer" : "Add to Buffer Schedule"
        }
    }
    
    // MARK: - Auto-Threading Logic
    
    private var threadSegments: [String] {
        ComposerView.splitTextIntoThread(text: postText, limit: characterLimit)
    }
    
    private var isThreaded: Bool {
        postText.count > characterLimit
    }
    
    static func splitTextIntoThread(text: String, limit: Int) -> [String] {
        guard text.count > limit else { return [text] }
        
        var segments: [String] = []
        var remainingText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        while !remainingText.isEmpty {
            if remainingText.count <= limit {
                segments.append(remainingText)
                break
            }
            
            // We need to split. Let's find the best split point within the limit.
            // Look for newlines first, then sentence endings, then spaces.
            let searchString = String(remainingText.prefix(limit))
            var splitIndex = searchString.endIndex
            
            if let lastNewline = searchString.lastIndex(of: "\n") {
                splitIndex = lastNewline
            } else if let lastPeriod = searchString.lastIndex(where: { [".", "!", "?"].contains($0) }) {
                splitIndex = searchString.index(after: lastPeriod)
            } else if let lastSpace = searchString.lastIndex(of: " ") {
                splitIndex = lastSpace
            }
            
            // If we couldn't find a good split point, just split exactly at the limit
            if splitIndex == searchString.startIndex {
                let limitIndex = remainingText.index(remainingText.startIndex, offsetBy: limit)
                splitIndex = limitIndex
            }
            
            let segment = remainingText[..<splitIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty {
                segments.append(segment)
            }
            remainingText = remainingText[splitIndex...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return segments
    }
    
    // MARK: - Emoji Picker Autocomplete Logic
    
    struct EmojiItem {
        let shortcode: String
        let emoji: String
    }
    
    private let emojiDictionary: [String: String] = [
        "smile": "😄", "laughing": "😆", "wink": "😉", "heart_eyes": "😍",
        "joy": "😂", "sob": "😭", "sweat_smile": "😅", "thinking": "🤔",
        "thumbsup": "👍", "thumbsdown": "👎", "clap": "👏", "pray": "🙏",
        "raised_hands": "🙌", "wave": "👋", "heart": "❤️", "fire": "🔥",
        "star": "⭐", "rocket": "🚀", "laptop": "💻", "phone": "📱",
        "check": "✅", "cross": "❌", "warning": "⚠️", "party": "🎉",
        "eyes": "👀", "bulb": "💡", "dog": "🐶", "cat": "🐱",
        "unicorn": "🦄", "coffee": "☕", "beer": "🍺", "pizza": "🍕",
        "tada": "🎉", "100": "💯", "cool": "😎", "mindblown": "🤯",
        "scream": "😱", "sparkles": "✨", "flex": "💪", "money": "💵"
    ]
    
    private var mostUsedEmojis: [String] {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: "most_used_emojis_list"), !saved.isEmpty {
            return saved
        }
        // Default most used emojis
        return ["fire", "thumbsup", "heart", "rocket", "joy", "check", "party", "thinking"]
    }
    
    private func recordEmojiUsage(_ shortcode: String) {
        var currentList = mostUsedEmojis
        if let idx = currentList.firstIndex(of: shortcode) {
            currentList.remove(at: idx)
        }
        currentList.insert(shortcode, at: 0)
        if currentList.count > 12 {
            currentList = Array(currentList.prefix(12))
        }
        UserDefaults.standard.set(currentList, forKey: "most_used_emojis_list")
    }
    
    private func getEmojiMatches(for query: String) -> [EmojiItem] {
        if query.isEmpty {
            return mostUsedEmojis.compactMap { shortcode in
                if let emoji = emojiDictionary[shortcode] {
                    return EmojiItem(shortcode: shortcode, emoji: emoji)
                }
                return nil
            }
        }
        
        let normalized = query.lowercased()
        let filtered = emojiDictionary.filter { $0.key.contains(normalized) }
        
        let sorted = filtered.sorted { a, b in
            let aStarts = a.key.hasPrefix(normalized)
            let bStarts = b.key.hasPrefix(normalized)
            if aStarts && !bStarts { return true }
            if !aStarts && bStarts { return false }
            return a.key < b.key
        }
        
        return sorted.map { EmojiItem(shortcode: $0.key, emoji: $0.value) }
    }
    
    private func updateEmojiSuggestions(for text: String) {
        guard let colonIndex = text.lastIndex(of: ":") else {
            emojiSearchQuery = nil
            return
        }
        
        let afterColon = text[text.index(after: colonIndex)...]
        
        if afterColon.contains(where: { $0.isWhitespace }) {
            emojiSearchQuery = nil
            return
        }
        
        if colonIndex > text.startIndex {
            let beforeColonIndex = text.index(before: colonIndex)
            let beforeColonChar = text[beforeColonIndex]
            if beforeColonChar.isLetter || beforeColonChar.isNumber {
                let substring = String(text[..<colonIndex])
                if substring.hasSuffix("http") || substring.hasSuffix("https") {
                    emojiSearchQuery = nil
                    return
                }
            }
        }
        
        emojiSearchQuery = String(afterColon)
    }
    
    private func selectEmoji(_ shortcode: String, emoji: String) {
        guard let query = emojiSearchQuery else { return }
        let targetToReplace = ":" + query
        if postText.hasSuffix(targetToReplace) {
            postText = String(postText.dropLast(targetToReplace.count)) + emoji
        }
        
        recordEmojiUsage(shortcode)
        emojiSearchQuery = nil
    }
    
    // MARK: - Native Pasteboard Handler
    
    private func handlePasteProviders(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    guard let data = item as? Data,
                          let fileURL = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    
                    let ext = fileURL.pathExtension.lowercased()
                    let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv"]
                    let imageExtensions = ["jpg", "jpeg", "png", "gif", "webp", "heic"]
                    
                    DispatchQueue.main.async {
                        if videoExtensions.contains(ext) {
                            if canAddVideo {
                                addMediaAttachment(url: fileURL, isVideo: true)
                            } else {
                                showStatus("Cannot add video: media list is not empty", isError: true)
                            }
                        } else if imageExtensions.contains(ext) {
                            if canAddImages {
                                addMediaAttachment(url: fileURL, isVideo: false)
                            } else {
                                showStatus("Cannot add image: reached image limit (4)", isError: true)
                            }
                        } else {
                            showStatus("Unsupported file type: .\(ext)", isError: true)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                    guard let image = item as? NSImage else { return }
                    DispatchQueue.main.async {
                        if canAddImages {
                            if let fileURL = saveClipboardImage(image) {
                                addMediaAttachment(url: fileURL, isVideo: false)
                            }
                        } else {
                            showStatus("Cannot add image: reached image limit (4)", isError: true)
                        }
                    }
                }
            }
        }
    }
    
    private func openSettings() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.openSettingsWindow()
        }
    }
    
    private func openAbout() {
        if let delegate = NSApp.delegate as? AppDelegate {
            delegate.openAboutWindow()
        }
    }
    
    private func triggerCheckForUpdates() {
        AppUpdater.shared.checkForUpdatesAndInstall(silentOnNoUpdate: false)
    }
    
    private func debugLog(_ message: String) {
        #if DEBUG
        print("[Composer] \(message)")
        #endif
    }
    
    // MARK: - Toast / Status Display Helper
    
    private func showStatus(_ message: String, isError: Bool) {
        withAnimation(feedbackAnimation) {
            postingStatus = message
            statusIsError = isError
        }
        
        // Auto fade status messages unless active posting is in progress
        if !isPosting && !isUploadingMedia {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                withAnimation(layoutAnimation) {
                    if postingStatus == message {
                        postingStatus = nil
                    }
                }
            }
        }
    }
}

// MARK: - ChannelBadge Subview

struct ChannelBadge: View {
    let service: String
    
    var body: some View {
        if let iconUrl = dashboardIconUrl {
            AsyncImage(url: iconUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .clipShape(Circle())
                case .failure, .empty:
                    fallbackBadge
                @unknown default:
                    fallbackBadge
                }
            }
        } else {
            fallbackBadge
        }
    }
    
    private var fallbackBadge: some View {
        ZStack {
            Circle()
                .fill(service.serviceColor)
                .frame(width: 18, height: 18)
            
            Text(serviceIconText)
                .font(.system(size: 8, weight: .black))
                .foregroundColor(.white)
        }
    }
    
    private var dashboardIconUrl: URL? {
        let normalized = service.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String
        switch normalized {
        case "twitter", "x":
            name = "twitter"
        case "bluesky":
            name = "bluesky"
        case "facebook":
            name = "facebook"
        case "instagram":
            name = "instagram"
        case "linkedin":
            name = "linkedin"
        case "pinterest":
            name = "pinterest"
        case "tiktok":
            name = "tiktok"
        case "youtube":
            name = "youtube"
        case "mastodon":
            name = "mastodon"
        case "threads":
            name = "threads"
        default:
            name = normalized
        }
        return URL(string: "https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/\(name).png")
    }
    
    private var serviceIconText: String {
        switch service.lowercased() {
        case "twitter", "x": return "X"
        case "facebook": return "F"
        case "instagram": return "I"
        case "linkedin": return "L"
        case "pinterest": return "P"
        case "tiktok": return "T"
        case "youtube": return "Y"
        case "bluesky": return "B"
        case "mastodon": return "M"
        case "threads": return "T"
        default: return String(service.prefix(1)).uppercased()
        }
    }
}

extension String {
    var serviceColor: Color {
        switch self.lowercased() {
        case "twitter", "x": return Color.primary
        case "facebook": return Color(red: 0.23, green: 0.35, blue: 0.6)
        case "instagram": return Color(red: 0.88, green: 0.19, blue: 0.42)
        case "linkedin": return Color(red: 0.04, green: 0.4, blue: 0.65)
        case "pinterest": return Color(red: 0.8, green: 0.08, blue: 0.18)
        case "tiktok": return Color.primary
        case "youtube": return Color(red: 0.9, green: 0.08, blue: 0.08)
        case "bluesky": return Color(red: 0.0, green: 0.53, blue: 1.0)
        case "mastodon": return Color(red: 0.35, green: 0.33, blue: 0.81)
        case "threads": return Color.primary
        default: return Color.gray
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScaleButtonBody(configuration: configuration)
    }
    
    private struct ScaleButtonBody: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let configuration: Configuration
        @State private var isHovering = false
        
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? (reduceMotion ? 0.99 : 0.97) : (isHovering && !reduceMotion ? 1.01 : 1.0))
                .opacity(configuration.isPressed ? 0.9 : 1.0)
                .animation(reduceMotion ? .linear(duration: 0.01) : .timingCurve(0.25, 1, 0.5, 1, duration: 0.12), value: configuration.isPressed)
                .animation(reduceMotion ? .linear(duration: 0.01) : .timingCurve(0.25, 1, 0.5, 1, duration: 0.18), value: isHovering)
                .onHover { hovering in
                    isHovering = hovering
                }
        }
    }
}

struct GlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(<6.2)
        content
        #else
        if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive())
        } else {
            content
        }
        #endif
    }
}

struct ProfilePillModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(<6.2)
        content
            .background(Color.primary.opacity(0.08))
            .cornerRadius(20)
        #else
        if #available(macOS 26, *) {
            content
                .glassEffect(.regular.interactive())
        } else {
            content
                .background(Color.primary.opacity(0.08))
                .cornerRadius(20)
        }
        #endif
    }
}
