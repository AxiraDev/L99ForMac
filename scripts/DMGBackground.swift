// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import AppKit

// Installation instructions are drawn as layout, without manufacturer artwork.
let output=URL(fileURLWithPath:CommandLine.arguments[1])
let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1320,pixelsHigh:840,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
bitmap.size=NSSize(width:660,height:420)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
NSColor(calibratedWhite:0.97,alpha:1).setFill();NSRect(x:0,y:0,width:660,height:420).fill()
func text(_ value:String,y:CGFloat,size:CGFloat,bold:Bool=false,color:NSColor = .darkGray){
    let value=NSAttributedString(string:value,attributes:[.font:bold ? NSFont.boldSystemFont(ofSize:size):NSFont.systemFont(ofSize:size),.foregroundColor:color])
    value.draw(at:NSPoint(x:(660-value.size().width)/2,y:y))
}
text("L99 for Mac",y:345,size:32,bold:true,color:NSColor(calibratedWhite:0.12,alpha:1))
text("Drag the app to Applications",y:313,size:17)
text("Перетащи в Applications · 将应用拖入 Applications",y:289,size:12)
let blue=NSColor(calibratedRed:0.03,green:0.53,blue:0.77,alpha:1);blue.setStroke()
let arrow=NSBezierPath();arrow.lineWidth=5;arrow.lineCapStyle = .round;arrow.lineJoinStyle = .round
arrow.move(to:NSPoint(x:292,y:210));arrow.line(to:NSPoint(x:368,y:210))
arrow.move(to:NSPoint(x:350,y:228));arrow.line(to:NSPoint(x:368,y:210));arrow.line(to:NSPoint(x:350,y:192));arrow.stroke()
text("macOS 14+ · Apple Silicon · Audio visualization: 14.2+",y:80,size:12)
text("If macOS blocks the first launch: System Settings",y:50,size:11)
text("Privacy & Security → Open Anyway",y:33,size:11)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:output)
