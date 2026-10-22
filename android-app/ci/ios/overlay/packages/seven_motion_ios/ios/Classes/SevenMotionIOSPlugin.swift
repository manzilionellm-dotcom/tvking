import Flutter
import UIKit
import AVFoundation
import Security

/// Le moteur vidéo reste media_kit. Ce pont apporte les services Apple qui
/// étaient auparavant confiés à MainActivity sur Android.
public final class SevenMotionIOSPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = SevenMotionIOSPlugin()
        for name in ["device", "pip"] {
            let channel = FlutterMethodChannel(
                name: "com.manzilionellm.tvking/\(name)",
                binaryMessenger: registrar.messenger())
            registrar.addMethodCallDelegate(plugin, channel: channel)
        }
        // La lecture reste audible avec le commutateur silencieux de l'iPhone.
        // setActive est laissé au lecteur : l'ouverture seule de l'app ne doit
        // pas interrompre la musique d'une autre application.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            NSLog("7 MOTION: audio session configuration failed")
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getInstallId":
            do { result(try installationID()) }
            catch { result(FlutterError(code: "KEYCHAIN_UNAVAILABLE", message: "Could not read the private installation identifier.", details: nil)) }
        case "getCredentialKey":
            do {
                let data = try keychainData(account: "seven-motion-credentials-v1") {
                    var bytes = [UInt8](repeating: 0, count: 32)
                    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
                    guard status == errSecSuccess else {
                        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
                    }
                    return Data(bytes)
                }
                result(data.base64EncodedString())
            } catch {
                result(FlutterError(code: "KEYCHAIN_UNAVAILABLE", message: "Could not read the credential key.", details: nil))
            }
        case "getAndroidId":
            result(nil)
        case "getDeviceInfo":
            // Informations d'assistance ; jamais utilisées comme empreinte.
            result(["manufacturer": "Apple", "model": UIDevice.current.model,
                    "release": UIDevice.current.systemVersion, "platform": "ios"])
        case "isPipSupported", "enterPip":
            // media_kit ne fournit pas ici de couche AVPlayer PiP. Le Dart
            // utilise ce verdict pour ne pas proposer un bouton inopérant.
            result(false)
        case "startBackgroundAudio":
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
                result(true)
            } catch {
                result(FlutterError(code: "AUDIO_SESSION", message: "Background audio could not start.", details: nil))
            }
        case "stopBackgroundAudio", "setAudioOnlyMode", "setPlaybackActive", "setAspectRatio":
            // Pas de service Android à arrêter. Ne pas désactiver la session
            // ici : le lecteur/radio peut encore l'utiliser au premier plan.
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// UUID aléatoire privé de l'app, conservé dans le trousseau local. Ni IDFA,
    /// ni numéro matériel, ni synchronisation iCloud. Une erreur de lecture
    /// n'écrase jamais une ancienne identité avec une nouvelle.
    private func installationID() throws -> String {
        let data = try keychainData(account: "seven-motion-installation-v1") {
            Data(UUID().uuidString.utf8)
        }
        guard let value = String(data: data, encoding: .utf8), !value.isEmpty else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errSecDecode))
        }
        return value
    }

    private func keychainData(account: String, create: () throws -> Data) throws -> Data {
        let service = Bundle.main.bundleIdentifier ?? "com.manzilionellm.sevenmotion"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data { return data }
        guard status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        let data = try create()
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let saved = SecItemAdd(insert as CFDictionary, nil)
        guard saved == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(saved))
        }
        return data
    }
}
