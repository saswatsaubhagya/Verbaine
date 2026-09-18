import Foundation

/// The provider every action runs against.
///
/// Resolved per call rather than cached: switching providers in Settings has to take effect on the
/// next action, not the next launch. Resolution is cheap — the on-device case returns a singleton,
/// and the remote case builds a struct around `URLSession.shared`.
enum Inference {
    static var current: any InferenceProvider { ModelService.shared }
}
