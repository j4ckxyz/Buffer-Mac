import Foundation
import AppKit
import AVFoundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

final class CatboxUploader: NSObject, URLSessionTaskDelegate {
    static let shared = CatboxUploader()
    
    private let maxVideoUploadBytes: Int64 = 100 * 1024 * 1024 // 100 MB
    private var progressHandlers: [Int: (Double) -> Void] = [:]
    
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()
    
    enum UploadError: LocalizedError {
        case fileReadError
        case invalidResponse
        case serverError(String)
        case videoTooLargeAfterCompression(finalSizeMB: Int)
        case videoCompressionFailed
        case multipartCreationFailed
        
        var errorDescription: String? {
            switch self {
            case .fileReadError:
                return "Could not read the selected local file."
            case .invalidResponse:
                return "The media hosting service returned an invalid response."
            case .serverError(let msg):
                return "Media upload failed: \(msg)"
            case .videoTooLargeAfterCompression(let finalSizeMB):
                return "Video is still \(finalSizeMB) MB after local compression. Please trim or re-encode to under 100 MB."
            case .videoCompressionFailed:
                return "Unable to compress this video locally. Please try a different video format."
            case .multipartCreationFailed:
                return "Could not prepare media upload payload."
            }
        }
    }
    
    /// Uploads a local file URL to Catbox.moe anonymously, reporting progress in real-time.
    /// For videos, performs local compression when needed and enforces a 100 MB max size.
    func uploadFile(at fileURL: URL, progressHandler: @escaping (Double) -> Void) async throws -> String {
        guard fileURL.startAccessingSecurityScopedResource() else {
            // If secure-scoped bookmarks are not enabled or not needed, we can try reading directly anyway
            return try await performUpload(fileURL: fileURL, progressHandler: progressHandler)
        }
        defer { fileURL.stopAccessingSecurityScopedResource() }
        return try await performUpload(fileURL: fileURL, progressHandler: progressHandler)
    }
    
    private func performUpload(fileURL: URL, progressHandler: @escaping (Double) -> Void) async throws -> String {
        let prepared = try await prepareFileForUpload(at: fileURL)
        
        let sourceSize = try fileSizeBytes(for: prepared.url)
        var dimensionString = "Unknown Dimensions"
        
        if let image = NSImage(contentsOf: prepared.url) {
            let width = image.size.width
            let height = image.size.height
            if height > 0 {
                let ratio = width / height
                dimensionString = "\(Int(width))x\(Int(height)) (Aspect Ratio: \(String(format: "%.2f", ratio)))"
            } else {
                dimensionString = "\(Int(width))x\(Int(height))"
            }
        }
        
        debugLog("📤 Starting media upload | Ext: \(prepared.url.pathExtension.lowercased()) | Size: \(sourceSize) bytes | Dimensions: \(dimensionString)")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        let mimeType = mimeType(for: prepared.url)
        let multipartBodyURL = try createMultipartBodyFile(boundary: boundary, fileURL: prepared.url, mimeType: mimeType)
        
        var cleanupURLs = prepared.cleanupURLs
        cleanupURLs.append(multipartBodyURL)
        
        var request = URLRequest(url: URL(string: "https://catbox.moe/user/api.php")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let payloadSize = try? fileSizeBytes(for: multipartBodyURL) {
            request.setValue(String(payloadSize), forHTTPHeaderField: "Content-Length")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.uploadTask(with: request, fromFile: multipartBodyURL) { responseData, response, error in
                self.cleanupLocalFiles(cleanupURLs)
                
                if let error = error {
                    self.debugLog("❌ Upload failed: \(error.localizedDescription)")
                    continuation.resume(throwing: UploadError.serverError(error.localizedDescription))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                      let responseData = responseData,
                      let rawUrlString = String(data: responseData, encoding: .utf8) else {
                    self.debugLog("❌ Invalid server response")
                    continuation.resume(throwing: UploadError.invalidResponse)
                    return
                }
                
                let cleanedUrl = rawUrlString.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanedUrl.contains("https://") || cleanedUrl.contains("http://") {
                    self.debugLog("✅ Upload completed")
                    continuation.resume(returning: cleanedUrl)
                } else {
                    self.debugLog("❌ Media host returned an error")
                    continuation.resume(throwing: UploadError.serverError(cleanedUrl))
                }
            }
            
            self.progressHandlers[task.taskIdentifier] = progressHandler
            self.debugLog("📡 Sending request | Operation: CatboxUpload/task:\(task.taskIdentifier)")
            task.resume()
        }
    }
    
    private struct PreparedUpload {
        let url: URL
        let cleanupURLs: [URL]
    }
    
    private func prepareFileForUpload(at fileURL: URL) async throws -> PreparedUpload {
        guard isVideo(fileURL) else {
            let originalSize = try fileSizeBytes(for: fileURL)
            let maxImageBytes: Int64 = 2 * 1024 * 1024 // 2 MB
            if originalSize <= maxImageBytes {
                return PreparedUpload(url: fileURL, cleanupURLs: [])
            }
            
            do {
                let compressedURL = try compressImageToFitLimit(inputURL: fileURL, maxBytes: maxImageBytes)
                let finalSize = try fileSizeBytes(for: compressedURL)
                if finalSize <= maxImageBytes {
                    debugLog("✅ Image compression successful: \(finalSize / 1024) KB")
                    return PreparedUpload(url: compressedURL, cleanupURLs: [compressedURL])
                }
                return PreparedUpload(url: fileURL, cleanupURLs: [])
            } catch {
                debugLog("⚠️ Image compression failed, uploading original: \(error.localizedDescription)")
                return PreparedUpload(url: fileURL, cleanupURLs: [])
            }
        }
        
        let originalSize = try fileSizeBytes(for: fileURL)
        let originalSizeMB = Int(ceil(Double(originalSize) / 1_048_576.0))
        
        if originalSize <= maxVideoUploadBytes {
            return PreparedUpload(url: fileURL, cleanupURLs: [])
        }
        
        debugLog("🎬 Video is \(originalSizeMB) MB. Trying local compression to fit 100 MB limit...")
        let compressedURL = try await compressVideoToFitLimit(inputURL: fileURL, maxBytes: maxVideoUploadBytes)
        let compressedSize = try fileSizeBytes(for: compressedURL)
        let compressedSizeMB = Int(ceil(Double(compressedSize) / 1_048_576.0))
        
        if compressedSize > maxVideoUploadBytes {
            try? FileManager.default.removeItem(at: compressedURL)
            throw UploadError.videoTooLargeAfterCompression(finalSizeMB: compressedSizeMB)
        }
        
        debugLog("✅ Local video compression complete (\(compressedSizeMB) MB).")
        return PreparedUpload(url: compressedURL, cleanupURLs: [compressedURL])
    }
    
    private func compressImageToFitLimit(inputURL: URL, maxBytes: Int64) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let _ = CGImageSourceGetType(imageSource) else {
            return inputURL
        }
        
        let originalSize = try fileSizeBytes(for: inputURL)
        if originalSize <= maxBytes {
            return inputURL
        }
        
        debugLog("🖼️ Image size is \(originalSize / 1024) KB. Compressing to fit under \(maxBytes / 1024) KB...")
        
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return inputURL
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // 1. Try step-down quality compression first
        var quality: CGFloat = 0.85
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("compressed_image_\(UUID().uuidString)")
            .appendingPathExtension("jpg")
        
        while quality >= 0.4 {
            if let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                let options: [CFString: Any] = [
                    kCGImageDestinationLossyCompressionQuality: quality
                ]
                CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
                if CGImageDestinationFinalize(destination) {
                    let size = try fileSizeBytes(for: outputURL)
                    debugLog("📸 Quality \(quality) produced \(size / 1024) KB")
                    if size <= maxBytes {
                        return outputURL
                    }
                }
            }
            quality -= 0.15
        }
        
        // 2. If quality compression wasn't enough, downscale the image and compress
        var scale: CGFloat = 0.75
        while scale >= 0.25 {
            let targetWidth = Int(CGFloat(width) * scale)
            let targetHeight = Int(CGFloat(height) * scale)
            
            guard let context = CGContext(
                data: nil,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: cgImage.bitsPerComponent,
                bytesPerRow: 0,
                space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: cgImage.bitmapInfo.rawValue
            ) else {
                break
            }
            
            context.interpolationQuality = .high
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            
            if let downscaledImage = context.makeImage() {
                if let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
                    let options: [CFString: Any] = [
                        kCGImageDestinationLossyCompressionQuality: CGFloat(0.7)
                    ]
                    CGImageDestinationAddImage(destination, downscaledImage, options as CFDictionary)
                    if CGImageDestinationFinalize(destination) {
                        let size = try fileSizeBytes(for: outputURL)
                        debugLog("📸 Scale \(scale) produced \(size / 1024) KB")
                        if size <= maxBytes {
                            return outputURL
                        }
                    }
                }
            }
            scale -= 0.25
        }
        
        return inputURL
    }
    
    private func compressVideoToFitLimit(inputURL: URL, maxBytes: Int64) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)
        let candidatePresets = [
            AVAssetExportPreset1280x720,
            AVAssetExportPreset960x540,
            AVAssetExportPreset640x480,
            AVAssetExportPresetMediumQuality,
            AVAssetExportPresetLowQuality
        ]
        
        let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
        let presets = candidatePresets.filter { compatible.contains($0) }
        guard !presets.isEmpty else { throw UploadError.videoCompressionFailed }
        
        for preset in presets {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("compressed_\(UUID().uuidString)")
                .appendingPathExtension("mp4")
            
            do {
                try await export(asset: asset, to: outputURL, preset: preset)
                let size = try fileSizeBytes(for: outputURL)
                let sizeMB = Int(ceil(Double(size) / 1_048_576.0))
                debugLog("🎞️ Preset \(preset) produced \(sizeMB) MB")
                if size <= maxBytes {
                    return outputURL
                }
                try? FileManager.default.removeItem(at: outputURL)
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                continue
            }
        }
        
        let originalSize = try fileSizeBytes(for: inputURL)
        let originalSizeMB = Int(ceil(Double(originalSize) / 1_048_576.0))
        throw UploadError.videoTooLargeAfterCompression(finalSizeMB: originalSizeMB)
    }
    
    private func export(asset: AVAsset, to outputURL: URL, preset: String) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw UploadError.videoCompressionFailed
        }
        
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        
        try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: session.error ?? UploadError.videoCompressionFailed)
                default:
                    continuation.resume(throwing: UploadError.videoCompressionFailed)
                }
            }
        }
    }
    
    private func createMultipartBodyFile(boundary: String, fileURL: URL, mimeType: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("catbox_multipart_\(UUID().uuidString)")
            .appendingPathExtension("tmp")
        
        guard FileManager.default.createFile(atPath: tempURL.path, contents: nil) else {
            throw UploadError.multipartCreationFailed
        }
        
        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: tempURL)
        } catch {
            throw UploadError.multipartCreationFailed
        }
        
        func writeString(_ string: String) throws {
            guard let data = string.data(using: .utf8) else { throw UploadError.multipartCreationFailed }
            try handle.write(contentsOf: data)
        }
        
        do {
            try writeString("--\(boundary)\r\n")
            try writeString("Content-Disposition: form-data; name=\"reqtype\"\r\n\r\n")
            try writeString("fileupload\r\n")
            
            try writeString("--\(boundary)\r\n")
            try writeString("Content-Disposition: form-data; name=\"fileToUpload\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
            try writeString("Content-Type: \(mimeType)\r\n\r\n")
            
            try streamFile(into: handle, from: fileURL)
            
            try writeString("\r\n--\(boundary)--\r\n")
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: tempURL)
            throw UploadError.multipartCreationFailed
        }
        
        return tempURL
    }
    
    private func streamFile(into handle: FileHandle, from fileURL: URL) throws {
        guard let input = InputStream(url: fileURL) else {
            throw UploadError.fileReadError
        }
        
        input.open()
        defer { input.close() }
        
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        
        while input.hasBytesAvailable {
            let bytesRead = input.read(buffer, maxLength: bufferSize)
            if bytesRead < 0 {
                throw input.streamError ?? UploadError.fileReadError
            }
            if bytesRead == 0 {
                break
            }
            let chunk = Data(bytes: buffer, count: bytesRead)
            try handle.write(contentsOf: chunk)
        }
    }
    
    private func cleanupLocalFiles(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func isVideo(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(ext)
    }
    
    private func fileSizeBytes(for url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let fileSize = values.fileSize else { throw UploadError.fileReadError }
        return Int64(fileSize)
    }
    
    // MARK: - URLSessionTaskDelegate
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard let progressHandler = progressHandlers[task.taskIdentifier], totalBytesExpectedToSend > 0 else { return }
        
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        progressHandler(max(0.0, min(1.0, progress)))
        
        if totalBytesSent >= totalBytesExpectedToSend {
            progressHandlers.removeValue(forKey: task.taskIdentifier)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        progressHandlers.removeValue(forKey: task.taskIdentifier)
    }
    
    // MARK: - Utility MIME Detection
    
    private func mimeType(for fileURL: URL) -> String {
        let ext = fileURL.pathExtension.lowercased()
        
        if #available(macOS 11.0, *) {
            if let type = UTType(filenameExtension: ext),
               let mime = type.preferredMIMEType {
                return mime
            }
        }
        
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        default: return "application/octet-stream"
        }
    }
    
    private func debugLog(_ message: String) {
        #if DEBUG
        print("[CatboxUploader] \(message)")
        #endif
    }
}
