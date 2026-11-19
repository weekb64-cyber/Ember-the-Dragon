import Foundation
import CoreGraphics

/// A single curved silhouette, rendered as a transparent overlay rather than joint geometry.
func guideOpenHandImage() -> CGImage? {
    let size = 640
    guard let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,
        space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.scaleBy(x:CGFloat(size)/512,y:CGFloat(size)/512)
    let p = CGMutablePath()
    p.move(to:CGPoint(x:188,y:45))
    p.addCurve(to:CGPoint(x:171,y:134),control1:CGPoint(x:186,y:86),control2:CGPoint(x:187,y:110))
    p.addCurve(to:CGPoint(x:99,y:250),control1:CGPoint(x:145,y:167),control2:CGPoint(x:113,y:211))
    p.addCurve(to:CGPoint(x:124,y:276),control1:CGPoint(x:87,y:276),control2:CGPoint(x:103,y:291))
    p.addCurve(to:CGPoint(x:177,y:226),control1:CGPoint(x:143,y:263),control2:CGPoint(x:154,y:244))
    p.addCurve(to:CGPoint(x:184,y:242),control1:CGPoint(x:181,y:225),control2:CGPoint(x:185,y:232))
    p.addLine(to:CGPoint(x:168,y:400))
    p.addCurve(to:CGPoint(x:204,y:404),control1:CGPoint(x:165,y:429),control2:CGPoint(x:201,y:434))
    p.addLine(to:CGPoint(x:219,y:292))
    p.addCurve(to:CGPoint(x:229,y:293),control1:CGPoint(x:220,y:285),control2:CGPoint(x:228,y:286))
    p.addLine(to:CGPoint(x:230,y:447))
    p.addCurve(to:CGPoint(x:267,y:448),control1:CGPoint(x:230,y:477),control2:CGPoint(x:267,y:479))
    p.addLine(to:CGPoint(x:268,y:297))
    p.addCurve(to:CGPoint(x:278,y:296),control1:CGPoint(x:268,y:288),control2:CGPoint(x:277,y:288))
    p.addLine(to:CGPoint(x:293,y:422))
    p.addCurve(to:CGPoint(x:328,y:417),control1:CGPoint(x:296,y:449),control2:CGPoint(x:331,y:447))
    p.addLine(to:CGPoint(x:315,y:284))
    p.addCurve(to:CGPoint(x:325,y:281),control1:CGPoint(x:314,y:274),control2:CGPoint(x:321,y:272))
    p.addLine(to:CGPoint(x:346,y:358))
    p.addCurve(to:CGPoint(x:379,y:349),control1:CGPoint(x:355,y:384),control2:CGPoint(x:387,y:376))
    p.addLine(to:CGPoint(x:354,y:233))
    p.addCurve(to:CGPoint(x:328,y:142),control1:CGPoint(x:351,y:202),control2:CGPoint(x:345,y:169))
    p.addCurve(to:CGPoint(x:313,y:45),control1:CGPoint(x:314,y:112),control2:CGPoint(x:315,y:83))
    p.closeSubpath()
    context.saveGState()
    context.addPath(p); context.clip()
    let colors = [CGColor(red:0.74,green:0.76,blue:0.78,alpha:0.5),CGColor(red:0.92,green:0.93,blue:0.94,alpha:0.95)] as CFArray
    let gradient = CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:colors,locations:[0,1])!
    context.drawLinearGradient(gradient,start:CGPoint(x:160,y:60),end:CGPoint(x:290,y:450),options:[.drawsBeforeStartLocation,.drawsAfterEndLocation])
    context.restoreGState()
    context.addPath(p)
    context.setLineWidth(3);context.setLineJoin(.round)
    context.setStrokeColor(CGColor(red:0.96,green:0.97,blue:0.98,alpha:0.98));context.strokePath()
    context.setStrokeColor(CGColor(red:0.35,green:0.38,blue:0.40,alpha:0.28));context.setLineWidth(2)
    context.move(to:CGPoint(x:193,y:203));context.addCurve(to:CGPoint(x:312,y:224),control1:CGPoint(x:230,y:234),control2:CGPoint(x:270,y:244));context.strokePath()
    context.move(to:CGPoint(x:209,y:159));context.addCurve(to:CGPoint(x:292,y:169),control1:CGPoint(x:237,y:178),control2:CGPoint(x:265,y:181));context.strokePath()
    return context.makeImage()
}
