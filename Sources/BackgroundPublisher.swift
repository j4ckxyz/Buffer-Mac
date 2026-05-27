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
    
    func publish(
        texts: [String],
        mediaItems: [[String: String]],
        isVideo: Bool,
        selectedChannels: [String],
        channels: [BufferAPI.ChannelsResponse.Channel],
        postMode: String,
        token: String
    ) {
        isPosting = true
        
        // Handle Intelligent Anti-Spam protection:
        let isIntelligentAntiSpamEnabled = UserDefaults.standard.object(forKey: "intelligent_antispam") == nil 
            ? true 
            : UserDefaults.standard.bool(forKey: "intelligent_antispam")
        
        let lastPost = UserDefaults.standard.double(forKey: "last_post_timestamp")
        let isRecentlyPosted = lastPost > 0 && (Date().timeIntervalSince1970 - lastPost) < 1800
        
        let finalPostMode: String
        if isIntelligentAntiSpamEnabled && isRecentlyPosted && postMode == "shareNow" {
            finalPostMode = "addToQueue"
        } else {
            finalPostMode = postMode
        }
        
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
                        
                        try await BufferAPI.shared.createPost(
                            channelId: channelId,
                            text: textSegment,
                            mediaItems: segmentMedia,
                            isVideo: segmentIsVideo,
                            mode: finalPostMode,
                            token: token
                        )
                        
                        if index == 0 {
                            completedCount += 1
                            if let channel = channels.first(where: { $0.id == channelId }) {
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
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "last_post_timestamp")
                    
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
}
