//
//  POV.swift
//  Wacoma
//
//  Created by Jim Hanson on 1/8/22.
//

import Foundation
import simd

enum POVError: Error {
    case notUnitVector(_ name: String, length: Float)
    case notOrthogonal(_ name1: String, _ name2: String, dotProduct: Float)
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

/// POV whose forward vector always points toward a fixed point in world coordinates.
public struct CenteredPOV: POV, Codable, Sendable, Hashable, Equatable, CustomStringConvertible   {

    public var description: String {
        "{ location: \(location.prettyString), center: \(center.prettyString), up: \(trueUp.prettyString) }"
    }

    public var radius: Float {
        simd_distance(location, center)
    }

    public var forward: SIMD3<Float> {
        normalize(center - location)
    }

    public var up: SIMD3<Float> {
        get { trueUp }
        set { trueUp = normalize(newValue - dot(forward, newValue) * forward) }
    }

    public var location: SIMD3<Float>

    public var center: SIMD3<Float>

    private var trueUp: SIMD3<Float>

    /// location is any point
    /// center can be any point not equal to location
    /// up can be any nonzero vector not parallel to the displacement between center and location
    public init(location: SIMD3<Float> = SIMD3<Float>(0, 0, -1),
                center: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
                up: SIMD3<Float> = SIMD3<Float>(0,1,0)) {
        self.location = location
        self.center = center
        let delta = center - location
        self.trueUp =  normalize(up - (simd_dot(delta, up) / simd_dot(delta, delta)) * delta)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(location: try container.decode(SIMD3<Float>.self, forKey: .location),
                  center: try container.decode(SIMD3<Float>.self, forKey: .center),
                  up: try container.decode(SIMD3<Float>.self, forKey: .up))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(location, forKey: .location)
        try container.encode(center, forKey: .center)
        try container.encode(trueUp, forKey: .up)
    }

    private enum CodingKeys: String, CodingKey {
        case location
        case center
        case up
    }

}

/// POV whose forward vector is directly settable.
public struct FlyingPOV: POV, Codable, Hashable, Equatable, CustomStringConvertible {

    public var description: String {
        "{ location: \(location.prettyString), forward: \(trueForward.prettyString), up: \(trueUp.prettyString) }"
    }

    public var location: SIMD3<Float>

    public var forward: SIMD3<Float> {
        get { trueForward }
        set { trueForward = normalize(newValue) }
    }

    private var trueForward: SIMD3<Float>

    public var up: SIMD3<Float> {
        get { trueUp }
        set { trueUp = normalize(newValue - dot(trueForward, newValue) * trueForward) }
    }

    private var trueUp: SIMD3<Float>

    /// location: any point
    /// forwardHint: any  nonzero vector
    /// upHint: any nonzero vector not parallel to forward
    public init(location: SIMD3<Float> = SIMD3<Float>(0, 0, -1),
                forward: SIMD3<Float> =  SIMD3<Float>(0, 0, 1),
                up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)) {
        self.init(location: location,
                  trueForward: normalize(forward),
                  trueUp: normalize(up - (dot(forward, up) / dot(forward, forward)) * forward))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(location: try container.decode(SIMD3<Float>.self, forKey: .location),
                  forward: try container.decode(SIMD3<Float>.self, forKey: .forward),
                  up: try container.decode(SIMD3<Float>.self, forKey: .up))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(location, forKey: .location)
        try container.encode(trueForward, forKey: .forward)
        try container.encode(trueUp, forKey: .up)
    }

    /// location: any point
    /// trueForward: unit vector
    /// trueUp: unit vector orthogonal to trueForward
    internal init(location: SIMD3<Float>, trueForward: SIMD3<Float>, trueUp: SIMD3<Float>) {
        do {
            try Self.validate(location: location, forward: trueForward, up: trueUp)
            self.location = location
            self.trueForward = trueForward
            self.trueUp = trueUp
        }
        catch {
            // print("Problem with POV -- \(error)")
            self.location = SIMD3<Float>(0, 0, -1)
            self.trueForward = SIMD3<Float>(0, 0, 1)
            self.trueUp = SIMD3<Float>(0, 1, 0)
        }
    }

    static func validate(location: SIMD3<Float>, forward: SIMD3<Float>, up: SIMD3<Float>) throws {
        if length(forward).differentFrom(1) {
            throw POVError.notUnitVector("forward", length: length(forward))
        }
        if length(up).differentFrom(1) {
            throw POVError.notUnitVector("up", length: length(up))
        }
        if dot(forward, up).differentFrom(0) {
            throw POVError.notOrthogonal("forward", "up", dotProduct: dot(forward, up))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case forward
        case location
        case up
    }


}

public struct POVControllerSettings {

    public var scrollSensitivity: Float

    public var panSensitivity: Float

    public var rotationSensitivity: Float

    public var flyCoastingThreshold: Double

    public var flyNormalizedAcceleration: Double

    public var flyMinSpeed: Double

    public var flyMaxSpeed: Double

#if os(iOS) // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    public init() {
        self.scrollSensitivity = 2.5
        self.panSensitivity = 2.5
        self.rotationSensitivity = 1.25
        self.flyCoastingThreshold = 0.33
        self.flyNormalizedAcceleration = 4 // WAS: 5.5
        self.flyMinSpeed  = 0.01
        self.flyMaxSpeed = 5 // WAS: 9
    }
#elseif os(macOS) // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    public init() {
        self.scrollSensitivity = 2.5
        self.panSensitivity = 2.5
        self.rotationSensitivity = 1.25
        self.flyCoastingThreshold = 0.33
        self.flyNormalizedAcceleration = 4 // WAS: 5.5
        self.flyMinSpeed  = 0.01
        self.flyMaxSpeed = 5 // WAS: 9
    }
#endif // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

}

public protocol POVController {

    var settings: POVControllerSettings { get set }

    var pov: POV { get }

    var viewMatrix: float4x4 { get }

    func reset()
    
    /// Sets the POV's properties to the values they should have at the given system time.
    /// This is called during each rendering cycle as a way to support a POV that changes on its own
    func update(_ timestamp: Date)

    func dragGestureBegan(at: SIMD3<Float>)

    func dragGestureChanged(panDistance: Float, scrollDistance: Float)

    func dragGestureEnded()

    func pinchGestureBegan(at: SIMD3<Float>)

    func pinchGestureChanged(scale: Float)

    func pinchGestureEnded()

    func rotationGestureBegan(at: SIMD3<Float>)

    func rotationGestureChanged(radians: Float)

    func rotationGestureEnded()

}

extension POVController {

    public var viewMatrix: float4x4 {

        // Adapted from:
        // https://stackoverflow.com/questions/9053377/ios-questions-about-camera-information-within-glkmatrix4makelookat-result
        // https://gist.github.com/CaptainRedmuff/5673450

        let pov = self.pov
        let n = -pov.forward
        let u = normalize(simd_cross(pov.up, n))
        let v = simd_cross(n, u)

        return float4x4(columns: (SIMD4<Float>(u.x, v.x, n.x,  0),
                                  SIMD4<Float>(u.y, v.y, n.y,  0),
                                  SIMD4<Float>(u.z, v.z, n.z,  0),
                                  SIMD4<Float>(simd_dot(-u, pov.location), simd_dot(-v, pov.location), simd_dot(-n, pov.location),  1)))
    }
}

public class OrbitingPOVController: ObservableObject, POVController {

    static let defaultFlightTime: TimeInterval = 1

    @Published public var orbitPermitted: Bool {
        didSet {
            if orbitPermitted == false {
                orbitEnabled = false
            }
        }
    }

    @Published public var orbitEnabled: Bool

    /// angular rotation rate in radians per second
    @Published public var orbitSpeed: Float

    public var pov: POV { currentPOV }

    /// Not published because it changes too frequently
    public private(set) var currentPOV = CenteredPOV()

    public var defaultPOV = CenteredPOV()

    public var markedPOV: CenteredPOV? = nil

    public var markIsSet: Bool {
        return markedPOV != nil
    }

    public var isFlightInProgress: Bool {
        return flightInProgress != nil
    }

    public var settings = POVControllerSettings()

    private var _lastUpdateTimestamp: Date? = nil

    private var flightInProgress: CenteredPOVFlight? = nil

    private var dragInProgress: CenteredPOVTangentialMove? = nil

    private var pinchInProgress: CenteredPOVRadialMove? = nil

    private var rotationInProgress: CenteredPOVRoll? = nil

    private var queuedFlights: [CenteredPOVFlight.Spec]

    public init(pov: CenteredPOV = CenteredPOV(),
                orbitPermitted: Bool = true,
                orbitEnabled: Bool = true,
                orbitSpeed: Float = 1/8) {
        self.currentPOV = pov
        self.defaultPOV = pov
        self.orbitPermitted = orbitPermitted
        self.orbitEnabled = orbitEnabled && orbitPermitted
        self.orbitSpeed = orbitSpeed
        self.queuedFlights = [CenteredPOVFlight.Spec]()
    }

    public func reset() {
        self.currentPOV = defaultPOV
        self.orbitPermitted = true
        self.orbitEnabled = true
        self.orbitSpeed = 1/8
        self.queuedFlights.removeAll()
        self.flightInProgress = nil
        self.dragInProgress = nil
        self.pinchInProgress = nil
        self.rotationInProgress = nil
        self._lastUpdateTimestamp = nil
    }

    public func markPOV() {
        markedPOV = currentPOV
    }

    public func unsetMark() {
        markedPOV = nil
    }

    public func jump(to pov: CenteredPOV) {
        queuedFlights.append(CenteredPOVFlight.Spec(pov: pov, flightTime: 0))
    }

    public func fly(to pov: CenteredPOV, flightTime: TimeInterval? = nil) {
        let trueFlightTime = flightTime ?? Self.defaultFlightTime
        queuedFlights.append(CenteredPOVFlight.Spec(pov: pov, flightTime: trueFlightTime))
    }

    public func centerOn(_ newCenter: SIMD3<Float>) {
        fly(to: CenteredPOV(location: currentPOV.location, center: newCenter, up: currentPOV.up))
    }

    public func hoverOver(_ point: SIMD3<Float>, _ distance: Float = 5) {
        self.orbitEnabled = false
        var displacementRTP = cartesianToSpherical(xyz: point - currentPOV.center)
        displacementRTP.x += distance
        let destination = sphericalToCartesian(rtp: displacementRTP)
        fly(to: CenteredPOV(location: destination, center: currentPOV.center, up: currentPOV.up))
    }

    public func dragGestureBegan(at touchPoint: SIMD3<Float>) {
        if isFlightInProgress {
            // print("OrbitingPOVController.dragGestureBegan: aborting because flight is in progress")
            return
        }

        // print("OrbitingPOVController.dragGestureBegan: beginning drag")
        self.dragInProgress = CenteredPOVTangentialMove(self.currentPOV, touchPoint, settings)
    }

    public func dragGestureChanged(panDistance pan: Float, scrollDistance scroll: Float) {
        if let handler = self.dragInProgress {
            // NO GOOD:
            // let viewDelta = SIMD4<Float>(pan, scroll, 0, 1)
            // if let newPOV = handler.touchLocationChanged(delta: (viewMatrix.inverse * viewDelta).xyz) {

            // ORIG
            if let newPOV = handler.locationChanged(panDistance: pan, scrollDistance: scroll) {
                self.currentPOV = newPOV
            }
        }
    }

    /// DON'T COUNT ON THIS. Sometimes it's not delivered
    public func dragGestureEnded() {
        // print("OrbitingPOVController.dragGestureEnded")
        self.dragInProgress = nil
    }


    public func pinchGestureBegan(at pinchCenter: SIMD3<Float>) {
        if isFlightInProgress {
            // print("OrbitingPOVController.pinchGestureBegan: aborting because flight is in progress")
            return
        }
        // print("OrbitingPOVController.pinchGestureBegan: starting pinch")
        self.pinchInProgress = CenteredPOVRadialMove(self.currentPOV, pinchCenter, settings)
    }

    public func pinchGestureChanged(scale: Float) {
        if let handler = self.pinchInProgress {
            if let newPOV = handler.scaleChanged(scale: scale) {
                self.currentPOV = newPOV
            }
        }
    }

    /// DON'T COUNT ON THIS. Sometimes it's not delivered
    public func pinchGestureEnded() {
        // print("OrbitingPOVController.pinchGestureEnded")
        pinchInProgress = nil
    }

    public func rotationGestureBegan(at rotationCenter: SIMD3<Float>) {
        if isFlightInProgress {
            // print("OrbitingPOVController.rotationGestureBegan: aborting because flight is in progress")
            return
        }
        // print("OrbitingPOVController.rotationGestureBegan: beginning rotation")
        self.rotationInProgress = CenteredPOVRoll(self.currentPOV, rotationCenter, settings)
    }

    public func rotationGestureChanged(radians: Float) {
        if let handler = self.rotationInProgress {
            if let newPOV = handler.rotationChanged(radians: radians) {
                self.currentPOV = newPOV
            }
        }
    }

    /// DON'T COUNT ON THIS. Sometimes it's not delivered
    public func rotationGestureEnded() {
        // print("OrbitingPOVController.rotationGestureEnded")
        self.rotationInProgress = nil
    }

    public func update(_ timestamp: Date) {
        self.currentPOV = makeUpdatedPOV(timestamp)
        self._lastUpdateTimestamp = timestamp

        // print("OrbitingPOVController.update: Exiting. new POV: \(currentPOV)")
    }

    private func makeUpdatedPOV(_ timestamp: Date) -> CenteredPOV {

        // ==================================================================
        // Q: orbital motion even if we're flying?
        // A: Yes, if it looks OK
        //
        // Q: how about if we're handling a gesture?
        // A: Problem there is that we don't always get notified whenn a gesture
        //    ends. So we can't disallow update during a gesture.
        //
        // If orbit speed is > 0 then it looks like we're flying east over
        // the figure.
        // ==================================================================

        if flightInProgress == nil && !queuedFlights.isEmpty {
            let spec = queuedFlights.removeFirst()
            flightInProgress = CenteredPOVFlight(from: self.currentPOV,
                                                 to: spec.pov,
                                                 flightTime: spec.flightTime)
        }

        var updatedPOV: CenteredPOV
        if let pov = flightInProgress?.update(timestamp) {
            updatedPOV = pov
        }
        else {
            flightInProgress = nil
            updatedPOV = currentPOV
        }

        if orbitEnabled, let t0 = _lastUpdateTimestamp {
            let transform = float4x4(translationBy: updatedPOV.center)
            * float4x4(rotationAround: updatedPOV.up, by: orbitSpeed * Float(timestamp.timeIntervalSince(t0)))
            * float4x4(translationBy: -updatedPOV.center)
            let newLocation = (transform * SIMD4<Float>(updatedPOV.location, 1)).xyz

            updatedPOV = CenteredPOV(location: newLocation,
                               center: updatedPOV.center,
                               up: updatedPOV.up)
        }

        return updatedPOV
    }
}

// ===========================================================
// MARK: - POV Actions
// ===========================================================

///
///
///
class CenteredPOVFlight {

    struct Spec {
        var pov: CenteredPOV
        var flightTime: TimeInterval
    }

    enum Phase: Double {
        case new
        case accelerating
        case coasting
        case decelerating
        case arrived
    }


    // Chosen because default frame rate is 60/sec
    static let minFlightTime: TimeInterval = 1/60

    static let coastingFraction: Double = 0.33

    /// Normalized units
    static let minSpeed: Double = 1/60

    let initialPOV: CenteredPOV

    let finalPOV: CenteredPOV

    let isJump: Bool

    /// Normalized units
    let acceleration: Double

    /// fractional distance at which we stop accelerating
    /// Normalized units
    let accelerationEnd: Double

    /// fractional distance at which we start decelerating
    /// Normalized units
    let decelerationStart: Double

    private var phase: Phase = .new

    private(set) var lastUpdateTime: Date = .distantPast

    /// Normalized units
    private(set) var speed: Double = 0

    /// fraction of the total distance that has been covered so far
    /// Normalized units
    private(set) var distance: Double = 0


    public init(from initialPOV: CenteredPOV,
                to finalPOV: CenteredPOV,
                 flightTime: TimeInterval)
    {
        self.initialPOV = initialPOV
        self.finalPOV = finalPOV

        if flightTime <= Self.minFlightTime {
            self.isJump = true
            self.acceleration = 0
            self.accelerationEnd = 0
            self.decelerationStart = 1
        }
        else {

            // ======================================================
            // tA: time spent accelerating
            // tC: time spent coasting
            // tD: time spent decenerating
            // dA: fractional distance traveled while accelerating
            // dC: fractional distance traveled while coasting
            // dD: fractional distance traveled while decelerating
            // a:  acceleration rate
            // v1: maximum velocity
            //
            // tA + tC + tD = flightTime
            // dA + dC + dD = 1
            //
            // tC = coastingFraction * flightTime
            // tA = tD = (flightTime - tC)/2
            //
            // v1 = a * tA
            //
            // dA = a * (tA * tA / 2)
            // dC = v1 * tC = a * (tA * tC)
            // dD = v1 * tD - (a * tD * tD / 2) = a * (tA * tD - tD * tD / 2)
            //
            // 1 = dA + dC + dD
            //
            // 1 = a * [ (tA * tA / 2) + (tA * tC) + (tA * tD) - (tD * tD / 2) ]
            //
            // a = 1 / [ (tA * tA / 2) + (tA * tC) + (tA * tD) - (tD * tD / 2) ]
            // ======================================================

            let tC: TimeInterval = Self.coastingFraction * flightTime
            let tA: TimeInterval = (flightTime - tC) / 2
            let tD: TimeInterval = flightTime - tA - tC // do this way b/c of roundoff.
            let invA: Double = (tA * tA / 2.0) + (tA * tC) + (tA * tD) - (tD * tD / 2.0)

            let a = 1.0 / invA
            let dA = a * tA * tA / 2
            let dC = a * tA * tC

            self.isJump = false
            self.acceleration = a
            self.accelerationEnd = dA
            self.decelerationStart = dA + dC
        }
    }

    /// returns nil when the flight finished
    func update(_ timestamp: Date) -> CenteredPOV? {

        // debug("POVFlightAction.update", "phase = \(phase)")

        let dt = timestamp.timeIntervalSince(lastUpdateTime)
        lastUpdateTime = timestamp

        switch phase {
        case .new:
            beginFlight()
            return newPOV()
        case .accelerating:
            continueAcceleration(dt)
            return newPOV()
        case .coasting:
            continueCoasting(dt)
            return newPOV()
        case .decelerating:
            continueDeceleration(dt)
            return newPOV()
        case .arrived:
            return nil
        }
    }

    private func beginFlight() {
        if isJump {
            distance = 1
            phase = .arrived
        }
        else {
            distance = 0
            speed = 0
            phase = .accelerating
        }
    }

    private func continueAcceleration(_ dt: Double) {
        distance += speed * dt
        if distance >= accelerationEnd {
            phase = .coasting
        }
        else {
            speed += acceleration * dt
        }
    }

    private func continueCoasting(_ dt: Double) {
        distance += speed * dt
        if distance >= decelerationStart {
            phase = .decelerating
        }
    }

    private func continueDeceleration(_ dt: Double) {
        distance += speed * dt
        if distance >= 1  {
            distance = 1
            phase = .arrived
        }
        else {
            speed -= acceleration * dt
            if speed < Self.minSpeed {
                speed = Self.minSpeed
            }
        }
    }

    private func newPOV() -> CenteredPOV {
        let newLocation = Float(distance) * (finalPOV.location - initialPOV.location) + initialPOV.location
        let newCenter   = Float(distance) * (finalPOV.center - initialPOV.center) + initialPOV.center
        let newUp       = Float(distance) * (finalPOV.up - initialPOV.up) + initialPOV.up
        return CenteredPOV(location: newLocation,
                           center: newCenter,
                           up: newUp)
    }
}

///
/// PAN is a rotation of the POV's location about an axis that is
/// parallel to the POV's up axis and that passes through the POV's
/// center point
///
/// SCROLL is a rotation of the location and up vectors.
/// --location rotates about an axis that is perpendicular to both
///   forward and up axes and that passes through the center point
/// --up vector rotates about the same axis
///
struct CenteredPOVTangentialMove {

    let initialPOV: CenteredPOV

    let initialTouch: SIMD3<Float>

    let touchToCenterDistance: Float

    let initialTheta: Float

    let initialPhi: Float

    /// unit vector perpendicular to initial POV's forward and up vectors
    let scrollRotationAxis: SIMD3<Float>

    let panRotationAxis: SIMD3<Float>

    let scrollFactor: Float

    let panFactor: Float

    init(_ pov: CenteredPOV, _ touchPoint: SIMD3<Float>, _ settings: POVControllerSettings) {

        self.initialPOV = pov
        self.initialTouch = touchPoint
        self.scrollRotationAxis = normalize(simd_cross(initialPOV.forward, initialPOV.up))
        self.panRotationAxis = initialPOV.up

        let d = simd_dot((touchPoint - pov.center), -pov.forward)
        self.touchToCenterDistance = (d == 0) ? 1 : d

        let initialDisplacementRTP = cartesianToSpherical(xyz: touchPoint - pov.center)
        self.initialTheta = initialDisplacementRTP.y
        self.initialPhi = initialDisplacementRTP.z
        // print("initialTheta: \(initialTheta), initialPhi: \(initialPhi)")

        self.scrollFactor = settings.scrollSensitivity
        self.panFactor = settings.panSensitivity
    }

    // ALT.
    // Didn't work when I tried it.
    // But I tried it before touchPoint calculation was fixed.
    //    func touchLocationChanged(delta: SIMD3<Float>) -> CenteredPOV? {
    //
    //
    //        let newTouch = initialTouch + delta
    //        let newDisplacementRTP = cartesianToSpherical(xyz: (newTouch - initialPOV.center))
    //        let dTheta = newDisplacementRTP.y - initialTheta
    //        let dPhi = newDisplacementRTP.z - initialPhi
    //
    //        // print("dTheta: \(dTheta), dPhi: \(dPhi)")
    //
    //        let newLocation = (
    //            float4x4(translationBy: initialPOV.center)
    //            * float4x4(rotationAround: panRotationAxis, by: dPhi)
    //            * float4x4(rotationAround: scrollRotationAxis, by: dTheta)
    //            * float4x4(translationBy: -initialPOV.center)
    //            * SIMD4<Float>(initialPOV.location, 1)
    //        ).xyz
    //
    //        let newUp = (
    //            float4x4(rotationAround: scrollRotationAxis, by: dTheta)
    //            * SIMD4<Float>(initialPOV.up, 1)
    //        ).xyz
    //
    //        return CenteredPOV(location: newLocation,
    //                           center: initialPOV.center,
    //                           up: newUp)
    //
    //    }

    func locationChanged(panDistance: Float, scrollDistance: Float) -> CenteredPOV? {

        let dTheta = scrollFactor * atan(scrollDistance/touchToCenterDistance)
        let dPhi = -panFactor * atan(panDistance/touchToCenterDistance)
        // print("dTheta: \(dTheta), dPhi: \(dPhi)")

        let newLocation = (
            float4x4(translationBy: initialPOV.center)
            * float4x4(rotationAround: panRotationAxis, by: dPhi)
            * float4x4(rotationAround: scrollRotationAxis, by: dTheta)
            * float4x4(translationBy: -initialPOV.center)
            * SIMD4<Float>(initialPOV.location, 1)
        ).xyz

        let newUp = (
            float4x4(rotationAround: scrollRotationAxis, by: dTheta)
            * SIMD4<Float>(initialPOV.up, 1)
        ).xyz

        return CenteredPOV(location: newLocation,
                           center: initialPOV.center,
                           up: newUp)
    }
}

///
/// This is a translation of POV's location toward or away from a given center that it's pointed toward
///
struct CenteredPOVRadialMove {

    let initialPOV: CenteredPOV

    let pinchRadius: Float

    /// displacement from POV center to POV location, in spherical world coordinates
    let initialRTP: SIMD3<Float>

    init(_ pov: CenteredPOV, _ pinchCenter: SIMD3<Float>, _ settings: POVControllerSettings) {
        self.initialPOV = pov
        self.pinchRadius = cartesianToSpherical(xyz: (pinchCenter-pov.center)).x
        self.initialRTP = cartesianToSpherical(xyz: (pov.location-pov.center))
        // print("pinchRadius: \(pinchRadius), initialRadius: \(initialRTP.x)")
    }

    func scaleChanged(scale: Float) -> CenteredPOV? {
        let newRadius = ((initialRTP.x - pinchRadius) / scale) + pinchRadius
        let newLocation = initialPOV.center + sphericalToCartesian(rtp: SIMD3<Float>(newRadius,
                                                                                     initialRTP.y,
                                                                                     initialRTP.z))
        // print("    scale: \(scale), newRadius: \(newRadius)")
        return CenteredPOV(location: newLocation,
                           center: initialPOV.center,
                           up: initialPOV.up)
    }
}



typealias CenteredPOVRoll = CenteredPOVRoll2

///
/// This is a rotation of the POV's up vector about its forward vector
///
struct CenteredPOVRoll1 {

    let initialPOV: CenteredPOV
    let rotationCenter: SIMD3<Float>
    let rotationSensitivity: Float

    init(_ pov: CenteredPOV, _ rotationCenter: SIMD3<Float>, _ settings: POVControllerSettings) {
        self.initialPOV = pov
        self.rotationCenter = rotationCenter
        self.rotationSensitivity = settings.rotationSensitivity
    }

    func rotationChanged(radians: Float) -> CenteredPOV? {
        let newUp = (
            float4x4(rotationAround: initialPOV.forward, by: Float(-rotationSensitivity * radians))
            * SIMD4<Float>(initialPOV.up, 1)).xyz
        return CenteredPOV(location: initialPOV.location,
                           center: initialPOV.center,
                           up: newUp)
    }
}

struct CenteredPOVRoll2 {

    let initialPOV: CenteredPOV
    let rotationCenter: SIMD3<Float>
    let rotationSensitivity: Float

    init(_ pov: CenteredPOV, _ rotationCenter: SIMD3<Float>, _ settings: POVControllerSettings) {
        self.initialPOV = pov
        self.rotationCenter = rotationCenter
        self.rotationSensitivity = settings.rotationSensitivity
    }

    func rotationChanged(radians: Float) -> CenteredPOV? {

        // First try:
        // Rotate pov.location and .up around the rotation axis
        // - Gets it right if the center of rotation is the center of the screen
        // - If center of rotation is not center of the screen, it does something but not what I expected

        let rotationAxis = initialPOV.center - rotationCenter

        let transform = float4x4(rotationAround: rotationAxis, by: radians)

        // Second try:
        // 1. transform the view coords until rotationAxis vector intersects the glass at the center
        // of the screen.
        // - That's a rotation around some derived axis (not rotationAxis) by some
        //   amount (not radians). Maybe I can calculate the matrix in the initer.
        // - in view coords, initialPOV.location is in the spot where I want to transform the rotationAxis vector to.
        //   therfore the displacement vector between rotationCenter and pov.location is the key.
        //
        // 2. rotate view coords by radians
        //
        // 3. do reverse of step 1
        // I can calculate the matrix in the initer.
        //
        // To do step 1:
        // v1 = displacement vector from pov location to pov center
        // v2 = displacement vector from touch location to pov center
        // a = axis of rotation = cross product of v1 and v2
        // theta = angle to rotate. Found by solving for theta in dot(v1, v2) = |v1| * |v2| * cos(theta
        //
        // - Not much different from the first try!
        //
        //        let v1 = initialPOV.center - initialPOV.location
        //        let m1 = simd_length(v1)
        //        let v2 = initialPOV.center - rotationCenter
        //        let m2 = simd_length(v2)
        //        let rotationAxis = simd_cross(v1, v2)
        //        let cosTheta = simd_dot(v1, v2) / (m1 * m2)
        //        let theta = acos(cosTheta)
        //        let zAxis = SIMD3<Float>(0, 0, -1)
        //        let transform = float4x4(rotationAround: rotationAxis, by: theta)
        //        * float4x4(rotationAround: zAxis, by: radians)
        //        * float4x4(rotationAround: rotationAxis, by: -theta)

        return CenteredPOV(location: (transform * SIMD4<Float>(initialPOV.location, 1)).xyz,
                           center: initialPOV.center,
                           up: (transform * SIMD4<Float>(initialPOV.up, 1)).xyz)
    }
}
