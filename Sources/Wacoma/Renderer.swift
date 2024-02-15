//
//  Renderer.swift
//  
//
//  Created by Jim Hanson on 1/8/22.
//

import Foundation
import simd
import SwiftUI
import MetalKit

public enum RenderError: Error {
    case noDevice
    case noDefaultLibrary
    case noDepthStencilState
    case badVertexDescriptor
    case bufferCreationFailed
    case snapshotInProgress
}

public struct RenderConstants {

    public static let maxBuffersInFlight = 3
}

public struct RenderSettings {

    public var pov: POV

    public var viewMatrix: float4x4

    public var fadeoutMidpoint: Float

    public var fadeoutDistance: Float

    public var projectionMatrix: float4x4

    public var preferredFramesPerSecond: Int
}

public protocol Renderable {

    /// Called at the beginning of every rendering cycle.
    mutating func prepareToDraw(_ mtkView: MTKView, _ renderSettings: RenderSettings)

    /// Called on every rendering cycle. Should execute as quickly as possible.
    func encodeDrawCommands(_ encoder: MTLRenderCommandEncoder)
}

// ============================================================================
// MARK: - RenderController
// ============================================================================

public class RenderController: ObservableObject, DragHandler, PinchHandler, RotationHandler {

    public static let defaultDarkBackground = SIMD4<Double>(0.025, 0.025, 0.025, 1)

    public static let defaultLightBackground = SIMD4<Double>(0.975, 0.975, 0.975, 1)

    public var renderables = [Renderable]()

    public var povController: POVController

    public var fovController: FOVController

    /// The renderer view's bounds, in points
    public private(set) var viewBounds: CGRect = CGRect.zero // DUMMY VALUE

    /// distance in world coordinates between the POV's location and the plane on which a touch is located.
    /// If zero, then pinching and dragging do not work.
    /// Non-negative.
    public var touchPlaneDistance: Float = 1

    @Published public var backgroundColor: SIMD4<Double>

    @Published public private(set) var snapshotRequested: Bool = false

    private var snapshotCallback: ((String) -> Any?)? = nil

    public init(_ povController: POVController,
                _ fovController: FOVController,
                _ backgroundColor: SIMD4<Double> = RenderController.defaultDarkBackground) {
        self.povController = povController
        self.fovController = fovController
        self.backgroundColor = backgroundColor
    }

    public func update(_ viewBounds: CGRect) {
        self.viewBounds = viewBounds
        self.fovController.update(viewBounds)
    }

    public func requestSnapshot(_ callback: @escaping ((String) -> Any?)) throws {
        if snapshotRequested {
            throw RenderError.snapshotInProgress
        }
        snapshotRequested = true
        snapshotCallback = callback
    }

    public func snapshotTaken(_ response: String) {
        let callback = snapshotCallback
        snapshotRequested = false
        snapshotCallback = nil
        Task {
            if let callback {
                _ = callback(response)
            }
        }
    }

    /// location and size are both in clip-space coords
    public func touchRay(at location: SIMD2<Float>, size: SIMD2<Float>) -> TouchRay {
        let inverseProjectionMatrix = fovController.projectionMatrix.inverse
        let inverseViewMatrix = povController.viewMatrix.inverse

        var v1 = inverseProjectionMatrix * SIMD4<Float>(location.x, location.y, 0, 1)
        v1.z = -1
        v1.w = 0
        let ray1 = normalize(inverseViewMatrix * v1).xyz

        var v2 = inverseProjectionMatrix * SIMD4<Float>(location.x + size.x, location.y, 0, 1)
        v2.z = -1
        v2.w = 0
        let ray2 = normalize(inverseViewMatrix * v2).xyz

        var v3 = inverseProjectionMatrix * SIMD4<Float>(location.x, location.y + size.y, 0, 1)
        v3.z = -1
        v3.w = 0
        let ray3 = normalize(inverseViewMatrix * v3).xyz

        // Starting at ray origin, make a right triangle in space such that ray1 forms
        // one leg and the hypoteneuse lies along ray2. axis2is the other leg.
        let cross1 = (ray2 / simd_dot(ray1, ray2)) - ray1

        // Similar thing for ray3
        let cross2 = (ray3 / simd_dot(ray1, ray3)) - ray1

//        print("RenderController.touchRay")
//        print("                  ray1: \(ray1.prettyString)")
//        print("                  ray2: \(ray2.prettyString)")
//        print("                  ray3: \(ray3.prettyString)")
//        print("                  cross1: \(cross1)")
//        print("                  cross2: \(cross2)")
//        print("                  simd_dot(ray1, cross1): \(simd_dot(ray1, cross1))")
//        print("                  simd_dot(ray1, cross2): \(simd_dot(ray1, cross2))")
//        print("                  simd_dot(cross1, cross2): \(simd_dot(cross1, cross2))")

        return TouchRay(origin: povController.pov.location,
                        direction: ray1,
                        range: fovController.visibleZ,
                        cross1: cross1,
                        cross2: cross2)
    }

    /// location is in clip-space coords
    public func touchPoint(_ location: SIMD2<Float>) -> SIMD3<Float> {

        // I want to find the world coordinates of the point where the
        // touch ray intersects the touch plane
        //
        // touch plane is normal to pov.forward (which is given in world coordinates)
        // touchPlaneDistance is distance btw POV and touch plane, in world coordinates
        // touch ray's origin and direction are given in world coordinates

        let ray = touchRay(at: location, size: .zero)
        let distanceToPoint: Float = touchPlaneDistance / simd_dot(povController.pov.forward, ray.direction)
        let touchPoint = ray.origin + distanceToPoint * ray.direction

//        print("RenderController.touchPoint")
//        print("    pov.forward: \(povController.pov.forward.prettyString)")
//        print("    touchPlaneDistance: \(touchPlaneDistance)")
//        print("    ray.origin: \(ray.origin.prettyString)")
//        print("    ray.direction: \(ray.origin.prettyString)")
//        print("    fwd*ray: \(simd_dot(povController.pov.forward, ray.direction))")
//        print("    distanceToPoint: \(distanceToPoint)")
//        print("    touchPoint: \(touchPoint.prettyString)")

        return touchPoint
    }

    public func dragBegan(at location: SIMD2<Float>) {
        // print("RenderController.dragBegan")
        povController.dragGestureBegan(at: touchPoint(location))
    }

    public func dragChanged(panFraction: Float, scrollFraction: Float) {
        // print("RenderController.dragChanged")
        // Convert pan & scroll from fractions of the screen (-1...1)
        // to distances in view coordinates.
        let fovSize = fovController.fovSize(touchPlaneDistance)
        povController.dragGestureChanged(panDistance: panFraction * Float(fovSize.width),
                                         scrollDistance: scrollFraction * Float(fovSize.height))
    }

    public func dragEnded() {
        // print("RenderController.dragEnded")
        povController.dragGestureEnded()
    }

    public func pinchBegan(at location: SIMD2<Float>) {
        // print("RenderController.pinchBegan")
        // HACK HACK HACK HACK use center of screen, not touch location
        povController.pinchGestureBegan(at: touchPoint(.zero))
    }

    public func pinchChanged(scale: Float) {
        // print("RenderController.pinchChanged")
        povController.pinchGestureChanged(scale: scale)
    }

    public func pinchEnded() {
        // print("RenderController.pinchEnded")
        povController.pinchGestureEnded()
    }

    public func rotationBegan(at location: SIMD2<Float>) {
        // print("RenderController.rotationBegan")
        // HACK HACK HACK HACK use center of screen, not touch location
        povController.rotationGestureBegan(at: touchPoint(.zero))
    }

    public func rotationChanged(radians: Float) {
        // print("RenderController.rotationChanged")
        povController.rotationGestureChanged(radians: radians)
    }

    public func rotationEnded() {
        // print("RenderController.rotationEnded")
        povController.rotationGestureEnded()
    }

}

public struct TouchRay: Codable, Sendable {

    /// Ray's point of origin in world coordinates
    public var origin: SIMD3<Float>

    /// Unit vector giving ray's direction in world coordinates
    public var direction: SIMD3<Float>

    /// Start and end of the ray, given as distance along ray
    public var range: ClosedRange<Float>

    /// cross1 and cross2 are two vectors perpendicular to ray direction giving its rate of spreading.
    /// They give the semi-major and semi-minor axes of the ellipse that is the cross-section (we
    /// don't know which is which).
    public var cross1: SIMD3<Float>
    public var cross2: SIMD3<Float>

    public init(origin: SIMD3<Float>, direction: SIMD3<Float>, range: ClosedRange<Float>, cross1: SIMD3<Float>, cross2: SIMD3<Float>) {
        self.origin = origin
        self.direction = direction
        self.range = range
        self.cross1 = cross1
        self.cross2 = cross2
    }
}

extension RenderController {

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

// ============================================================================
// MARK: - Renderer
// ============================================================================


public class Renderer: NSObject, MTKViewDelegate {

    weak var controller: RenderController!

    var gestureCoordinator: GestureCoordinator

    let device: MTLDevice!

    let inFlightSemaphore = DispatchSemaphore(value: RenderConstants.maxBuffersInFlight)

    let commandQueue: MTLCommandQueue

    var depthState: MTLDepthStencilState

    public init(_ controller: RenderController, _ gestureHandlers: GestureHandlers) throws {
        self.controller = controller
        self.gestureCoordinator = GestureCoordinator(gestureHandlers)
        if let device = MTLCreateSystemDefaultDevice() {
            self.device = device
        }
        else {
            throw RenderError.noDevice
        }

        self.commandQueue = device.makeCommandQueue()!

        let depthStateDesciptor = MTLDepthStencilDescriptor()
        depthStateDesciptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDesciptor.isDepthWriteEnabled = true

        if let state = device.makeDepthStencilState(descriptor:depthStateDesciptor) {
            depthState = state
        }
        else {
            throw RenderError.noDepthStencilState
        }

        super.init()

    }

    public func connectGestures(_ mtkView: MTKView) {
        gestureCoordinator.connectGestures(mtkView)
    }

    public func disconnectGestures(_ mtkView: MTKView) {
        gestureCoordinator.disconnectGestures(mtkView)
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange newSize: CGSize) {

        // print("Renderer.mtkView. view.bounds: \(view.bounds), newSize: \(newSize)")

        // Docco for this method sez: "Updates the view’s contents upon receiving a change
        // in layout, resolution, or size." And: "Use this method to recompute any view or
        // projection matrices, or to regenerate any buffers to be compatible with the view’s
        // new size." However, we're going to do all that in draw() because the matrices
        // depend on user-settable properties that may change anytime, not just when something
        // happens to trigger this method.

        // newSize is in pixels, view.bounds is in points.
        controller.update(view.bounds)
    }

    public func draw(in view: MTKView) {

        // print("Renderer.draw")

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)

        // _drawCount += 1
        // let t0 = Date()

        // Swift compiler sez that the snapshot needs to be taken before the current drawable
        // is presented. This means it will capture the figure that was drawn the in PREVIOUS
        // call to this method.
        if controller.snapshotRequested {
            controller.snapshotTaken(saveSnapshot(view))
        }

        // Make sure all the renderables get exactly the same values
        let date = Date()
        controller.povController.update(date)
        controller.fovController.update(date)
        let renderSettings = RenderSettings(pov: controller.povController.pov,
                                            viewMatrix: controller.povController.viewMatrix,
                                            fadeoutMidpoint: controller.fovController.fadeoutMidpoint,
                                            fadeoutDistance: controller.fovController.fadeoutDistance,
                                            projectionMatrix: controller.fovController.projectionMatrix,
                                            preferredFramesPerSecond: view.preferredFramesPerSecond)

        for var renderable in controller.renderables {
            renderable.prepareToDraw(view, renderSettings)
        }

        if let commandBuffer = commandQueue.makeCommandBuffer() {

            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { (_ commandBuffer) -> Swift.Void in
                semaphore.signal()
            }

            // Delay getting the current Drawable and RenderPassDescriptor until we absolutely
            // them, in order to avoid holding onto the drawable and therby blocking the display
            // pipeline any longer than necessary
            if let drawable = view.currentDrawable,
               let renderPassDescriptor = view.currentRenderPassDescriptor,
               let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {

                // The figure's background is opaque and we doing single-pass rendering, so we don't
                // need to do anything for loadAction or storeAction.
                renderPassDescriptor.colorAttachments[0].loadAction = .dontCare
                renderPassDescriptor.colorAttachments[0].storeAction = .dontCare

                renderEncoder.setDepthStencilState(depthState)

                for renderable in controller.renderables {
                    renderable.encodeDrawCommands(renderEncoder)
                }
                renderEncoder.endEncoding()
                commandBuffer.present(drawable)
            }
            commandBuffer.commit()
        }
    }

    func saveSnapshot(_ view: MTKView) -> String {
        if let cgImage = view.takeSnapshot() {
            return cgImage.save()

            // Docco sez: "You are responsible for releasing this object by calling CGImageRelease"
            // but I get a compiler error: "'CGImageRelease' is unavailable: Core Foundation objects
            // are automatically memory managed"
            // CGImageRelease(cgImage)
        }
        else {
            return "Image capture failed"
        }
    }
}

// ============================================================================
// MARK: - RendererView
// ============================================================================

public struct RendererView {

    @ObservedObject var controller: RenderController

    var gestureHandlers: GestureHandlers?

    public init(_ controller: RenderController,
                _ gestureHandlers: GestureHandlers? = nil) {
        self.controller = controller
        self.gestureHandlers = gestureHandlers
    }

    public func makeCoordinator() -> Renderer {
        // Docco sez, "Implement this method if changes to your view might affect other
        // parts of your app. In your implementation, create a custom Swift instance that
        // can communicate with other parts of your interface. For example, you might
        // provide an instance that binds its variables to SwiftUI properties, causing
        // the two to remain synchronized."
        do {
            return try Renderer(controller, gestureHandlers ?? GestureHandlers())
        }
        catch {
            fatalError("Problem creating render coordinator: \(error)")
        }
    }

    public func makeMTKView(_ coordinator: Renderer) -> MTKView {
        // "Creates the view object and configures its initial state."

        // print("RendererView.makeMTKView")

        let mtkView = MTKView()

        // Pause to stop it from drawing while we're setting things up
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true

        mtkView.delegate = coordinator
        mtkView.device = coordinator.device
        mtkView.drawableSize = mtkView.frame.size
        mtkView.depthStencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
        mtkView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb

        mtkView.framebufferOnly = false // necessary for screenshots

        coordinator.connectGestures(mtkView)

        // Update and unpause
        doUpdate(mtkView, coordinator)
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false

        return mtkView
    }

    public func updateMTKView(_ mtkView: MTKView, _ coordinator: Renderer) {

        // Docco for this method sez, "Updates the state of the specified view with
        // new information from SwiftUI." This struct gets recreated many many times,
        // and I think the system calls makeMTKView the first time this is created
        // but it calls this method all the subsequent times.

        // EMPIRICAL: I'm seeing this method called once per handful of calls to draw()

        // print("RendererView.updateMTKView")
        doUpdate(mtkView, coordinator)
    }

    private func doUpdate(_ mtkView: MTKView, _ coordinator: Renderer) {

        // RenderController's backgroundColor MIGHT have changed
        mtkView.clearColor = MTLClearColorMake(coordinator.controller.backgroundColor.x,
                                               coordinator.controller.backgroundColor.y,
                                               coordinator.controller.backgroundColor.z,
                                               coordinator.controller.backgroundColor.w)

        // mtkView's bounds are measured in points while its drawableSize is measured in pixels.
        // They need not match, e.g., on my ipad, bounds: (0.0, 0.0, 1180.0, 820.0), drawableSize: (2360.0, 1640.0)
        // print("RendererView.doUpdate. view bounds: \(mtkView.bounds), drawableSize: \(mtkView.drawableSize)")
    }

    static public func dismantleMTKView(_ mtkView: MTKView, _ coordinator: Renderer) {
        coordinator.disconnectGestures(mtkView)
    }
}

#if os(iOS) // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

extension RendererView: UIViewRepresentable {

    public typealias UIViewType = MTKView
    public typealias Coordinator = Renderer

    public func makeUIView(context: Context) -> MTKView {
        let mtkView = makeMTKView(context.coordinator)
        mtkView.isMultipleTouchEnabled = true
        return mtkView
    }

    public func updateUIView(_ mtkView: MTKView, context: Context) {
        return updateMTKView(mtkView, context.coordinator)
    }

    static public func dismantleUIView(_ mtkView: MTKView, coordinator: Renderer) {
        dismantleMTKView(mtkView, coordinator)
    }
}

#elseif os(macOS) // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

extension RendererView: NSViewRepresentable {

    public typealias NSViewType = MTKView
    public typealias Coordinator = Renderer

    public func makeNSView(context: Context) -> MTKView {
        return makeMTKView(context.coordinator)
    }

    public func updateNSView(_ mtkView: MTKView, context: Context) {
        return updateMTKView(mtkView, context.coordinator)
    }

    static public func dismantleNSView(_ mtkView: MTKView, coordinator: Renderer) {
        dismantleMTKView(mtkView, coordinator)
    }
}

#endif // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

// ============================================================================
// MARK: - GestureCoordinator
// ============================================================================

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
                handlers.primaryTap?.tap(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
            default:
                break
            }
        }
    }

    @objc func secondaryTap(_ gesture: UITapGestureRecognizer) {
        if let view = gesture.view {
            switch gesture.state {
            case .ended:
                handlers.secondaryTap?.tap(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
            default:
                break
            }
        }
    }

    @objc func primaryLongPress(_ gesture: UILongPressGestureRecognizer) {
        if let view = gesture.view {
            switch gesture.state {
            case .began:
                handlers.primaryLongPress?.longPressBegan(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                handlers.primaryLongPress?.longPressMoved(to: RenderController.clipPoint(gesture.location(in: view), view.bounds))
            case .ended:
                handlers.primaryLongPress?.longPressEnded(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
            default:
                break
            }
        }
    }

    @objc func secondaryLongPress(_ gesture: UILongPressGestureRecognizer) {
        if let view = gesture.view {
            switch gesture.state {
            case .began:
                handlers.secondaryLongPress?.longPressBegan(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                handlers.secondaryLongPress?.longPressMoved(to: RenderController.clipPoint(gesture.location(in: view), view.bounds))
            case .ended:
                handlers.secondaryLongPress?.longPressEnded(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
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
                handlers.primaryDrag?.dragBegan(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
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
                handlers.secondaryDrag?.dragBegan(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
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
                handlers.pinch?.pinchBegan(at: RenderController.clipPoint(gesture.location(ofTouch: 0, in: view),
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
                handlers.rotation?.rotationBegan(at: RenderController.clipPoint(gesture.location(ofTouch: 0, in: view),
                                                                               gesture.location(ofTouch: 1, in: view),
                                                                               view.bounds))
            case .changed:
                handlers.rotation?.rotationChanged(radians: Float(gesture.rotation))
            default:
                handlers.rotation?.rotationEnded()
            }
        }
    }

//    /// Needed in order to do  simultaneous drag, pinch, rotation.
//    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith: UIGestureRecognizer) -> Bool {
//        print("GestureCoordinator.gestureRecognizer")
//        // Disallow combos that include tap.
//        if gestureRecognizer is UITapGestureRecognizer || shouldRecognizeSimultaneouslyWith is UITapGestureRecognizer {
//            return false
//        }
//
//        // Disallow combos that include long press.
//        if gestureRecognizer is UILongPressGestureRecognizer || shouldRecognizeSimultaneouslyWith is UILongPressGestureRecognizer {
//            return false
//        }
//
//        // Allow everything else.
//        return true
//    }

    /// Needed in order to do  simultaneous drag, pinch, rotation.
    public func gestureRecognizer(_ first: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith second: UIGestureRecognizer) -> Bool {
        // WAS: Disallow combos that include dragging, but allow anything else.

        // print("GestureCoordinator.gestureRecognizer. first is \(type(of: first)), second is \(type(of: second))")

        // Disallow combos that include tap or long press.
        if first is UITapGestureRecognizer || first is UILongPressGestureRecognizer {
            return false
        }

        // Allow everything else.
        return true
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
                handlers.primaryTap?.tap(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
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
                handlers.secondaryTap?.tap(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
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
                handlers.primaryLongPress?.longPressBegan(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                handlers.primaryLongPress?.longPressMoved(to: RenderController.clipPoint(gesture.location(in: view), view.bounds))
            case .ended:
                handlers.primaryLongPress?.longPressEnded(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
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
                handlers.secondaryLongPress?.longPressBegan(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                handlers.secondaryLongPress?.longPressMoved(to: RenderController.clipPoint(gesture.location(in: view), view.bounds))
            case .ended:
                handlers.secondaryLongPress?.longPressEnded(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
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
                handlers.primaryDrag?.dragBegan(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
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
                handlers.secondaryDrag?.dragBegan(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
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
                handlers.pinch?.pinchBegan(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
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
                handlers.rotation?.rotationBegan(at: RenderController.clipPoint(gesture.location(in: view), view.bounds))
            case .changed:
                // multiply by -1 because macOS gestures use upside-down clip space
                handlers.rotation?.rotationChanged(radians: Float(-gesture.rotation))
            default:
                handlers.rotation?.rotationEnded()
            }
        }
    }

    /// needed in order to do simultaneous gestures
    public func gestureRecognizer(_ first: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith second: NSGestureRecognizer) -> Bool {
        // WAS: Disallow combos that include dragging, but allow anything else.

        // print("GestureCoordinator.gestureRecognizer. first is \(type(of: first)), second is \(type(of: second))")

        // Disallow combos that include tap or long press.
        if first is NSClickGestureRecognizer || first is NSPressGestureRecognizer {
            return false
        }

        // Allow everything else.
        return true

    }
}

#endif  // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
