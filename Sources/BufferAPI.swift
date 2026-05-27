import Foundation

final class BufferAPI {
    static let shared = BufferAPI()
    private let endpoint = URL(string: "https://api.buffer.com")!
    
    enum APIError: LocalizedError {
        case invalidToken
        case networkError(Error)
        case invalidResponse
        case graphQLError(String)
        case custom(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidToken: return "Invalid or expired Buffer API Key. Please verify your token."
            case .networkError(let error): return "Network connection error: \(error.localizedDescription)"
            case .invalidResponse: return "Received an invalid response from the Buffer server."
            case .graphQLError(let message): return "Buffer API Error: \(message)"
            case .custom(let message): return message
            }
        }
    }
    
    // MARK: - Generic GraphQL Requester
    
    private func performGraphQLQuery<R: Decodable>(
        operationName: String,
        query: String,
        variables: [String: Any] = [:],
        token: String
    ) async throws -> R {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        
        debugLog("📡 Sending request | Operation: \(operationName) | Variable keys: \(Array(variables.keys))")
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            debugLog("❌ Failed to serialize JSON payload")
            throw APIError.invalidResponse
        }
        request.httpBody = httpBody
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("❌ Invalid HTTP response received")
            throw APIError.invalidResponse
        }
        
        debugLog("📥 Response received | HTTP Status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode == 401 {
            debugLog("❌ Unauthorised (401) | Token is invalid or expired")
            throw APIError.invalidToken
        }
        
        guard httpResponse.statusCode == 200 else {
            debugLog("❌ Server error status: \(httpResponse.statusCode)")
            throw APIError.custom("Buffer API returned HTTP Status \(httpResponse.statusCode)")
        }
        
        // Parse GraphQL structure
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            debugLog("❌ Failed to parse JSON response body")
            throw APIError.invalidResponse
        }
        
        if let errors = json["errors"] as? [[String: Any]], let firstError = errors.first, let message = firstError["message"] as? String {
            debugLog("❌ GraphQL Error received")
            throw APIError.graphQLError(message)
        }
        
        guard let dataContainer = json["data"] else {
            throw APIError.invalidResponse
        }
        
        let subData = try JSONSerialization.data(withJSONObject: dataContainer, options: [])
        return try JSONDecoder().decode(R.self, from: subData)
    }
    
    // MARK: - Authentication & Validation
    
    struct AccountVerifyResponse: Decodable {
        struct Account: Decodable {
            let id: String
            let email: String
            struct Org: Decodable {
                let id: String
                let name: String
            }
            let organizations: [Org]
        }
        let account: Account
    }
    
    func verifyTokenAndGetOrganizations(token: String) async throws -> AccountVerifyResponse.Account {
        let query = """
        query VerifyToken {
          account {
            id
            email
            organizations {
              id
              name
            }
          }
        }
        """
        
        let response: AccountVerifyResponse = try await performGraphQLQuery(
            operationName: "VerifyToken/account",
            query: query,
            token: token
        )
        return response.account
    }
    
    // MARK: - Channel Fetching
    
    struct ChannelsResponse: Decodable {
        struct Channel: Decodable {
            let id: String
            let name: String
            let service: String
        }
        let channels: [Channel]
    }
    
    func fetchChannels(forOrganizationId orgId: String, token: String) async throws -> [ChannelsResponse.Channel] {
        let query = """
        query FetchChannels {
          channels(input: { organizationId: "\(orgId)" }) {
            id
            name
            service
          }
        }
        """
        
        let response: ChannelsResponse = try await performGraphQLQuery(
            operationName: "FetchChannels/org:\(orgId)",
            query: query,
            variables: [:],
            token: token
        )
        return response.channels
    }
    
    // MARK: - Post Creation
    
    struct CreatePostResponse: Decodable {
        struct CreatePostResult: Decodable {
            // Buffer createPost is a GraphQL union. It returns either PostActionSuccess or MutationError.
            // In our decoded JSON it could match:
            let message: String? // Present in MutationError
            struct Post: Decodable {
                let id: String
            }
            let post: Post? // Present in PostActionSuccess
        }
        let createPost: CreatePostResult
    }
    
    func createPost(
        channelId: String,
        text: String,
        mediaItems: [[String: String]], // List of items, each containing ["url": "...", "altText": "..."]
        linkAsset: [String: String]? = nil,
        isVideo: Bool,
        mode: String = "shareNow", // Default to immediate sharing
        token: String
    ) async throws {
        let query = """
        mutation CreateAppPost($input: CreatePostInput!) {
          createPost(input: $input) {
            ... on PostActionSuccess {
              post {
                id
              }
            }
            ... on MutationError {
              message
            }
          }
        }
        """
        
        // Build assets payload according to standard schema
        var assetsPayload: [[String: Any]] = []
        if !mediaItems.isEmpty {
            if isVideo, let firstVideo = mediaItems.first, let url = firstVideo["url"] {
                assetsPayload.append([
                    "video": [
                        "url": url
                    ]
                ])
            } else {
                for item in mediaItems {
                    guard let url = item["url"] else { continue }
                    var imageDict: [String: Any] = ["url": url]
                    
                    if let altText = item["altText"], !altText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        imageDict["metadata"] = [
                            "altText": altText
                        ]
                    }
                    
                    assetsPayload.append([
                        "image": imageDict
                    ])
                }
            }
        }
        
        if let linkAsset, let url = linkAsset["url"], !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var linkDict: [String: Any] = ["url": url]
            if let title = linkAsset["title"], !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                linkDict["title"] = title
            }
            if let description = linkAsset["description"], !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                linkDict["description"] = description
            }
            if let thumbnailUrl = linkAsset["thumbnailUrl"], !thumbnailUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                linkDict["thumbnailUrl"] = thumbnailUrl
            }
            
            assetsPayload.append([
                "link": linkDict
            ])
        }
        
        var inputVariables: [String: Any] = [
            "channelId": channelId,
            "text": text,
            "schedulingType": "automatic",
            "mode": mode
        ]
        
        if !assetsPayload.isEmpty {
            inputVariables["assets"] = assetsPayload
        }
        
        let response: CreatePostResponse = try await performGraphQLQuery(
            operationName: "CreatePost/channel:\(channelId)/mode:\(mode)",
            query: query,
            variables: ["input": inputVariables],
            token: token
        )
        
        if let errorMessage = response.createPost.message {
            throw APIError.custom(errorMessage)
        }
        
        guard response.createPost.post != nil else {
            throw APIError.custom("Failed to create post.")
        }
    }
    
    private func debugLog(_ message: String) {
        #if DEBUG
        print("[BufferAPI] \(message)")
        #endif
    }
}
