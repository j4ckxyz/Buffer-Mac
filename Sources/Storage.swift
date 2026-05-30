import Foundation

struct Storage {
    private static let selectedChannelsKey = "selected_channel_ids"
    private static let draftTextKey = "composer_draft_text"
    private static let cachedChannelsKey = "cached_channels_data"
    
    static var selectedChannelIds: Set<String> {
        get {
            let list = UserDefaults.standard.stringArray(forKey: selectedChannelsKey) ?? []
            return Set(list)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: selectedChannelsKey)
        }
    }
    
    static var draftText: String {
        get {
            return UserDefaults.standard.string(forKey: draftTextKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: draftTextKey)
        }
    }
    
    static var draftThreadTexts: [String] {
        get {
            return UserDefaults.standard.stringArray(forKey: "composer_draft_thread_texts") ?? [draftText]
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "composer_draft_thread_texts")
            if let first = newValue.first {
                draftText = first
            }
        }
    }
    
    struct CachedChannel: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        let service: String
    }
    
    static var cachedChannels: [CachedChannel] {
        get {
            guard let data = UserDefaults.standard.data(forKey: cachedChannelsKey),
                  let channels = try? JSONDecoder().decode([CachedChannel].self, from: data) else {
                return []
            }
            return channels
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: cachedChannelsKey)
            }
        }
    }
    
    private static let userEmailKey = "authenticated_user_email"
    
    static var userEmail: String {
        get {
            return UserDefaults.standard.string(forKey: userEmailKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: userEmailKey)
        }
    }
    
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: selectedChannelsKey)
        UserDefaults.standard.removeObject(forKey: draftTextKey)
        UserDefaults.standard.removeObject(forKey: cachedChannelsKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
    }
}
