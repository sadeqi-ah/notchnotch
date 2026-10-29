import Foundation
import JavaScriptCore
import NotchProtocol

/// JavaScriptCore is confined to the runner's main thread, never the app's UI process.
@MainActor
public final class JavaScriptRuntime {
    private var context: JSContext?
    private var timers: [Int32: Timer] = [:]
    private var callbacks: [Int32: JSValue] = [:]
    private var nextTimer: Int32 = 0
    private var lastException: String?
    private let extensionID: String
    private let send: (String) -> Void

    public init(extensionID: String, send: @escaping (String) -> Void) throws {
        self.extensionID = extensionID
        self.send = send
        guard let context = JSContext() else { throw ProtocolError.invalid("Could not create JavaScript context") }
        self.context = context
        context.exceptionHandler = { [weak self] _, exception in
            MainActor.assumeIsolated {
                let message = exception?.toString() ?? "JavaScript exception"
                self?.lastException = message
                self?.notice(message, type: "error")
            }
        }
        let sendBlock: @convention(block) (String) -> Void = { [weak self] json in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard json.utf8.count <= maximumMessageBytes else {
                    self.notice("Extension message exceeded 256 KiB", type: "error"); return
                }
                self.send(json)
            }
        }
        let scheduleBlock: @convention(block) (JSValue, Double, Bool) -> Int32 = { [weak self] callback, delay, repeats in
            MainActor.assumeIsolated { self?.schedule(callback, milliseconds: delay, repeats: repeats) ?? -1 }
        }
        let cancelBlock: @convention(block) (Int32) -> Void = { [weak self] identifier in
            MainActor.assumeIsolated {
                self?.timers.removeValue(forKey: identifier)?.invalidate()
                self?.callbacks.removeValue(forKey: identifier)
            }
        }
        context.setObject(sendBlock, forKeyedSubscript: "__nativeSend" as NSString)
        context.setObject(scheduleBlock, forKeyedSubscript: "__nativeSchedule" as NSString)
        context.setObject(cancelBlock, forKeyedSubscript: "__nativeCancel" as NSString)
        context.setObject(extensionID, forKeyedSubscript: "__notchnotchExtensionID" as NSString)
        context.evaluateScript(Self.bootstrap)
    }

    public func evaluate(_ script: String, sourceURL: URL? = nil) throws {
        guard let context else { throw ProtocolError.invalid("Runtime is stopped") }
        context.exception = nil
        lastException = nil
        context.evaluateScript(script, withSourceURL: sourceURL)
        if let lastException { throw ProtocolError.invalid(lastException) }
    }

    public func receive(_ json: String) {
        if json.utf8.count <= maximumMessageBytes, let data = json.data(using: .utf8),
           let update = try? JSONDecoder().decode(MediaUpdate.self, from: data),
           update.protocolVersion == 1, update.type == "media" {
            if let state = update.state, (try? state.validate()) == nil { return }
            context?.objectForKeyedSubscript("__notchnotchDispatch")?.call(withArguments: [json])
            return
        }
        guard json.utf8.count <= 8192, let data = json.data(using: .utf8),
              let event = try? JSONDecoder().decode(UserEvent.self, from: data),
              event.protocolVersion == 1, event.type == "event", event.action.count <= 128,
              (event.value?.count ?? 0) <= 4096 else { return }
        context?.objectForKeyedSubscript("__notchnotchDispatch")?.call(withArguments: [json])
    }

    public func stop() {
        for timer in timers.values { timer.invalidate() }
        timers.removeAll()
        callbacks.removeAll()
        context?.exceptionHandler = nil
        context = nil
    }

    private func schedule(_ callback: JSValue, milliseconds: Double, repeats: Bool) -> Int32 {
        guard timers.count < 128, milliseconds.isFinite else {
            notice("Too many timers or invalid timer delay", type: "error"); return -1
        }
        nextTimer += 1
        let identifier = nextTimer
        callbacks[identifier] = callback
        let interval = max(repeats ? 10 : 0, min(milliseconds, 86_400_000)) / 1000
        let timer = Timer(timeInterval: interval, repeats: repeats) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let callback = self.callbacks[identifier] else { return }
                if !repeats {
                    self.timers.removeValue(forKey: identifier)
                    self.callbacks.removeValue(forKey: identifier)
                }
                callback.call(withArguments: [])
            }
        }
        timers[identifier] = timer
        RunLoop.main.add(timer, forMode: .common)
        return identifier
    }

    private func notice(_ message: String, type: String) {
        if let data = try? JSONEncoder().encode(RuntimeNotice(type: type, extensionID: extensionID, message: message)),
           let json = String(data: data, encoding: .utf8) { send(json) }
    }

    private static let bootstrap = #"""
    globalThis.__notchnotchSend = (json) => __nativeSend(String(json));
    globalThis.setTimeout = (callback, delay = 0, ...args) =>
      __nativeSchedule(() => callback(...args), Number(delay) || 0, false);
    globalThis.setInterval = (callback, delay = 0, ...args) =>
      __nativeSchedule(() => callback(...args), Number(delay) || 0, true);
    globalThis.clearTimeout = globalThis.clearInterval = (id) => __nativeCancel(id);
    globalThis.queueMicrotask = (callback) => Promise.resolve().then(callback).catch((error) => {
      __notchnotchSend(JSON.stringify({ protocolVersion: 1, type: 'error',
        extensionID: __notchnotchExtensionID, message: String(error) }));
    });
    const bootTime = Date.now();
    globalThis.performance = { now: () => Date.now() - bootTime };
    const log = (...args) => __notchnotchSend(JSON.stringify({ protocolVersion: 1,
      type: 'log', extensionID: __notchnotchExtensionID, message: args.map(String).join(' ').slice(0, 4096) }));
    globalThis.console = { log, info: log, warn: log, error: log, debug: log };
    """#
}
