//
//  ITransport.swift
//  Hippo
//
//  Transport layer interface for video streaming
//  Enhanced with P0.1 resolution downsample configuration
//

import Foundation
import CoreVideo
import CoreMedia

// MARK: - Transport Protocol

/// Abstract transport interface for sending video frames
/// Implementation: WebRTC with H.264 encoding
public protocol ITransport: AnyObject {
    /// Start the transport session with external signaling client
    /// Initializes peer connection, creates offer
    /// - Parameter signalingClient: External SignalingClient managed by caller
    func start(with signalingClient: SignalingClient) throws

    /// Stop the transport session
    /// Closes peer connection, releases resources
    func stop()

    /// Transport state
    var state: TransportState { get }

    /// State change callback
    /// Called on state transitions
    var onStateChange: ((TransportState) -> Void)? { get set }
}

// MARK: - Video Transport Protocol

/// Extended transport protocol for video streaming
/// Adds video frame delivery capability
public protocol IVideoTransport: ITransport {
    /// Send a video frame through the transport
    /// @param pixelBuffer: Composed SBS frame (3840×1080 or 1920×1080)
    /// @param presentationTime: Frame timestamp for A/V sync
    func send(pixelBuffer: CVPixelBuffer, presentationTime: CMTime)

    /// Video statistics callback
    /// Called periodically with encoding/network stats
    var onStats: ((VideoTransportStats) -> Void)? { get set }
}

// MARK: - Transport State

/// Transport connection state
public enum TransportState: String, Codable {
    case idle          // Not started
    case connecting    // Signaling in progress
    case connected     // Peer connection established
    case disconnected  // Connection lost
    case failed        // Connection failed
    case closed        // Transport closed

    public var isActive: Bool {
        self == .connected
    }
}

// MARK: - Transport Statistics

/// Video transport statistics
/// Provided by WebRTC RTCPeerConnection.statistics()
public struct VideoTransportStats {
    public let timestamp: Date

    // Encoding stats
    public let framesSent: Int
    public let framesEncoded: Int
    public let framesDropped: Int
    public let encodeTimeMs: Double

    // Network stats
    public let bytesSent: Int64
    public let bitrateMbps: Double
    public let packetsSent: Int
    public let packetsLost: Int

    // Quality stats
    public let qpSum: Int64        // Quantization parameter sum
    public let keyFramesSent: Int
    public let targetBitrate: Double

    public init(
        timestamp: Date = Date(),
        framesSent: Int = 0,
        framesEncoded: Int = 0,
        framesDropped: Int = 0,
        encodeTimeMs: Double = 0.0,
        bytesSent: Int64 = 0,
        bitrateMbps: Double = 0.0,
        packetsSent: Int = 0,
        packetsLost: Int = 0,
        qpSum: Int64 = 0,
        keyFramesSent: Int = 0,
        targetBitrate: Double = 0.0
    ) {
        self.timestamp = timestamp
        self.framesSent = framesSent
        self.framesEncoded = framesEncoded
        self.framesDropped = framesDropped
        self.encodeTimeMs = encodeTimeMs
        self.bytesSent = bytesSent
        self.bitrateMbps = bitrateMbps
        self.packetsSent = packetsSent
        self.packetsLost = packetsLost
        self.qpSum = qpSum
        self.keyFramesSent = keyFramesSent
        self.targetBitrate = targetBitrate
    }

    /// Packet loss ratio (0.0 ~ 1.0)
    public var packetLossRatio: Double {
        guard packetsSent > 0 else { return 0.0 }
        return Double(packetsLost) / Double(packetsSent + packetsLost)
    }

    /// Encoding efficiency (frames encoded / frames sent)
    public var encodingEfficiency: Double {
        guard framesSent > 0 else { return 0.0 }
        return Double(framesEncoded) / Double(framesSent)
    }
}

// MARK: - Transport Configuration

/// Configuration for transport layer
/// WebRTC-specific settings
///
/// P0.1 Enhancement: Added resolutionDownsampleFactor
public struct TransportConfig {
    // Network
    public let stunServers: [String]
    public let turnServers: [TURNServer]

    // Video encoding (H.264)
    public let codec: VideoCodec
    public let targetBitrate: Int      // bits per second
    public let maxBitrate: Int
    public let minBitrate: Int

    // Quality
    public let degradationPreference: DegradationPreference
    public let enableAdaptiveBitrate: Bool

    // P0.1: Resolution downsampling control
    /// Resolution downsample factor (1 = no downsampling, 2 = half, 3 = third)
    /// Default: 1 (no downsampling for maximum quality)
    /// Use 2 or 3 for bandwidth-constrained scenarios
    public let resolutionDownsampleFactor: Int

    /// Standard configuration (no downsampling, 30 Mbps for full quality)
    public static let standard = TransportConfig(
        stunServers: ["stun:stun.l.google.com:19302"],
        turnServers: [],
        codec: .h264(.baseline),
        targetBitrate: 30_000_000,          // 30 Mbps (for full resolution 3840×1080@60fps)
        maxBitrate: 45_000_000,             // 45 Mbps
        minBitrate: 10_000_000,             // 10 Mbps
        degradationPreference: .maintainResolution,
        enableAdaptiveBitrate: true,
        resolutionDownsampleFactor: 1       // P0.1: No downsampling by default
    )

    /// Low bandwidth configuration (2x downsampling, 15 Mbps)
    public static let lowBandwidth = TransportConfig(
        stunServers: ["stun:stun.l.google.com:19302"],
        turnServers: [],
        codec: .h264(.baseline),
        targetBitrate: 15_000_000,          // 15 Mbps
        maxBitrate: 20_000_000,             // 20 Mbps
        minBitrate: 5_000_000,              // 5 Mbps
        degradationPreference: .maintainResolution,
        enableAdaptiveBitrate: true,
        resolutionDownsampleFactor: 2       // P0.1: 2x downsampling for bandwidth saving
    )

    /// WiFi hotspot configuration — conservative bitrate for Mac hotspot → Galaxy XR
    /// Measured: ~0.7-1.5 Mbps actual throughput on 2.4GHz WiFi hotspot
    /// Previous 8Mbps max caused GCC to probe→overshoot→6s pause cycle
    public static let wifiHotspot = TransportConfig(
        stunServers: ["stun:stun.l.google.com:19302"],
        turnServers: [],
        codec: .h264(.baseline),
        targetBitrate: 1_500_000,           // 1.5 Mbps target (measured throughput)
        maxBitrate: 2_500_000,              // 2.5 Mbps max (prevent overshoot probing)
        minBitrate: 100_000,                // 100 Kbps min — let GCC adapt freely
        degradationPreference: .maintainResolution,  // prioritize image quality over fps
        enableAdaptiveBitrate: true,
        resolutionDownsampleFactor: 1
    )

    /// Home WiFi / dedicated router configuration (2.4GHz)
    /// GCC freeze diagnosis (2026-03-14): GCC probes up → 2.4GHz WiFi jitter → congestion
    /// detection → 4-6s transmission halt → repeat. Even maxBitrate=4Mbps caused probes
    /// to overshoot actual WiFi capacity (~1-3Mbps on 2.4GHz).
    /// Fix (2026-03-14): Tighten to max=2.5Mbps + SDP x-google-max-bitrate munging
    /// to constrain GCC probe ceiling at codec level. 2.5Mbps sufficient for 1280×360@30fps.
    public static let wifiHome = TransportConfig(
        stunServers: ["stun:stun.l.google.com:19302"],
        turnServers: [],
        codec: .h264(.baseline),
        targetBitrate: 2_000_000,           // 2 Mbps target (within 2.4GHz WiFi capacity)
        maxBitrate: 2_500_000,              // 2.5 Mbps max (tight ceiling prevents GCC overshoot)
        minBitrate: 300_000,                // 300 Kbps min (let GCC adapt freely downward)
        degradationPreference: .maintainResolution,
        enableAdaptiveBitrate: true,
        resolutionDownsampleFactor: 1
    )

    /// 5GHz WiFi / dedicated router configuration (ASUS RT-BE58 Go)
    /// Measured: actual throughput ~3-5Mbps to Galaxy XR over 5GHz WiFi.
    /// Previous 8Mbps max caused GCC probe→overshoot→6s pause (same pattern as 2.4GHz).
    /// Fix: target=3Mbps matches observed stable rate + setBweMinBitrateBps override.
    public static let wifi5GHz = TransportConfig(
        stunServers: ["stun:stun.l.google.com:19302"],
        turnServers: [],
        codec: .h264(.baseline),
        targetBitrate: 5_000_000,           // 5 Mbps target (more bits/pixel for 960×540)
        maxBitrate: 6_000_000,              // 6 Mbps max
        minBitrate: 2_000_000,              // 2 Mbps min
        degradationPreference: .maintainResolution,
        enableAdaptiveBitrate: true,
        resolutionDownsampleFactor: 2       // Half SBS 1920×1080 → 960×540 encoding
    )

    public init(
        stunServers: [String],
        turnServers: [TURNServer],
        codec: VideoCodec,
        targetBitrate: Int,
        maxBitrate: Int,
        minBitrate: Int,
        degradationPreference: DegradationPreference,
        enableAdaptiveBitrate: Bool,
        resolutionDownsampleFactor: Int = 1  // P0.1: Default to no downsampling
    ) {
        self.stunServers = stunServers
        self.turnServers = turnServers
        self.codec = codec
        self.targetBitrate = targetBitrate
        self.maxBitrate = maxBitrate
        self.minBitrate = minBitrate
        self.degradationPreference = degradationPreference
        self.enableAdaptiveBitrate = enableAdaptiveBitrate
        self.resolutionDownsampleFactor = max(1, resolutionDownsampleFactor)  // Minimum 1
    }
}

// MARK: - TURN Server

public struct TURNServer {
    public let url: String
    public let username: String
    public let credential: String

    public init(url: String, username: String, credential: String) {
        self.url = url
        self.username = username
        self.credential = credential
    }
}

// MARK: - Video Codec

public enum VideoCodec {
    case h264(H264Profile)
    case h265  // Future support
    case vp8
    case vp9

    public var mimeType: String {
        switch self {
        case .h264: return "video/H264"
        case .h265: return "video/H265"
        case .vp8: return "video/VP8"
        case .vp9: return "video/VP9"
        }
    }
}

public enum H264Profile: String {
    case baseline = "42e01f"
    case main = "4d001f"
    case high = "640c1f"
    case constrainedHigh = "640c2f"

    public var levelIdcString: String {
        return "31"  // Level 3.1 for 1080p30, adjust for higher resolutions
    }
}

// MARK: - Degradation Preference

/// RTCDegradationPreference equivalent
public enum DegradationPreference {
    case disabled               // No adaptation
    case maintainFramerate     // Reduce resolution under bandwidth pressure
    case maintainResolution    // Reduce framerate under bandwidth pressure
    case balanced              // Balanced adaptation

    public var rtcValue: String {
        switch self {
        case .disabled: return "disabled"
        case .maintainFramerate: return "maintain-framerate"
        case .maintainResolution: return "maintain-resolution"
        case .balanced: return "balanced"
        }
    }
}
