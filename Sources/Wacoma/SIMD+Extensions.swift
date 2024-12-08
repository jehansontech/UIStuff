//
//  SIMD+Extensions.swift
//  Wacoma
//
//  Created by Jim Hanson on 10/17/20.
//

import Foundation
import simd

fileprivate let scalarFormatter = makeScalarFormatter()

fileprivate func makeScalarFormatter() -> Formatter {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.usesSignificantDigits = true
    formatter.minimumSignificantDigits = 1
    formatter.maximumSignificantDigits = 3
    return formatter
}

fileprivate func format<S>(_ x: S) -> String where S: SIMDScalar {
    return scalarFormatter.string(for: x) ?? "\(x)"
}

public func cartesianToSpherical(xyz: SIMD3<Float>) -> SIMD3<Float> {
    var r = sqrt( xyz.x * xyz.x + xyz.y * xyz.y + xyz.z * xyz.z)
    if (r < .epsilon) {
        r = .epsilon
    }
    let theta =  acos(xyz.z/r)
    var phi = atan2(xyz.y, xyz.x)
    if (phi < 0) {
        phi += .twoPi
    }
    return SIMD3<Float>(r, theta, phi)
}

public func cartesianToSpherical(xyz: SIMD3<Double>) -> SIMD3<Double> {
    var r = sqrt( xyz.x * xyz.x + xyz.y * xyz.y + xyz.z * xyz.z)
    if (r < .epsilon) {
        r = .epsilon
    }
    let theta =  acos(xyz.z/r)
    var phi = atan2(xyz.y, xyz.x)
    if (phi < 0) {
        phi += .twoPi
    }
    return SIMD3<Double>(r, theta, phi)
}

public func sphericalToCartesian(rtp: SIMD3<Float>) -> SIMD3<Float> {
    let x = rtp.x * sin(rtp.y) * cos(rtp.z)
    let y = rtp.x * sin(rtp.y) * sin(rtp.z)
    let z = rtp.x * cos(rtp.y)
    return SIMD3<Float>(x, y, z)
}

public func sphericalToCartesian(rtp: SIMD3<Double>) -> SIMD3<Double> {
    let x = rtp.x * sin(rtp.y) * cos(rtp.z)
    let y = rtp.x * sin(rtp.y) * sin(rtp.z)
    let z = rtp.x * cos(rtp.y)
    return SIMD3<Double>(x, y, z)
}

extension SIMD2 {

    public var prettyString: String {
        "(\(format(self.x)), \(format(self.y)))"
    }

    public func differentFrom(_ v: Self) -> Bool where Self.Scalar == Float {
        return x.differentFrom(v.x) || y.differentFrom(v.y)
    }

    public func differentFrom(_ v: Self) -> Bool where Self.Scalar == Double {
        return x.differentFrom(v.x) || y.differentFrom(v.y)
    }
}

extension SIMD3 {

    public var xy: SIMD2<Scalar> {
        return SIMD2<Scalar>(self.x, self.y)
    }

    public var prettyString: String {
        "(\(format(self.x)), \(format(self.y)), \(format(self.z)))"
    }

    public func differentFrom(_ v: Self) -> Bool where Self.Scalar == Float {
        return x.differentFrom(v.x) || y.differentFrom(v.y) || z.differentFrom(v.z)
    }

    public func differentFrom(_ v: Self) -> Bool where Self.Scalar == Double {
        return x.differentFrom(v.x) || y.differentFrom(v.y) || z.differentFrom(v.z)
    }
}

extension SIMD4 {

    public var xy: SIMD2<Scalar> {
        return SIMD2<Scalar>(self.x, self.y)
    }

    public var xyz: SIMD3<Scalar> {
        return SIMD3<Scalar>(self.x, self.y, self.z)
    }

    public var prettyString: String {
        "(\(format(self.x)), \(format(self.y)), \(format(self.z)), \(format(self.w)))"
    }

    public func differentFrom(_ v: Self) -> Bool where Self.Scalar == Float {
        return x.differentFrom(v.x) || y.differentFrom(v.y) || z.differentFrom(v.z) || w.differentFrom(v.w)
    }

    public func differentFrom(_ v: Self) -> Bool where Self.Scalar == Double {
        return x.differentFrom(v.x) || y.differentFrom(v.y) || z.differentFrom(v.z) || w.differentFrom(v.w)
    }

}

extension simd_float3x3 {

    public init(rotateFrom v1: SIMD3<Float>, to v2: SIMD3<Float>) {
        let axis = cross(v1, v2)
        let cosA = dot(v1, v2)
        let k: Float = 1 / (1 + cosA)

        let a = (axis.x * axis.x * k) + cosA
        let b = (axis.y * axis.x * k) - axis.z
        let c = (axis.z * axis.x * k) + axis.y

        let d = (axis.x * axis.y * k) + axis.z
        let e = (axis.y * axis.y * k) + cosA
        let f = (axis.z * axis.y * k) - axis.x

        let g = (axis.x * axis.z * k) - axis.y
        let h = (axis.y * axis.z * k) + axis.x
        let i = (axis.z * axis.z * k) + cosA

        self.init(columns: (SIMD3<Float>(a,b,c),
                            SIMD3<Float>(d,e,f),
                            SIMD3<Float>(g,h,i)))
    }

}

extension simd_float4x4 {

    /// angle in radians
    public init(rotationAround axis: SIMD3<Float>, by angle: Float) {

        // from MetalPicking

        let unitAxis = normalize(axis)
        let ct = cosf(angle)
        let st = sinf(angle)
        let ci = 1 - ct
        let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
        self.init(columns:(SIMD4<Float>(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
                           SIMD4<Float>(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
                           SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
                           SIMD4<Float>(                  0,                   0,                   0, 1)))
    }

    public init(translationBy v: SIMD3<Float>) {

        // from MetalPicking

        self.init(columns:(SIMD4<Float>(  1,   0,   0,   0),
                           SIMD4<Float>(  0,   1,   0,   0),
                           SIMD4<Float>(  0,   0,   1,   0),
                           SIMD4<Float>(v.x, v.y, v.z,   1)))
    }

    public init(perspectiveProjectionRHFovY fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) {

        // from MetalPicking

        let ys = 1 / tanf(fovy * 0.5)
        let xs = ys / aspectRatio
        let zs = farZ / (nearZ - farZ)
        self.init(columns:(SIMD4<Float>(xs,  0,  0,          0),
                           SIMD4<Float>( 0, ys,  0,          0),
                           SIMD4<Float>( 0,  0, zs,         -1),
                           SIMD4<Float>( 0,  0, zs * nearZ,  0)))
    }

    public init(lookAt center: SIMD3<Float>, eye: SIMD3<Float>, up: SIMD3<Float>) {

        // https://stackoverflow.com/questions/9053377/ios-questions-about-camera-information-within-glkmatrix4makelookat-result
        // https://gist.github.com/CaptainRedmuff/5673450
        //
        // GLKVector3 ev = { eyeX, eyeY, eyeZ };
        // GLKVector3 cv = { centerX, centerY, centerZ };
        // GLKVector3 uv = { upX, upY, upZ };
        //
        // GLKVector3 n = GLKVector3Normalize(GLKVector3Add(ev, GLKVector3Negate(cv)));
        // GLKVector3 u = GLKVector3Normalize(GLKVector3CrossProduct(uv, n));
        // GLKVector3 v = GLKVector3CrossProduct(n, u);
        //
        // GLKMatrix4 m = { u.v[0], v.v[0], n.v[0], 0.0f,
        //                  u.v[1], v.v[1], n.v[1], 0.0f,
        //                  u.v[2], v.v[2], n.v[2], 0.0f,
        //                  GLKVector3DotProduct(GLKVector3Negate(u), ev),
        //                  GLKVector3DotProduct(GLKVector3Negate(v), ev),
        //                  GLKVector3DotProduct(GLKVector3Negate(n), ev),
        //                  1.0f };

        let n = normalize(eye - center)
        let u = normalize(simd_cross(up, n))
        let v = simd_cross(n, u)

        // If GLKMatrix4 constructor takes its args as a list of column vectors:
        self.init(columns: (SIMD4<Float>(              u.x,               v.x,               n.x,  0),
                            SIMD4<Float>(              u.y,               v.y,               n.y,  0),
                            SIMD4<Float>(              u.z,               v.z,               n.z,  0),
                            SIMD4<Float>(simd_dot(-u, eye), simd_dot(-v, eye), simd_dot(-n, eye),  1)))

        // If GLKMatrix4 constructor takes its args in a list of row vectors:
        //        self.init(columns: (SIMD4<Float>(u.x, u.y, u.z, simd_dot(-u, eye)),
        //                            SIMD4<Float>(v.x, v.y, v.z, simd_dot(-v, eye)),
        //                            SIMD4<Float>(n.x, n.y, n.z, simd_dot(-n, eye)),
        //                            SIMD4<Float>(0,   0,   0,   1)))

    }
}


