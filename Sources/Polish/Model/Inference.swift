import Foundation

/// The provider every action runs against.
///
/// Resolved per call rather than cached: switching providers in Settings has to take effect on the
/// next action, not the next launch. Resolution is cheap — the on-device case returns a singleton,
/// and the remote case builds a struct around `URLSession.shared`.
enum Inference {
    static var current: any InferenceProvider {
        guard Preferences.providerKind() == .remote else { return ModelService.shared }

        let config = Preferences.remoteConfig()
        guard let host = config.host, let key = APIKeyStore.load(forHost: host) else {
            // Configured as remote but the key is gone — a Keychain reset, or a base URL edited
            // after the key was saved. Falling back to the on-device model would quietly send the
            // text somewhere the user did not choose, so hand back a provider that explains itself.
            return OpenAICompatibleProvider(config: config, apiKey: "")
        }
        return OpenAICompatibleProvider(config: config, apiKey: key)
    }
}
