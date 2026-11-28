import ScoutCore

/// The readers for the system this binary runs on.
#if os(macOS)
typealias ServerSampler = MacSampler
#else
typealias ServerSampler = Sampler
#endif
