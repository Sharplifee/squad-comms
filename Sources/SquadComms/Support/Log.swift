import Foundation
import os

/// One subsystem so the whole app can be followed with a single predicate:
///
///     log stream --device --predicate 'subsystem == "com.connor.openline"'
///
/// Categories exist so each chain can be isolated while it is being trusted for
/// the first time. Everything below shipped without ever running on hardware,
/// so these are diagnostics, not decoration — leave them in.
enum Log {
    private static let subsystem = "com.connor.openline"

    /// Mic permission, AVAudioSession, VAD state, engine lifecycle.
    static let audio    = Logger(subsystem: subsystem, category: "audio")
    /// Speech authorization, buffers in, transcriptions out, intents dispatched.
    static let commands = Logger(subsystem: subsystem, category: "commands")
    /// CoreBluetooth advertise/scan, contact identity, fingerprint merges.
    static let ble      = Logger(subsystem: subsystem, category: "ble")
    /// Private line open/close, addressing, applied remote gains.
    static let priv     = Logger(subsystem: subsystem, category: "private")
    /// Squad create/join, LiveKit connect, first-launch path.
    static let session  = Logger(subsystem: subsystem, category: "session")
}
