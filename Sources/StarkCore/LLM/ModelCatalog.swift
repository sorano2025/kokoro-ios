//
//  StarkCore
//
import Foundation
#if canImport(os)
import os
#endif

/// One downloadable open-weights model.
public struct ModelDescriptor: Codable, Sendable, Identifiable, Equatable {
  /// Hugging Face repo id, which is also the id MLX loads by.
  public var id: String
  public var name: String
  public var parameters: String
  public var quantization: String
  /// Download size on disk.
  public var diskGB: Double
  /// Working set once loaded — weights plus KV cache headroom.
  public var ramGB: Double
  public var contextTokens: Int
  public var license: String
  public var notes: String

  public init(id: String, name: String, parameters: String, quantization: String, diskGB: Double, ramGB: Double, contextTokens: Int, license: String, notes: String) {
    self.id = id
    self.name = name
    self.parameters = parameters
    self.quantization = quantization
    self.diskGB = diskGB
    self.ramGB = ramGB
    self.contextTokens = contextTokens
    self.license = license
    self.notes = notes
  }
}

/// Curated list of MLX-community conversions that run on Apple silicon.
///
/// Sizes are the published repo sizes; the runtime re-checks free space and the
/// app's memory limit before committing to a download, because "massive" on a
/// phone is bounded by a per-app allowance well below the device's RAM.
public enum ModelCatalog {
  public static let all: [ModelDescriptor] = [
    ModelDescriptor(
      id: "mlx-community/Qwen3-1.7B-4bit", name: "Qwen3 1.7B", parameters: "1.7B", quantization: "4-bit",
      diskGB: 1.0, ramGB: 1.6, contextTokens: 32768, license: "Apache-2.0",
      notes: "Fits every supported device. Good for triage and short replies."),
    ModelDescriptor(
      id: "mlx-community/Llama-3.2-3B-Instruct-4bit", name: "Llama 3.2 3B", parameters: "3B", quantization: "4-bit",
      diskGB: 1.8, ramGB: 2.6, contextTokens: 131072, license: "Llama 3.2 Community",
      notes: "Reliable everyday reply model on 6 GB devices."),
    ModelDescriptor(
      id: "mlx-community/Qwen3-4B-4bit", name: "Qwen3 4B", parameters: "4B", quantization: "4-bit",
      diskGB: 2.3, ramGB: 3.2, contextTokens: 32768, license: "Apache-2.0",
      notes: "Best quality-per-byte on 8 GB phones."),
    ModelDescriptor(
      id: "mlx-community/Ministral-8B-Instruct-2410-4bit", name: "Ministral 8B", parameters: "8B", quantization: "4-bit",
      diskGB: 4.5, ramGB: 5.8, contextTokens: 32768, license: "Mistral Research",
      notes: "Noticeably better at tone. Needs a 12 GB device to stay resident."),
    ModelDescriptor(
      id: "mlx-community/Qwen3-14B-4bit", name: "Qwen3 14B", parameters: "14B", quantization: "4-bit",
      diskGB: 8.1, ramGB: 9.5, contextTokens: 32768, license: "Apache-2.0",
      notes: "Large. Only load on 16 GB iPads or Macs; iPhones will be jetsammed."),
    ModelDescriptor(
      id: "mlx-community/Mistral-Small-24B-Instruct-2501-4bit", name: "Mistral Small 24B", parameters: "24B", quantization: "4-bit",
      diskGB: 13.3, ramGB: 15.0, contextTokens: 32768, license: "Apache-2.0",
      notes: "Desktop-class. Mac only in practice."),
  ]

  public static func descriptor(for id: String) -> ModelDescriptor? {
    all.first { $0.id == id }
  }

  /// Models that fit inside this device's per-app memory allowance, with a
  /// margin for the rest of the app.
  public static func fitting(memoryBudgetGB: Double = DeviceCapability.memoryBudgetGB) -> [ModelDescriptor] {
    all.filter { $0.ramGB <= memoryBudgetGB * 0.8 }
  }
}

/// What this particular device can actually hold.
public enum DeviceCapability {
  /// Memory this process may use before the system kills it, in gigabytes.
  ///
  /// iOS gives an app a fraction of physical RAM, not all of it, and
  /// `os_proc_available_memory` is the only number that reflects the real
  /// headroom left right now.
  public static var memoryBudgetGB: Double {
    #if os(iOS) || os(visionOS)
    let available = Double(os_proc_available_memory())
    if available > 0 { return available / 1_073_741_824 }
    #endif
    return Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 * 0.6
  }

  public static var physicalMemoryGB: Double {
    Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
  }

  public static var freeDiskGB: Double {
    Double(StarkPaths.availableDiskBytes()) / 1_073_741_824
  }

  /// Preflight for a download plus load.
  public static func check(_ model: ModelDescriptor) throws {
    let disk = freeDiskGB
    guard disk > model.diskGB * 1.15 else {
      throw ModelError.notEnoughDisk(needGB: model.diskGB * 1.15, haveGB: disk)
    }
    let memory = memoryBudgetGB
    guard memory > model.ramGB else {
      throw ModelError.notEnoughMemory(needGB: model.ramGB, haveGB: memory)
    }
  }
}
