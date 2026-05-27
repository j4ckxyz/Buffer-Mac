import Foundation
import AppKit
import UserNotifications

final class BackgroundPublisher: ObservableObject {
    static let shared = BackgroundPublisher()
    
    @Published var isPosting = false
    @Published var postingStatus = ""
    @Published var lastStatusMessage = ""
    @Published var statusIsError = false
    @Published var triggerClearComposer = false
    
    init() {}
    
    @discardableResult
    func publish(
        texts: [String],
        mediaItems: [[String: String]],
        linkAsset: [String: String]?,
        isVideo: Bool,
        selectedChannels: [String],
        channels: [BufferAPI.ChannelsResponse.Channel],
        postMode: String,
        token: String
    ) -> Bool {
        guard !isPosting else {
            debugLog("Ignored duplicate publish request while a publish is already in progress.")
            return false
        }
        
        isPosting = true
        
        let finalPostMode = (postMode == "forceShareNow") ? "shareNow" : postMode
        let expectedCreatePostRequests = texts.count * selectedChannels.count
        debugLog("Starting publish | Buffer createPost requests: \(expectedCreatePostRequests) | Segments: \(texts.count) | Profiles: \(selectedChannels.count) | Media items: \(mediaItems.count) | Link asset: \(linkAsset == nil ? "none" : "available")")
        
        let actionWord = finalPostMode == "shareNow" ? "Posting" : "Queueing"
        let threadSuffix = texts.count > 1 ? " (Thread)" : ""
        postingStatus = "\(actionWord) to \(selectedChannels.count) profile\(selectedChannels.count > 1 ? "s" : "")\(threadSuffix)..."
        statusIsError = false
        triggerClearComposer = false
        
        // Detached background task that persists regardless of Popover dismissal
        Task {
            var completedCount = 0
            var successfulChannels: [String] = []
            var errors: [String] = []
            
            for (index, textSegment) in texts.enumerated() {
                let segmentSuffix = texts.count > 1 ? " (\(index + 1)/\(texts.count))" : ""
                
                await MainActor.run {
                    self.postingStatus = "\(actionWord) to \(selectedChannels.count) profile\(selectedChannels.count > 1 ? "s" : "")\(segmentSuffix)..."
                }
                
                for channelId in selectedChannels {
                    do {
                        // For the first segment in a thread, attach the media items!
                        // For subsequent segments, do not attach the same media.
                        let segmentMedia = index == 0 ? mediaItems : []
                        let segmentIsVideo = index == 0 ? isVideo : false
                        let channel = channels.first(where: { $0.id == channelId })
                        let segmentLinkAsset = index == 0 && segmentMedia.isEmpty && channel?.service.lowercased() == "bluesky" ? linkAsset : nil
                        
                        try await BufferAPI.shared.createPost(
                            channelId: channelId,
                            text: textSegment,
                            mediaItems: segmentMedia,
                            linkAsset: segmentLinkAsset,
                            isVideo: segmentIsVideo,
                            mode: finalPostMode,
                            token: token
                        )
                        
                        if index == 0 {
                            completedCount += 1
                            if let channel {
                                successfulChannels.append(channel.name)
                            }
                        }
                    } catch {
                        errors.append(error.localizedDescription)
                    }
                }
            }
            
            let finalCompleted = completedCount
            let finalSuccessList = successfulChannels
            let finalErrors = errors
            
            await MainActor.run {
                self.isPosting = false
                
                if finalErrors.isEmpty {
                    // Play subtle native success haptics!
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                    
                    let actionVerb = finalPostMode == "shareNow" ? "Posted" : "Queued"
                    let channelNamesStr = finalSuccessList.isEmpty ? "\(finalCompleted) profile(s)" : finalSuccessList.joined(separator: " + ")
                    let msg = "\(actionVerb) to \(channelNamesStr)"
                    
                    // SAVE TIMESTAMP HERE ON SUCCESS!
                    let now = Date().timeIntervalSince1970
                    UserDefaults.standard.set(now, forKey: "last_post_timestamp")
                    
                    var history = UserDefaults.standard.array(forKey: "post_timestamps_history") as? [Double] ?? []
                    history.append(now)
                    if history.count > 5 {
                        history.removeFirst()
                    }
                    UserDefaults.standard.set(history, forKey: "post_timestamps_history")
                    
                    self.lastStatusMessage = msg
                    self.statusIsError = false
                    self.triggerClearComposer = true
                    
                    self.showSystemNotification(title: "Post Successful", message: msg)
                } else {
                    let failVerb = finalPostMode == "shareNow" ? "post" : "queue"
                    let msg: String
                    if finalCompleted > 0 {
                        let successStr = finalSuccessList.joined(separator: " + ")
                        msg = "Sent to \(successStr). Failed some: \(finalErrors.joined(separator: ", "))"
                    } else {
                        msg = "Failed to \(failVerb): \(finalErrors.first ?? "Unknown API error")"
                    }
                    
                    self.lastStatusMessage = msg
                    self.statusIsError = true
                    
                    self.showSystemNotification(title: "Post Failed", message: msg)
                }
            }
        }
        
        return true
    }
    
    private func showSystemNotification(title: String, message: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            content.sound = .default
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
    
    private func debugLog(_ message: String) {
        #if DEBUG
        print("[BackgroundPublisher] \(message)")
        #endif
    }
}
