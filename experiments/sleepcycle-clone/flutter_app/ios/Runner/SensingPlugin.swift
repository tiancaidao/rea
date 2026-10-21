import Flutter
import CoreMotion

/// Streams accelerometer samples to Flutter over an EventChannel and start/stop
/// on a MethodChannel. A production build runs this under a background audio
/// session + UIBackgroundModes so sampling continues with the screen off; this
/// shows the channel wiring and the CoreMotion loop.
public class SensingPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private let motion = CMMotionManager()
    private var events: FlutterEventSink?
    private var sampleHz: Double = 50
    private let queue = OperationQueue()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SensingPlugin()
        let control = FlutterMethodChannel(name: "sleepclone/sensing",
                                           binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: control)
        let eventCh = FlutterEventChannel(name: "sleepclone/accelerometer",
                                          binaryMessenger: registrar.messenger())
        eventCh.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            if let args = call.arguments as? [String: Any],
               let hz = args["sampleHz"] as? Double { sampleHz = hz }
            startUpdates()
            result(nil)
        case "stop":
            motion.stopAccelerometerUpdates()
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startUpdates() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1.0 / sampleHz
        motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self = self, let d = data, let sink = self.events else { return }
            // CoreMotion reports in g; convert to m/s^2 to match the Android side.
            let g = 9.80665
            let sample = [d.acceleration.x * g, d.acceleration.y * g, d.acceleration.z * g]
            DispatchQueue.main.async { sink(sample) }
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        events = eventSink
        startUpdates()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        events = nil
        motion.stopAccelerometerUpdates()
        return nil
    }
}
