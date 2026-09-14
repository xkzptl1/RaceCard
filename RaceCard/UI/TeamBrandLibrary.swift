import SwiftUI
import RaceCardDataKit

@MainActor @Observable final class TeamBrandLibrary {
    static let shared=TeamBrandLibrary()
    var root:URL?
    var registry=TeamRegistry()
    private var images:[String:NSImage]=[:]
    func configure(root:URL,registry:TeamRegistry) {self.root=root;self.registry=registry;images=[:]}
    func image(season:Int,team:String)->NSImage? {
        guard let root,let metadata=registry.resolve(team),metadata.logoSeason==season,let path=metadata.logoPath,let file=AssetRegistry(root:root).file(path) else{return nil}
        let key=file.path
        if let cached=images[key] {return cached}
        guard let image=NSImage(contentsOf:file) else{return nil}
        let normalized=Self.opticallyNormalized(image)
        images[key]=normalized;return normalized
    }
    /// Crop transparent source canvas for every team; retain the original aspect ratio.
    static func opticallyNormalized(_ image:NSImage)->NSImage {
        guard let data=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data),let source=bitmap.cgImage else{return image}
        let w=source.width,h=source.height
        var pixels=[UInt8](repeating:0,count:w*h*4)
        guard let context=CGContext(data:&pixels,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else{return image}
        context.draw(source,in:CGRect(x:0,y:0,width:w,height:h))
        var x0=w,y0=h,x1=0,y1=0
        var monochrome=true
        for y in 0..<h {for x in 0..<w where pixels[(y*w+x)*4+3]>16 {x0=min(x0,x);x1=max(x1,x);y0=min(y0,y);y1=max(y1,y);let i=(y*w+x)*4;let rgb=[pixels[i],pixels[i+1],pixels[i+2]];if Int(rgb.max()!)-Int(rgb.min()!)>20 {monochrome=false}}}
        guard x1>=x0,y1>=y0,let cropped=context.makeImage()?.cropping(to:CGRect(x:x0,y:y0,width:x1-x0+1,height:y1-y0+1)) else{return image}
        let result=NSImage(cgImage:cropped,size:CGSize(width:cropped.width,height:cropped.height))
        result.isTemplate=monochrome
        return result
    }
}
