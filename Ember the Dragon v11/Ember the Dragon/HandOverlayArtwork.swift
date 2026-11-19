import Foundation
import CoreGraphics

/// A single curved silhouette, rendered as a transparent overlay rather than joint geometry.
func guideHandImage() -> CGImage? {
    let size = 640
    guard let context = CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,
        space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    context.scaleBy(x:CGFloat(size)/512,y:CGFloat(size)/512)
    let p = CGMutablePath()
    // Thumb and index meet at a rounded pinch; remaining fingers curl into the palm.
    p.move(to:CGPoint(x:185,y:48))
    p.addCurve(to:CGPoint(x:170,y:168),control1:CGPoint(x:187,y:98),control2:CGPoint(x:180,y:137))
    p.addCurve(to:CGPoint(x:144,y:260),control1:CGPoint(x:150,y:198),control2:CGPoint(x:135,y:225))
    p.addCurve(to:CGPoint(x:166,y:300),control1:CGPoint(x:145,y:288),control2:CGPoint(x:156,y:302))
    p.addCurve(to:CGPoint(x:213,y:328),control1:CGPoint(x:177,y:303),control2:CGPoint(x:191,y:321))
    p.addCurve(to:CGPoint(x:254,y:358),control1:CGPoint(x:226,y:344),control2:CGPoint(x:238,y:366))
    p.addCurve(to:CGPoint(x:273,y:332),control1:CGPoint(x:275,y:357),control2:CGPoint(x:284,y:341))
    p.addCurve(to:CGPoint(x:226,y:298),control1:CGPoint(x:259,y:316),control2:CGPoint(x:244,y:306))
    p.addCurve(to:CGPoint(x:216,y:271),control1:CGPoint(x:214,y:289),control2:CGPoint(x:209,y:280))
    p.addCurve(to:CGPoint(x:242,y:278),control1:CGPoint(x:220,y:264),control2:CGPoint(x:234,y:273))
    p.addCurve(to:CGPoint(x:271,y:329),control1:CGPoint(x:270,y:287),control2:CGPoint(x:274,y:311))
    p.addCurve(to:CGPoint(x:301,y:337),control1:CGPoint(x:273,y:349),control2:CGPoint(x:298,y:355))
    p.addCurve(to:CGPoint(x:298,y:274),control1:CGPoint(x:307,y:320),control2:CGPoint(x:307,y:295))
    p.addCurve(to:CGPoint(x:327,y:265),control1:CGPoint(x:309,y:292),control2:CGPoint(x:332,y:287))
    p.addCurve(to:CGPoint(x:350,y:247),control1:CGPoint(x:341,y:280),control2:CGPoint(x:360,y:271))
    p.addCurve(to:CGPoint(x:358,y:215),control1:CGPoint(x:368,y:255),control2:CGPoint(x:375,y:228))
    p.addCurve(to:CGPoint(x:324,y:157),control1:CGPoint(x:350,y:188),control2:CGPoint(x:335,y:171))
    p.addCurve(to:CGPoint(x:313,y:48),control1:CGPoint(x:310,y:127),control2:CGPoint(x:313,y:83))
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

/// Rounded knuckles, folded fingers and an overlaid thumb in the same translucent grey as the pinch guide.
func guideFistImage() -> CGImage? {
    guard let c = CGContext(data:nil,width:640,height:640,bitsPerComponent:8,bytesPerRow:2560,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    c.scaleBy(x:1.25,y:1.25)
    let p = CGMutablePath()
    p.move(to:CGPoint(x:185,y:48));p.addLine(to:CGPoint(x:180,y:165))
    p.addCurve(to:CGPoint(x:138,y:240),control1:CGPoint(x:150,y:185),control2:CGPoint(x:132,y:211))
    p.addLine(to:CGPoint(x:140,y:318))
    p.addCurve(to:CGPoint(x:190,y:341),control1:CGPoint(x:137,y:358),control2:CGPoint(x:177,y:366))
    p.addCurve(to:CGPoint(x:244,y:357),control1:CGPoint(x:195,y:390),control2:CGPoint(x:239,y:391))
    p.addCurve(to:CGPoint(x:297,y:350),control1:CGPoint(x:252,y:389),control2:CGPoint(x:293,y:384))
    p.addCurve(to:CGPoint(x:344,y:326),control1:CGPoint(x:309,y:376),control2:CGPoint(x:350,y:365))
    p.addLine(to:CGPoint(x:354,y:246))
    p.addCurve(to:CGPoint(x:319,y:170),control1:CGPoint(x:360,y:215),control2:CGPoint(x:343,y:188))
    p.addLine(to:CGPoint(x:314,y:48));p.closeSubpath()
    c.saveGState();c.addPath(p);c.clip()
    let colors = [CGColor(red:0.74,green:0.76,blue:0.78,alpha:0.50),CGColor(red:0.92,green:0.93,blue:0.94,alpha:0.95)] as CFArray
    if let g = CGGradient(colorsSpace:CGColorSpace(name:CGColorSpace.sRGB),colors:colors,locations:[0,1]) { c.drawLinearGradient(g,start:CGPoint(x:170,y:50),end:CGPoint(x:300,y:400),options:[]) }
    c.restoreGState();c.addPath(p);c.setStrokeColor(CGColor(red:0.96,green:0.97,blue:0.98,alpha:0.98));c.setLineWidth(3);c.strokePath()
    c.setStrokeColor(CGColor(red:0.35,green:0.38,blue:0.40,alpha:0.42));c.setLineWidth(2.5);c.setLineCap(.round)
    for x: CGFloat in [190,244,297] { c.move(to:CGPoint(x:x,y:345));c.addQuadCurve(to:CGPoint(x:x+2,y:281),control:CGPoint(x:x-7,y:310));c.strokePath() }
    c.move(to:CGPoint(x:153,y:255));c.addCurve(to:CGPoint(x:302,y:278),control1:CGPoint(x:195,y:230),control2:CGPoint(x:267,y:247));c.addCurve(to:CGPoint(x:302,y:242),control1:CGPoint(x:332,y:289),control2:CGPoint(x:341,y:254));c.addCurve(to:CGPoint(x:219,y:212),control1:CGPoint(x:276,y:239),control2:CGPoint(x:250,y:222));c.strokePath()
    return c.makeImage()
}
