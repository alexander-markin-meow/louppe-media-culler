import Foundation

enum AppBuildInfo {
    static var isReviewBuild: Bool {
        Bundle.main.object(forInfoDictionaryKey: "LouppeReviewBuild") as? Bool == true
    }

    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Louppe"
    }
}
