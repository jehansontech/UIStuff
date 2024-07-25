//
//  Renderer.swift
//  Wacoma
//
//  Created by Jim Hanson on 1/8/22.
//

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

// ============================================================================
// MARK: - RendererDelegate
// ============================================================================

public protocol RendererDelegate {

    var projectionMatrix: float4x4 { get }

    var viewMatrix: float4x4 { get }

    var snapshotRequested: Bool { get }

    var pov: POV { get }

    var visibleZ: ClosedRange<Float> { get }

    var backgroundColor: SIMD4<Double> { get }

    func requestSnapshot(_ callback: @escaping ((String) -> Any?)) throws

    func snapshotTaken(_ response: String)

    func update(_ viewBounds: CGRect)

    func prepareToDraw(_ view: MTKView)

    func encodeDrawCommands(_ encoder: MTLRenderCommandEncoder)

}

extension RendererDelegate {

    /// Point in world coordinates corresponding to the given point on the glass
    /// location is in clip-space coords
    public func touchPointOnGlass(at clipSpacePoint: SIMD2<Float>) -> SIMD3<Float> {

        // TODO: verify correctness

        let inverseProjectionMatrix = self.projectionMatrix.inverse
        let inverseViewMatrix = self.viewMatrix.inverse

        var viewSpacePoint = inverseProjectionMatrix * SIMD4<Float>(clipSpacePoint.x, clipSpacePoint.y, 0, 1)
        // print("touchPointOnGlass: clipSpace: \(clipSpacePoint.prettyString) viewSpace: \(viewSpacePoint.prettyString)")
        // viewSpacePoint.z = 0
        viewSpacePoint.w = 0
        let worldSpacePoint = (inverseViewMatrix * viewSpacePoint).xyz
        // print("touchPointOnGlass: clipSpace: \(clipSpacePoint.prettyString) worldSpace: \(worldSpacePoint.prettyString)")
        return worldSpacePoint
    }

    public func touchPointAtDepth(at clipSpacePoint: SIMD2<Float>, depth: Float) -> SIMD3<Float> {

        // I want to find the world coordinates of the point where the center of the
        // touch ray intersects a given plane normal to the POV's forward vector
        // (the "touch plane").
        //
        // touch plane is normal to pov.forward (which is given in world coordinates)
        // depth is distance btw POV and touch plane, in world coordinates
        // touch ray's origin and direction are given in world coordinates

        let ray = touchRay(at: clipSpacePoint, size: .zero)
        let distanceToPoint: Float = depth / simd_dot(pov.forward, ray.direction)
        let touchPoint = ray.origin + distanceToPoint * ray.direction

        //        print("touchPoint")
        //        print("    pov.forward: \(povController.pov.forward.prettyString)")
        //        print("    touchPlaneDistance: \(touchPlaneDistance)")
        //        print("    ray.origin: \(ray.origin.prettyString)")
        //        print("    ray.direction: \(ray.origin.prettyString)")
        //        print("    fwd*ray: \(simd_dot(povController.pov.forward, ray.direction))")
        //        print("    distanceToPoint: \(distanceToPoint)")
        //        print("    touchPoint: \(touchPoint.prettyString)")

        return touchPoint

    }

    /// Returns a TouchRay whose origin is in the center of the screen and whose direction is derived from the given location.
    /// location and size are both in clip-space coords
    public func touchRay(at clipSpacePoint: SIMD2<Float>, size: SIMD2<Float>) -> TouchRay {
        let inverseProjectionMatrix = self.projectionMatrix.inverse
        let inverseViewMatrix = self.viewMatrix.inverse

        var v1 = inverseProjectionMatrix * SIMD4<Float>(clipSpacePoint.x, clipSpacePoint.y, 0, 1)
        v1.z = -1
        v1.w = 0
        let ray1 = normalize(inverseViewMatrix * v1).xyz

        var v2 = inverseProjectionMatrix * SIMD4<Float>(clipSpacePoint.x + size.x, clipSpacePoint.y, 0, 1)
        v2.z = -1
        v2.w = 0
        let ray2 = normalize(inverseViewMatrix * v2).xyz

        var v3 = inverseProjectionMatrix * SIMD4<Float>(clipSpacePoint.x, clipSpacePoint.y + size.y, 0, 1)
        v3.z = -1
        v3.w = 0
        let ray3 = normalize(inverseViewMatrix * v3).xyz

        // Starting at ray origin, make a right triangle in space such that ray1 forms
        // one leg and the hypoteneuse lies along ray2. cross1 is the other leg.
        let cross1 = (ray2 / simd_dot(ray1, ray2)) - ray1

        // Similar thing for ray3
        let cross2 = (ray3 / simd_dot(ray1, ray3)) - ray1

        //        print("              touchRay")
        //        print("                  ray1: \(ray1.prettyString)")
        //        print("                  ray2: \(ray2.prettyString)")
        //        print("                  ray3: \(ray3.prettyString)")
        //        print("                  cross1: \(cross1)")
        //        print("                  cross2: \(cross2)")
        //        print("                  simd_dot(ray1, cross1): \(simd_dot(ray1, cross1))")
        //        print("                  simd_dot(ray1, cross2): \(simd_dot(ray1, cross2))")
        //        print("                  simd_dot(cross1, cross2): \(simd_dot(cross1, cross2))")

        return TouchRay(origin: self.pov.location,
                        direction: ray1,
                        range: self.visibleZ,
                        cross1: cross1,
                        cross2: cross2)
    }

}

/// Point of View
public protocol POV {

    /// the POV's location in world coordinates
    var location: SIMD3<Float> { get }

    /// Unit vector giving the direction the POV is pointed
    var forward: SIMD3<Float> { get }

    /// Unit vector giving the POV's "up" direction. Orthogonal to forward.
    var up: SIMD3<Float> { get }
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

// ============================================================================
// MARK: - Renderer
// ============================================================================


public class Renderer: NSObject, MTKViewDelegate {

    public var delegate: RendererDelegate?

    var gestureCoordinator: GestureCoordinator

    public let device: MTLDevice!

    let inFlightSemaphore = DispatchSemaphore(value: RenderConstants.maxBuffersInFlight)

    let commandQueue: MTLCommandQueue

    var depthState: MTLDepthStencilState

    public init(_ delegate: RendererDelegate, _ gestureHandlers: GestureHandlers) throws {
        self.delegate = delegate
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
        delegate?.update(view.bounds)
    }

    public func draw(in view: MTKView) {

        if delegate == nil {
            return
        }

        // print("Renderer.draw")

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)

        // _drawCount += 1
        // let t0 = Date()

        // Swift compiler sez that the snapshot needs to be taken before the current drawable
        // is presented. This means it will capture the figure that was drawn the in PREVIOUS
        // call to this method.

        if delegate!.snapshotRequested {
            delegate!.snapshotTaken(saveSnapshot(view))
        }

        delegate!.prepareToDraw(view)

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
                delegate!.encodeDrawCommands(renderEncoder)
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
