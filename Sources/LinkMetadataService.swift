import Foundation

struct LinkPreviewMetadata: Equatable {
    let canonicalURL: URL
    let title: String
    let description: String?
    let imageURL: URL?
    let imageSource: String?
    let siteName: String?
}

actor LinkMetadataService {
    static let shared = LinkMetadataService()
    
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": "BufferMenubar/1.0 (+https://github.com/jack/buffer-menubar)"
        ]
        return URLSession(configuration: config)
    }()
    
    func fetchPreview(for rawURL: URL) async -> LinkPreviewMetadata? {
        do {
            let (data, response) = try await session.data(from: rawURL)
            guard let http = response as? HTTPURLResponse,
                  (200...399).contains(http.statusCode),
                  let html = String(data: data, encoding: .utf8) else {
                return nil
            }
            
            let finalURL = http.url ?? rawURL
            return parseMetadata(from: html, baseURL: finalURL)
        } catch {
            return nil
        }
    }
    
    private func parseMetadata(from html: String, baseURL: URL) -> LinkPreviewMetadata {
        let title = firstNonEmpty([
            metaContent(in: html, property: "og:title"),
            metaContent(in: html, name: "twitter:title"),
            titleTag(in: html)
        ]) ?? baseURL.host ?? baseURL.absoluteString
        
        let description = firstNonEmpty([
            metaContent(in: html, property: "og:description"),
            metaContent(in: html, name: "twitter:description"),
            metaContent(in: html, name: "description")
        ])
        
        let siteName = firstNonEmpty([
            metaContent(in: html, property: "og:site_name"),
            baseURL.host
        ])
        
        // Requested priority: regular OG -> Twitter -> Facebook-ish/legacy fallbacks.
        let imageCandidates: [(String, String?)] = [
            ("og:image", metaContent(in: html, property: "og:image")),
            ("twitter:image", metaContent(in: html, name: "twitter:image")),
            ("og:image:secure_url", metaContent(in: html, property: "og:image:secure_url")),
            ("og:image:url", metaContent(in: html, property: "og:image:url")),
            ("image_src", linkHref(in: html, rel: "image_src")),
            ("itemprop:image", metaContent(in: html, itemprop: "image"))
        ]
        
        var selectedImageURL: URL?
        var selectedImageSource: String?
        
        for (source, rawValue) in imageCandidates {
            guard let rawValue, !rawValue.isEmpty,
                  let resolved = URL(string: rawValue, relativeTo: baseURL)?.absoluteURL else { continue }
            selectedImageURL = resolved
            selectedImageSource = source
            break
        }
        
        return LinkPreviewMetadata(
            canonicalURL: baseURL,
            title: title,
            description: description,
            imageURL: selectedImageURL,
            imageSource: selectedImageSource,
            siteName: siteName
        )
    }
    
    private func firstNonEmpty(_ values: [String?]) -> String? {
        for value in values {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { continue }
            return trimmed
        }
        return nil
    }
    
    private func metaContent(in html: String, property: String) -> String? {
        // Supports both: <meta property="..." content="..."> and reversed order.
        let patternA = #"<meta[^>]*property=["']__PROPERTY__["'][^>]*content=["']([^"']+)["'][^>]*>"#
        let patternB = #"<meta[^>]*content=["']([^"']+)["'][^>]*property=["']__PROPERTY__["'][^>]*>"#
        return firstMatch(in: html, regex: patternA.replacingOccurrences(of: "__PROPERTY__", with: NSRegularExpression.escapedPattern(for: property)))
            ?? firstMatch(in: html, regex: patternB.replacingOccurrences(of: "__PROPERTY__", with: NSRegularExpression.escapedPattern(for: property)))
    }
    
    private func metaContent(in html: String, name: String) -> String? {
        let patternA = #"<meta[^>]*name=["']__NAME__["'][^>]*content=["']([^"']+)["'][^>]*>"#
        let patternB = #"<meta[^>]*content=["']([^"']+)["'][^>]*name=["']__NAME__["'][^>]*>"#
        return firstMatch(in: html, regex: patternA.replacingOccurrences(of: "__NAME__", with: NSRegularExpression.escapedPattern(for: name)))
            ?? firstMatch(in: html, regex: patternB.replacingOccurrences(of: "__NAME__", with: NSRegularExpression.escapedPattern(for: name)))
    }
    
    private func metaContent(in html: String, itemprop: String) -> String? {
        let patternA = #"<meta[^>]*itemprop=["']__ITEMPROP__["'][^>]*content=["']([^"']+)["'][^>]*>"#
        let patternB = #"<meta[^>]*content=["']([^"']+)["'][^>]*itemprop=["']__ITEMPROP__["'][^>]*>"#
        return firstMatch(in: html, regex: patternA.replacingOccurrences(of: "__ITEMPROP__", with: NSRegularExpression.escapedPattern(for: itemprop)))
            ?? firstMatch(in: html, regex: patternB.replacingOccurrences(of: "__ITEMPROP__", with: NSRegularExpression.escapedPattern(for: itemprop)))
    }
    
    private func linkHref(in html: String, rel: String) -> String? {
        let patternA = #"<link[^>]*rel=["']__REL__["'][^>]*href=["']([^"']+)["'][^>]*>"#
        let patternB = #"<link[^>]*href=["']([^"']+)["'][^>]*rel=["']__REL__["'][^>]*>"#
        return firstMatch(in: html, regex: patternA.replacingOccurrences(of: "__REL__", with: NSRegularExpression.escapedPattern(for: rel)))
            ?? firstMatch(in: html, regex: patternB.replacingOccurrences(of: "__REL__", with: NSRegularExpression.escapedPattern(for: rel)))
    }
    
    private func titleTag(in html: String) -> String? {
        firstMatch(in: html, regex: #"<title[^>]*>([^<]+)</title>"#)
    }
    
    private func firstMatch(in html: String, regex pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[valueRange])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
