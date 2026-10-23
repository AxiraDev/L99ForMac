// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import AppKit
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum ScreenFit: String, CaseIterable, Identifiable, Codable {
    case fit="Вписать",fill="Заполнить",stretch="Растянуть"
    var id: Self {self}
}

struct EncodedScreen {
    let data: Data
    let frames: Int
    let preview: CGImage
}

enum ScreenEncoder {
    static func render(_ image: CGImage, fit: ScreenFit, rotation: Int) throws -> (Data, CGImage) {
        var bytes=[UInt8](repeating:0,count:320*480*4)
        return try bytes.withUnsafeMutableBytes { buffer in
            guard let ctx=CGContext(data:buffer.baseAddress,width:320,height:480,bitsPerComponent:8,bytesPerRow:1280,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {throw L99Error.message(T("Не удалось создать изображение экрана."))}
            ctx.setFillColor(CGColor(red:0,green:0,blue:0,alpha:1));ctx.fill(CGRect(x:0,y:0,width:320,height:480))
            ctx.interpolationQuality = .high
            let rotated=rotation%180 != 0
            let iw=Double(rotated ? image.height:image.width),ih=Double(rotated ? image.width:image.height)
            let factor=fit == .fill ? max(320/iw,480/ih):min(320/iw,480/ih)
            let w=fit == .stretch ? 320:iw*factor,h=fit == .stretch ? 480:ih*factor
            ctx.translateBy(x:160,y:240)
            ctx.rotate(by:Double(rotation)*Double.pi/180)
            let target=rotated ? CGRect(x:-h/2,y:-w/2,width:h,height:w):CGRect(x:-w/2,y:-h/2,width:w,height:h)
            ctx.draw(image,in:target)
            guard let preview=ctx.makeImage() else {throw L99Error.message(T("Не удалось подготовить предпросмотр."))}
            return (Data(buffer),preview)
        }
    }

    /// ImageIO supplies a photographic palette after scaling or rotating a frame.
    static func paletteImage(_ image:CGImage) throws -> CGImage {
        let buffer=NSMutableData()
        guard let gif=CGImageDestinationCreateWithData(buffer,UTType.gif.identifier as CFString,1,nil) else{throw L99Error.message(T("Не удалось подготовить палитру GIF."))}
        CGImageDestinationAddImage(gif,image,nil)
        guard CGImageDestinationFinalize(gif),let source=CGImageSourceCreateWithData(buffer,nil),let result=CGImageSourceCreateImageAtIndex(source,0,nil) else{throw L99Error.message(T("Не удалось преобразовать палитру GIF."))}
        return result
    }
    static func encode(url: URL, fit: ScreenFit, rotation: Int, animation: Bool = false, cancellation:TransferCancellation?=nil, progress: (Double)->Void = {_ in}) throws -> EncodedScreen {
        try cancellation?.check()
        guard let source=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary) else {throw L99Error.message(T("Файл изображения недоступен."))}
        let count=CGImageSourceGetCount(source)
        guard (1...200).contains(count), animation || count==1 else {throw L99Error.message(T("Для Photo Frame и фона выбери статичную картинку. В этом файле: \(count)."))}
        var rgba=Data();rgba.reserveCapacity(count*320*480*4)
        var delays:[UInt16]=[]
        var preview: CGImage?
        for i in 0..<count {
            try cancellation?.check()
            let options:[CFString:Any]=[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1024,kCGImageSourceShouldCacheImmediately:true]
            guard let image=CGImageSourceCreateThumbnailAtIndex(source,i,options as CFDictionary) else {throw L99Error.message(T("Не удалось прочитать кадр \(i+1)."))}
            let (raw,rendered)=try render(image,fit:fit,rotation:rotation)
            let pixels:Data
            if animation {let quantized=try paletteImage(rendered);pixels=try render(quantized,fit:.stretch,rotation:0).0}else{pixels=raw}
            if preview==nil {preview=rendered}
            rgba.append(pixels)
            let props=CGImageSourceCopyPropertiesAtIndex(source,i,nil) as? [CFString:Any]
            let gif=props?[kCGImagePropertyGIFDictionary] as? [CFString:Any]
            let seconds=(gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.1
            delays.append(UInt16(min(500,max(30,(seconds*1000).rounded()))))
            progress(Double(i+1)/Double(count))
        }
        try cancellation?.check()
        // Capacity is a bound: LT palettes and run lengths make frames variable-size.
        let logical=(animation ? 548*count:11)+count*320*480*2
        var output=[UInt8](repeating:255,count:logical)
        let length=output.count
        let written=rgba.withUnsafeBytes {pixels in delays.withUnsafeBufferPointer {times in output.withUnsafeMutableBufferPointer {out in
            l99_encode_screen(pixels.bindMemory(to:UInt8.self).baseAddress!,rgba.count,times.baseAddress!,count,animation ? 1:0,out.baseAddress!,length)
        }}}
        guard written>0,written<=length,let preview else {throw L99Error.message(T("Ошибка преобразования изображения в формат L99."))}
        try cancellation?.check()
        return EncodedScreen(data:Data(output.prefix(Int(written))),frames:count,preview:preview)
    }
}
