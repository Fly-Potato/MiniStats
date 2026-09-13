enum BuildIdentity {
    #if DEBUG
    static let isDevelopment = true
    static let displayName = "MiniStats Dev"
    #else
    static let isDevelopment = false
    static let displayName = "MiniStats"
    #endif
}
