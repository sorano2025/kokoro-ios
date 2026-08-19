//
//  StarkCore
//
import Foundation
import Security

/// Keychain-backed credential storage.
///
/// Tokens never go into the JSON config: that file is readable by anything that
/// can reach the app container, and a leaked platform token is an account
/// takeover. `kSecAttrAccessibleAfterFirstUnlock` is what lets the automation
/// loop keep running while the phone is locked in a pocket.
public enum TokenStore {
  private static let service = "stark.server.credentials"

  public static func set(_ token: String?, for connectionID: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: connectionID,
    ]
    SecItemDelete(query as CFDictionary)
    guard let token, !token.isEmpty else { return }
    var insert = query
    insert[kSecValueData as String] = Data(token.utf8)
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(insert as CFDictionary, nil)
  }

  public static func get(_ connectionID: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: connectionID,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data
    else { return nil }
    return String(decoding: data, as: UTF8.self)
  }

  public static func delete(_ connectionID: String) {
    set(nil, for: connectionID)
  }
}
