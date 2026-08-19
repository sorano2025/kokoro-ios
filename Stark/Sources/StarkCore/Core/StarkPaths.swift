//
//  StarkCore
//
import Foundation

/// Where the server keeps its state on disk.
///
/// State lives under Application Support so it survives relaunches and stays
/// out of the document pickers. Model weights go where `HubApi` puts them —
/// Documents/huggingface — with the backup flag cleared, because a 13 GB model
/// silently added to a user's iCloud backup is its own kind of bug.
public enum StarkPaths {
  public static var root: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let dir = base.appendingPathComponent("Stark", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  public static var models: URL {
    let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    var dir = base.appendingPathComponent("huggingface", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? dir.setResourceValues(values)
    return dir
  }

  public static func file(_ name: String) -> URL {
    root.appendingPathComponent(name)
  }

  /// Free space on the volume holding the model cache, in bytes.
  public static func availableDiskBytes() -> Int64 {
    let values = try? models.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values?.volumeAvailableCapacityForImportantUsage ?? 0
  }
}
