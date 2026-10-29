import AppKit
import SwiftUI
import NotchProtocol
import NotchCore

@MainActor
private enum ArtworkCache {
    static let images: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 64
        return cache
    }()
    static var pending: [String: Task<NSImage?, Never>] = [:]

    static func load(_ source: String?) async -> NSImage? {
        guard let source, NowPlayingState.isArtworkSource(source) else { return nil }
        if let image = images.object(forKey: source as NSString) { return image }
        if let task = pending[source] { return await task.value }
        let task = Task<NSImage?, Never> {
            let data: Data?
            if source.hasPrefix("data:"), let comma = source.firstIndex(of: ",") {
                data = Data(base64Encoded: String(source[source.index(after: comma)...]))
            } else if let url = URL(string: source) {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                if let (bytes, response) = try? await URLSession.shared.data(for: request),
                   (response as? HTTPURLResponse)?.statusCode == 200, bytes.count <= 2_000_000 {
                    data = bytes
                } else { data = nil }
            } else { data = nil }
            guard let data, let image = NSImage(data: data) else { return nil }
            images.setObject(image, forKey: source as NSString)
            return image
        }
        pending[source] = task
        let result = await task.value
        pending[source] = nil
        return result
    }

    static func tint(_ image: NSImage?) -> Color {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white.opacity(0.7) }
        var pixels: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(data: &pixels, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return .white.opacity(0.7) }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        // Lift dark covers enough to keep the progress track and waveform readable on black.
        return Color(red: max(0.38, Double(pixels[0]) / 255),
                     green: max(0.38, Double(pixels[1]) / 255), blue: max(0.38, Double(pixels[2]) / 255))
    }
}

struct AlbumArtwork: View {
    let source: String?
    var size: CGFloat = 18
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22).fill(.white.opacity(0.09))
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .overlay(RoundedRectangle(cornerRadius: size * 0.22).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .task(id: source) {
            let loaded = await ArtworkCache.load(source)
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .accessibilityHidden(true)
    }
}

struct PlaybackWaveform: View {
    let playing: Bool
    var source: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tint: Color = .white.opacity(0.65)
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.18, paused: !playing || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4) { index in
                    Capsule().fill(tint)
                        .frame(width: 2, height: playing ? 4 + 9 * (0.5 + 0.5 * sin(time * (3.2 + Double(index) * 0.7) + Double(index) * 1.8)) : 3)
                }
            }
            .frame(width: 16, height: 16)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: time)
        }
        .task(id: source) {
            let image = await ArtworkCache.load(source)
            guard !Task.isCancelled else { return }
            tint = ArtworkCache.tint(image)
        }
        .accessibilityLabel(playing ? "Playing" : "Paused")
    }
}

struct MusicPlayerView: View {
    let state: NowPlayingState
    let cameraHeight: CGFloat
    let onCommand: (MediaRequest) -> Void
    @State private var seeking: Double?
    @State private var feedback = PlaybackFeedback()
    @State private var tint: Color = .white.opacity(0.65)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let displayed = feedback.displayed(state)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 9) {
                Button { onCommand(.init(command: .openPlayer)) } label: {
                    AlbumArtwork(source: state.artwork, size: 60)
                }.buttonStyle(.plain).accessibilityLabel("Open \(state.player.name)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title).font(.system(size: 14, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                    Text(state.artist).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                }
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                // The header starts 14 pt from the screen edge. Keep both text
                // lines below the physical camera, even on taller notches.
                .padding(.top, max(16, cameraHeight - 8))
                PlaybackWaveform(playing: displayed.isPlaying, source: state.artwork).frame(height: 60).padding(.trailing, 25)
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let playback = feedback.displayed(state, now: timeline.date)
                let fraction = seeking ?? (state.duration > 0 ? playback.position / state.duration : 0)
                HStack(spacing: 10) {
                    Text(Self.time(fraction * state.duration)).frame(width: 30, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18))
                            Capsule().fill(tint).frame(width: proxy.size.width * fraction)
                        }
                        .frame(height: 4).frame(height: proxy.size.height)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                seeking = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                            }
                            .onEnded { value in
                                let target = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                                submit(.init(command: .seek, value: target))
                                seeking = nil
                            })
                    }
                    .frame(height: 16)
                    .disabled(state.duration <= 0)
                    .accessibilityRepresentation {
                        Slider(value: Binding(get: { fraction }, set: { value in
                            submit(.init(command: .seek, value: value))
                        }), in: 0...1)
                        .accessibilityLabel("Playback position")
                    }
                    Text(Self.time(state.duration)).frame(width: 30, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.top, 22)
            HStack(spacing: 14) {
                control("shuffle", command: .shuffle, label: "Shuffle", size: 17, active: displayed.shuffle, secondary: true)
                control("backward.fill", command: .previous, label: "Previous track", size: 25)
                Button { submit(.init(command: .playPause)) } label: {
                    ZStack {
                        Image(systemName: "play.fill").opacity(displayed.isPlaying ? 0 : 1)
                            .scaleEffect(reduceMotion || !displayed.isPlaying ? 1 : 0.65)
                            .blur(radius: reduceMotion || !displayed.isPlaying ? 0 : 3)
                        Image(systemName: "pause.fill").opacity(displayed.isPlaying ? 1 : 0)
                            .scaleEffect(reduceMotion || displayed.isPlaying ? 1 : 0.65)
                            .blur(radius: reduceMotion || displayed.isPlaying ? 0 : 3)
                    }
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 44, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(NotchPressStyle())
                .accessibilityLabel(displayed.isPlaying ? "Pause" : "Play")
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: displayed.isPlaying)
                control("forward.fill", command: .next, label: "Next track", size: 25)
                control("repeat", command: .repeatMode, label: "Repeat", size: 17, active: displayed.repeating, secondary: true)
            }
            .foregroundStyle(.white)
            .padding(.top, 15)
        }
        .onChange(of: state, initial: true) { _, sample in feedback.receive(sample) }
        .task(id: feedback.nextExpiry) {
            guard let deadline = feedback.nextExpiry else { return }
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
            catch { return }
            feedback.expire(now: deadline)
        }
        .task(id: state.artwork) {
            let image = await ArtworkCache.load(state.artwork)
            guard !Task.isCancelled else { return }
            tint = ArtworkCache.tint(image)
        }
    }

    private func submit(_ request: MediaRequest) {
        feedback.begin(request, state: state)
        onCommand(request)
    }

    private func control(_ symbol: String, command: MediaCommand, label: String, size: CGFloat,
                         active: Bool = false, secondary: Bool = false) -> some View {
        Button { submit(.init(command: command)) } label: {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .foregroundStyle(active ? tint : .white.opacity(secondary ? 0.45 : 1))
                .frame(width: 40, height: 40).contentShape(Rectangle())
        }
        .buttonStyle(NotchPressStyle()).accessibilityLabel(label)
        .accessibilityValue(secondary ? (active ? "On" : "Off") : "")
    }
    private static func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
