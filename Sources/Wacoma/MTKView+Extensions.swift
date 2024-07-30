//
//  MTKView+Extensions.swift
//  Wacoma
//
//  Created by Jim Hanson on 1/8/22.

import MetalKit

extension MTKView {

    public func takeSnapshot() -> CGImage? {
        guard
            let texture = self.currentDrawable?.texture
        else {
            return nil
        }

        let width = texture.width
        let height   = texture.height
        let rowBytes = texture.width * 4
        let p = malloc(width * height * 4)
        texture.getBytes(p!, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)

        let pColorSpace = CGColorSpaceCreateDeviceRGB()

        let rawBitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let bitmapInfo: CGBitmapInfo = CGBitmapInfo(rawValue: rawBitmapInfo)

        let dataSize = texture.width * texture.height * 4
        let releaseMaskImagePixelData: CGDataProviderReleaseDataCallback = { (info: UnsafeMutableRawPointer?, data: UnsafeRawPointer, size: Int) -> () in
            return
        }
        let provider = CGDataProvider(dataInfo: nil, data: p!, size: dataSize, releaseData: releaseMaskImagePixelData)
        return CGImage(width: texture.width,
                       height: texture.height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 32,
                       bytesPerRow: rowBytes,
                       space: pColorSpace,
                       bitmapInfo: bitmapInfo,
                       provider: provider!,
                       decode: nil,
                       shouldInterpolate: true,
                       intent: CGColorRenderingIntent.defaultIntent)
    }
}
