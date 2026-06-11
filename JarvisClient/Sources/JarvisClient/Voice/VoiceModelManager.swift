//
//  JarvisClient
//
import Foundation
import MLX
import MLXUtilsLibrary

/// Manages the on-device copy of the Kokoro TTS model weights and voice packs.
///
/// Kokoro's model file (`kokoro-v1_0.safetensors`) and voice packs (`voices.npz`)
/// are too large to bundle with the app, so they're downloaded once (or imported
/// from the Files app) and cached in the app's Documents directory.
@MainActor
final class VoiceModelManager: ObservableObject {
  enum Status: Equatable {
    case notReady
    case downloading(progress: Double)
    case loading
    case ready
    case failed(String)
  }

  @Published private(set) var status: Status = .notReady
  @Published private(set) var availableVoices: [String] = []

  private(set) var voices: [String: MLXArray] = [:]

  private let fileManager = FileManager.default
  private var activeDownloadDelegate: ProgressDownloadDelegate?
  private var activeDownloadSession: URLSession?

  private var modelDirectory: URL {
    let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("KokoroModel", isDirectory: true)
    if !fileManager.fileExists(atPath: dir.path) {
      try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    return dir
  }

  var modelFileURL: URL { modelDirectory.appendingPathComponent("kokoro-v1_0.safetensors") }
  var voicesFileURL: URL { modelDirectory.appendingPathComponent("voices.npz") }

  var isModelFilePresent: Bool { fileManager.fileExists(atPath: modelFileURL.path) }
  var isVoicesFilePresent: Bool { fileManager.fileExists(atPath: voicesFileURL.path) }
  var isReady: Bool { isModelFilePresent && isVoicesFilePresent }

  /// Looks up a voice embedding by its short name (e.g. "af_heart"),
  /// regardless of whether the loader stored it with a ".npy" suffix.
  func voiceEmbedding(named name: String) -> MLXArray? {
    voices["\(name).npy"] ?? voices[name]
  }

  func refreshStatus() {
    status = isReady ? .ready : .notReady
  }

  /// Loads `voices.npz` into memory (once) and populates `availableVoices`.
  func loadVoicesIfNeeded() async {
    guard voices.isEmpty, isVoicesFilePresent else { return }
    status = .loading
    let url = voicesFileURL
    let loaded = await Task.detached { () -> [String: MLXArray]? in
      NpyzReader.read(fileFromPath: url)
    }.value

    guard let loaded else {
      status = .failed("Could not read voices.npz — make sure it's a valid .npz archive of voice embeddings.")
      return
    }

    voices = loaded
    availableVoices = loaded.keys
      .map { key -> String in
        if let dot = key.firstIndex(of: ".") {
          return String(key[..<dot])
        }
        return key
      }
      .sorted()
    status = .ready
  }

  /// Copies a file picked from the Files app into place.
  func importModelFile(from url: URL) throws {
    try importFile(from: url, to: modelFileURL)
    refreshStatus()
  }

  /// Copies a `voices.npz` file picked from the Files app into place.
  func importVoicesFile(from url: URL) throws {
    try importFile(from: url, to: voicesFileURL)
    voices = [:]
    availableVoices = []
    refreshStatus()
  }

  private func importFile(from sourceURL: URL, to destinationURL: URL) throws {
    let accessing = sourceURL.startAccessingSecurityScopedResource()
    defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

    if fileManager.fileExists(atPath: destinationURL.path) {
      try fileManager.removeItem(at: destinationURL)
    }
    try fileManager.copyItem(at: sourceURL, to: destinationURL)
  }

  /// Downloads whichever of the model/voices files are missing.
  /// `modelURL`/`voicesURL` may be `nil` to skip that file.
  func download(modelURL: URL?, voicesURL: URL?) async {
    status = .downloading(progress: 0)
    do {
      if let modelURL, !isModelFilePresent {
        try await downloadFile(from: modelURL, to: modelFileURL) { progress in
          self.status = .downloading(progress: progress * (voicesURL != nil ? 0.85 : 1.0))
        }
      }
      if let voicesURL, !isVoicesFilePresent {
        try await downloadFile(from: voicesURL, to: voicesFileURL) { progress in
          self.status = .downloading(progress: 0.85 + progress * 0.15)
        }
      }
      refreshStatus()
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  private func downloadFile(from url: URL, to destination: URL, progress: @escaping (Double) -> Void) async throws {
    let tempURL: URL = try await withCheckedThrowingContinuation { continuation in
      let delegate = ProgressDownloadDelegate(progressHandler: progress, continuation: continuation)
      let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
      activeDownloadDelegate = delegate
      activeDownloadSession = session
      session.downloadTask(with: url).resume()
    }
    activeDownloadDelegate = nil
    activeDownloadSession = nil

    if fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    try fileManager.moveItem(at: tempURL, to: destination)
  }
}

/// Bridges `URLSessionDownloadDelegate` callbacks to async/await with progress reporting.
private final class ProgressDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  private let progressHandler: (Double) -> Void
  private let continuation: CheckedContinuation<URL, Error>

  init(progressHandler: @escaping (Double) -> Void, continuation: CheckedContinuation<URL, Error>) {
    self.progressHandler = progressHandler
    self.continuation = continuation
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    guard totalBytesExpectedToWrite > 0 else { return }
    progressHandler(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    do {
      try FileManager.default.moveItem(at: location, to: destination)
      continuation.resume(returning: destination)
    } catch {
      continuation.resume(throwing: error)
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let error {
      continuation.resume(throwing: error)
    }
  }
}
