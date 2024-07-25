//
//  GestureCoordinator.swift
//  
//
//  Created by Jim Hanson on 3/21/24.
//

import SwiftUI
import MetalKit

#if os(iOS) // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

public class GestureCoordinator: NSObject, UIGestureRecognizerDelegate {

    var handlers: GestureHandlers

    public init(_ handlers: GestureHandlers) {
        self.handlers = handlers
    }

    public func connectGestures(_ mtkView: MTKView) {

        if handlers.primaryTap != nil {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(primaryTap))
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.secondaryTap != nil {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(secondaryTap))
            recognizer.numberOfTouchesRequired = 2
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.primaryLongPress != nil {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(primaryLongPress))
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.secondaryLongPress != nil {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(secondaryLongPress))
            recognizer.numberOfTouchesRequired = 2
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.primaryDrag != nil {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(primaryDrag))
            recognizer.maximumNumberOfTouches = 1
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.secondaryDrag != nil {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(secondaryDrag))
            recognizer.minimumNumberOfTouches = 2
            recognizer.maximumNumberOfTouches = 2
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.pinch !=  nil {
            let recognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinch))
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.rotation != nil {
            let recognizer = UIRotationGestureRecognizer(target: self, action: #selector(rotation))
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }
    }

    public func disconnectGestures(_ mtkView: MTKView) {
        mtkView.gestureRecognizers?.forEach({ mtkView.removeGestureRecognizer($0) })
    }

    @objc func primaryTap(_ gesture: UITapGestureRecognizer) {
        if let view = gesture.view {
            switch gesture.state {
            case .ended:
                handlers.primaryTap?.tap(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            default:
                break
            }
        }
    }

    @objc func secondaryTap(_ gesture: UITapGestureRecognizer) {
        if let view = gesture.view {
            switch gesture.state {
            case .ended:
                handlers.secondaryTap?.tap(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            default:
                break
            }
        }
    }

    @objc func primaryLongPress(_ gesture: UILongPressGestureRecognizer) {
        if let view = gesture.view {
            switch gesture.state {
            case .began:
                handlers.primaryLongPress?.longPressBegan(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                handlers.primaryLongPress?.longPressMoved(to: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .ended:
                handlers.primaryLongPress?.longPressEnded(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            default:
                break
            }
        }
    }

    @objc func secondaryLongPress(_ gesture: UILongPressGestureRecognizer) {
        if let view = gesture.view {
            switch gesture.state {
            case .began:
                handlers.secondaryLongPress?.longPressBegan(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                handlers.secondaryLongPress?.longPressMoved(to: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .ended:
                handlers.secondaryLongPress?.longPressEnded(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            default:
                break
            }
        }
    }

    @objc func primaryDrag(_ gesture: UIPanGestureRecognizer) {
        if let view = gesture.view {
            switch gesture.state {
            case .possible:
                break
            case .began:
                handlers.primaryDrag?.dragBegan(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                let translation = gesture.translation(in: view)
                // NOTE the factor of -1 on the scroll
                handlers.primaryDrag?.dragChanged(panFraction: Float(translation.x / view.bounds.width),
                                                  scrollFraction: Float(-translation.y / view.bounds.height))
            default:
                handlers.primaryDrag?.dragEnded()
            }
        }
    }

    @objc func secondaryDrag(_ gesture: UIPanGestureRecognizer) {
        if let view = gesture.view {
            switch gesture.state {
            case .possible:
                break
            case .began:
                handlers.secondaryDrag?.dragBegan(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                let translation = gesture.translation(in: view)
                // NOTE the factor of -1 on the scroll
                handlers.secondaryDrag?.dragChanged(panFraction: Float(translation.x / view.bounds.width),
                                                    scrollFraction: Float(-translation.y / view.bounds.height))
            default:
                handlers.secondaryDrag?.dragEnded()
            }
        }
    }

    @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.numberOfTouches < 2 {
            return
        }

        if let view = gesture.view {
            switch gesture.state {
            case .possible:
                break
            case .began:
                handlers.pinch?.pinchBegan(at: GestureCoordinator.clipPoint(gesture.location(ofTouch: 0, in: view),
                                                                          gesture.location(ofTouch: 1, in: view),
                                                                          view.bounds))
            case .changed:
                handlers.pinch?.pinchChanged(scale: Float(gesture.scale))
            default:
                handlers.pinch?.pinchEnded()
            }
        }
    }

    @objc func rotation(_ gesture: UIRotationGestureRecognizer) {
        if gesture.numberOfTouches < 2 {
            return
        }

        if let view = gesture.view {
            switch gesture.state {
            case .possible:
                break
            case .began:
                handlers.rotation?.rotationBegan(at: GestureCoordinator.clipPoint(gesture.location(ofTouch: 0, in: view),
                                                                                gesture.location(ofTouch: 1, in: view),
                                                                                view.bounds))
            case .changed:
                handlers.rotation?.rotationChanged(radians: Float(gesture.rotation))
            default:
                handlers.rotation?.rotationEnded()
            }
        }
    }

    // NO: I still have problems with simultaneous drag,pinch,rotate
    //
    //    /// Support for simultaneous gestures.
    //    public func gestureRecognizer(_ first: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith second: UIGestureRecognizer) -> Bool {
    //        // Disallow combos that include tap or long press.
    //        if first is UITapGestureRecognizer || first is UILongPressGestureRecognizer {
    //            return false
    //        }
    //
    //        // Disallow combos that include pinch. We only do this because of a bug in POV
    //        // controller: pinch interferes with drag and rotation step on each other.
    //        if first is UIPinchGestureRecognizer {
    //            return false
    //        }
    //
    //        // Allow everything else.
    //        return true
    //    }

    private func isPOVGesture(_ recognizer: UIGestureRecognizer) -> Bool {
        return recognizer is UIPanGestureRecognizer || recognizer is UIPinchGestureRecognizer || recognizer is UIRotationGestureRecognizer
    }
}

#elseif os(macOS) // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

public class GestureCoordinator: NSObject, NSGestureRecognizerDelegate {

    var handlers: GestureHandlers

    public init(_ handlers: GestureHandlers) {
        self.handlers = handlers
    }

    public func connectGestures(_ mtkView: MTKView) {

        if handlers.primaryTap != nil {
            let recognizer = NSClickGestureRecognizer(target: self, action: #selector(primaryTap))
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.secondaryTap != nil {
            let recognizer = NSClickGestureRecognizer(target: self, action: #selector(secondaryTap))
            recognizer.buttonMask = 0x2
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.primaryLongPress != nil {
            let recognizer = NSPressGestureRecognizer(target: self, action: #selector(primaryLongPress))
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.secondaryLongPress != nil {
            let recognizer = NSPressGestureRecognizer(target: self, action: #selector(secondaryLongPress))
            recognizer.buttonMask = 0x2
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.primaryDrag != nil {
            let recognizer = NSPanGestureRecognizer(target: self, action: #selector(primaryDrag))
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.secondaryDrag != nil {
            let recognizer = NSPanGestureRecognizer(target: self, action: #selector(secondaryDrag))
            recognizer.buttonMask = 0x2
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }


        if handlers.pinch !=  nil {
            let recognizer = NSMagnificationGestureRecognizer(target: self, action: #selector(pinch))
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }

        if handlers.rotation != nil {
            let recognizer = NSRotationGestureRecognizer(target: self, action: #selector(rotation))
            recognizer.delegate = self
            mtkView.addGestureRecognizer(recognizer)
        }
    }

    public func disconnectGestures(_ mtkView: MTKView) {
        mtkView.gestureRecognizers.forEach({ mtkView.removeGestureRecognizer($0) })
    }

    @MainActor
    @objc func primaryTap(_ gesture: NSClickGestureRecognizer) {
        if let view = gesture.view {
            switch gesture.state {
            case .ended:
                handlers.primaryTap?.tap(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            default:
                break
            }
        }
    }

    @MainActor
    @objc func secondaryTap(_ gesture: NSClickGestureRecognizer) {
        if let view = gesture.view {
            switch gesture.state {
            case .ended:
                handlers.secondaryTap?.tap(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            default:
                break
            }
        }
    }

    @MainActor
    @objc func primaryLongPress(_ gesture: NSPressGestureRecognizer) {
        if let view = gesture.view  {
            switch gesture.state {
            case .began:
                handlers.primaryLongPress?.longPressBegan(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                handlers.primaryLongPress?.longPressMoved(to: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .ended:
                handlers.primaryLongPress?.longPressEnded(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            default:
                break
            }
        }
    }

    @MainActor
    @objc func secondaryLongPress(_ gesture: NSPressGestureRecognizer) {
        if let view = gesture.view  {
            switch gesture.state {
            case .began:
                handlers.secondaryLongPress?.longPressBegan(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                handlers.secondaryLongPress?.longPressMoved(to: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .ended:
                handlers.secondaryLongPress?.longPressEnded(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            default:
                break
            }
        }
    }

    @MainActor
    @objc func primaryDrag(_ gesture: NSPanGestureRecognizer) {
        if let view = gesture.view  {
            switch gesture.state {
            case .possible:
                break
            case .began:
                handlers.primaryDrag?.dragBegan(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                let translation = gesture.translation(in: view)
                // macOS uses upside-down clip coords, so the scroll value is the opposite of that on iOS
                handlers.primaryDrag?.dragChanged(panFraction: Float(translation.x / view.bounds.width),
                                                  scrollFraction: Float(translation.y / view.bounds.height))
            default:
                handlers.primaryDrag?.dragEnded()
            }
        }
    }

    @MainActor
    @objc func secondaryDrag(_ gesture: NSPanGestureRecognizer) {
        if let view = gesture.view  {
            switch gesture.state {
            case .possible:
                break
            case .began:
                handlers.secondaryDrag?.dragBegan(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                let translation = gesture.translation(in: view)
                // macOS uses upside-down clip coords, so the scroll value is the opposite of that on iOS
                handlers.secondaryDrag?.dragChanged(panFraction: Float(translation.x / view.bounds.width),
                                                    scrollFraction: Float(translation.y / view.bounds.height))
            default:
                handlers.secondaryDrag?.dragEnded()
            }
        }
    }

    @MainActor
    @objc func pinch(_ gesture: NSMagnificationGestureRecognizer) {
        if let view = gesture.view  {
            switch gesture.state {
            case .possible:
                break
            case .began:
                handlers.pinch?.pinchBegan(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                // macOS gesture's magnification=0 corresponds to iOS gesture's scale=1
                handlers.pinch?.pinchChanged(scale: Float(1 + gesture.magnification))
            default:
                handlers.pinch?.pinchEnded()
            }
        }
    }

    @MainActor
    @objc func rotation(_ gesture: NSRotationGestureRecognizer) {
        if let view = gesture.view  {
            switch gesture.state {
            case .possible:
                break
            case .began:
                handlers.rotation?.rotationBegan(at: GestureCoordinator.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                // multiply by -1 because macOS gestures use upside-down clip space
                handlers.rotation?.rotationChanged(radians: Float(-gesture.rotation))
            default:
                handlers.rotation?.rotationEnded()
            }
        }
    }

    // NO: I still have problems with simultaneous drag,pinch,rotate
    //
    //    /// Support for simultaneous gestures.
    //    public func gestureRecognizer(_ first: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith second: NSGestureRecognizer) -> Bool {
    //        // Disallow combos that include tap or long press.
    //        if first is NSClickGestureRecognizer || first is NSPressGestureRecognizer {
    //            return false
    //        }
    //
    //        // Disallow combos that include pinch. We only do this because of a bug in POV
    //        // controller: pinch interferes with drag and rotation step on each other.
    //        if first is NSMagnificationGestureRecognizer {
    //            return false
    //        }
    //
    //        // Allow everything else.
    //        return true
    //    }
}

#endif  // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

extension GestureCoordinator {

    public static func clipPoint(_ viewPt: CGPoint, _ viewBounds: CGRect) -> SIMD2<Float> {
        // FIXME: ASSUMES viewBounds origin is (0,0)
        return SIMD2<Float>(clipX(viewPt.x, viewBounds.width), clipY(viewPt.y, viewBounds.height))
    }

    public static func clipPoint(_ viewPt0: CGPoint, _ viewPt1: CGPoint, _ viewBounds: CGRect) -> SIMD2<Float> {
        // FIXME: ASSUMES viewBounds origin is (0,0)
        return SIMD2<Float>(clipX((viewPt0.x + viewPt1.x)/2, viewBounds.width),
                            clipY((viewPt0.y + viewPt1.y)/2, viewBounds.height))
    }

    private static func clipX(_ viewX: CGFloat, _ viewWidth: CGFloat) -> Float {
        return Float(2 * viewX / viewWidth - 1)
    }

#if os(iOS) // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    private static func clipY(_ viewY: CGFloat, _ viewHeight: CGFloat) -> Float {
        // In iOS, viewY increases toward the TOP of the screen
        return Float(1 - 2 * viewY / viewHeight)
    }

#elseif os(macOS) // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    private static func clipY(_ viewY: CGFloat, _ viewHeight: CGFloat) -> Float {
        // In macOS, viewY increaases toward the BOTTOM of the screen
        return Float(2 * viewY / viewHeight - 1)
    }

#endif  // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

}
