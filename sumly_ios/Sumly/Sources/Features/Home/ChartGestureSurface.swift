import SwiftUI
import UIKit

/// A dedicated chart surface distinguishes one-finger inspection from two-finger navigation.
struct ChartGestureSurface: UIViewRepresentable {
    var begin: () -> Void
    var transform: (Double, Double, Double) -> Void
    var end: () -> Void
    var select: (Double) -> Void
    var reset: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        let coordinator = context.coordinator
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinch(_:)))
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.pan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        let inspect = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.inspect(_:)))
        inspect.maximumNumberOfTouches = 1
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tap(_:)))
        let reset = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.reset(_:)))
        reset.numberOfTapsRequired = 2
        tap.require(toFail: reset)
        for gesture in [pinch, pan, inspect, tap, reset] {
            gesture.delegate = coordinator
            view.addGestureRecognizer(gesture)
        }
        coordinator.pinchRecognizer = pinch
        coordinator.panRecognizer = pan
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.owner = self }
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.finish() }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var owner: ChartGestureSurface
        weak var pinchRecognizer: UIPinchGestureRecognizer?
        weak var panRecognizer: UIPanGestureRecognizer?
        private var active = Set<ObjectIdentifier>()
        private var scale = 1.0
        private var translation = 0.0
        private var anchor = 0.5
        init(_ owner: ChartGestureSurface) { self.owner = owner }
        func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
            (a === pinchRecognizer && b === panRecognizer) || (a === panRecognizer && b === pinchRecognizer)
        }
        private func beginIfNeeded(_ gesture: UIGestureRecognizer) {
            if active.isEmpty {
                scale = 1; translation = 0
                anchor = fraction(gesture)
                owner.begin()
            }
            active.insert(ObjectIdentifier(gesture))
        }
        private func fraction(_ gesture: UIGestureRecognizer) -> Double {
            guard let view = gesture.view, view.bounds.width > 0 else { return 0.5 }
            return min(1, max(0, gesture.location(in: view).x / view.bounds.width))
        }
        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            if gesture.state == .began { beginIfNeeded(gesture) }
            if !active.isEmpty { scale = gesture.scale; owner.transform(scale, anchor, translation) }
            finishIfNeeded(gesture)
        }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { beginIfNeeded(gesture) }
            if !active.isEmpty, let view = gesture.view, view.bounds.width > 0 {
                translation = gesture.translation(in: view).x / view.bounds.width
                owner.transform(scale, anchor, translation)
            }
            finishIfNeeded(gesture)
        }
        private func finishIfNeeded(_ gesture: UIGestureRecognizer) {
            if [.ended, .cancelled, .failed].contains(gesture.state) {
                active.remove(ObjectIdentifier(gesture))
                if active.isEmpty { owner.end() }
            }
        }
        func finish() { if !active.isEmpty { active.removeAll(); owner.end() } }
        @objc func inspect(_ gesture: UIPanGestureRecognizer) {
            if active.isEmpty && [.began, .changed].contains(gesture.state) { owner.select(fraction(gesture)) }
        }
        @objc func tap(_ gesture: UITapGestureRecognizer) { if active.isEmpty { owner.select(fraction(gesture)) } }
        @objc func reset(_ gesture: UITapGestureRecognizer) { finish(); owner.reset() }
    }
}
