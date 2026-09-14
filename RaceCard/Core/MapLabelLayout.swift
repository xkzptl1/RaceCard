import Foundation
import RaceCardDataKit

/// Layout only. Anchors are immutable factual positions; collisions move or omit text, never geometry.
enum MapLabelLayout {
    static func place(anchor:CGPoint,size:CGSize,bounds:CGSize,occupied:inout [CGRect],technical:Bool)->CGRect? {
        let direction=atan2(anchor.y-bounds.height/2,anchor.x-bounds.width/2)
        let radii:[CGFloat]=technical ? [16,24,34,44]:[0,15,28,40,52]
        for radius in radii {
            for turn in [0.0,0.5,-0.5,1.0,-1.0,1.6,-1.6,2.4,-2.4,Double.pi] {
                let point=CGPoint(x:anchor.x+cos(direction+turn)*radius,y:anchor.y+sin(direction+turn)*radius)
                let rect=CGRect(x:point.x-size.width/2,y:point.y-size.height/2,width:size.width,height:size.height)
                if rect.minX>=1 && rect.maxX<bounds.width-1 && rect.minY>=1 && rect.maxY<bounds.height-1 && !occupied.contains(where:{$0.insetBy(dx:-2,dy:-2).intersects(rect)}) {occupied.append(rect);return rect}
            }
        }
        return nil
    }
}

struct MapAnnotationAnchor:Equatable {
    let id:String
    let canonicalCoordinate:TrackPoint
}
/// One transform shared by stroke, anchors, cars, labels and hover targets.
/// Orientation depends only on source geometry; viewport changes scale and centering only.
struct MapProjection {
    let center:CGPoint;let scale:CGFloat;let size:CGSize;let angle:CGFloat
    init(points:[TrackPoint],size:CGSize) {
        let xs=points.map(\.x),ys=points.map(\.y)
        let dx=(xs.max() ?? 1)-(xs.min() ?? 0),dy=(ys.max() ?? 1)-(ys.min() ?? 0)
        let base:CGFloat=dy>dx ? -.pi/2:0
        // Choose one readable landscape orientation against a fixed reference viewport.
        // Opening driver detail or resizing must never rotate the circuit.
        let radians:[CGFloat] = [-90,-60,-45,-30,0,30,45,60,90].map { $0 * CGFloat.pi / 180 }
        let candidates:[CGFloat] = [base]+radians
        let referenceSize=CGSize(width:900,height:300)
        func fit(_ angle:CGFloat,_ viewport:CGSize)->(CGFloat,CGPoint) {
            let c=cos(angle),s=sin(angle)
            var x0=CGFloat.infinity,x1 = -CGFloat.infinity,y0=CGFloat.infinity,y1 = -CGFloat.infinity
            for p in points {
                let px=CGFloat(p.x),py=CGFloat(p.y)
                let x=c*px-s*py
                let y=s*px+c*py
                x0=min(x0,x);x1=max(x1,x);y0=min(y0,y);y1=max(y1,y)
            }
            guard !points.isEmpty else{return (1,.zero)}
            return (min(max(1,viewport.width-64)/max(0.01,x1-x0),max(1,viewport.height-46)/max(0.01,y1-y0)),CGPoint(x:(x0+x1)/2,y:(y0+y1)/2))
        }
        let original=fit(base,referenceSize)
        var chosen=base,best=original
        for candidate in candidates {let value=fit(candidate,referenceSize);if value.0>best.0*1.001 {chosen=candidate;best=value}}
        if best.0<original.0*1.15 {chosen=base;best=original}
        let fitted=fit(chosen,size)
        self.size=size;angle=chosen;scale=fitted.0;center=fitted.1
    }
    func point(_ p:TrackPoint)->CGPoint {
        let c=cos(angle),s=sin(angle)
        let px=CGFloat(p.x),py=CGFloat(p.y)
        let x=c*px-s*py-center.x
        let y=s*px+c*py-center.y
        return CGPoint(x:x*scale+size.width/2,y:y*scale+size.height/2)
    }
}

enum MapSafetyPriority {
    static func rank(_ flag:String)->Int {["RED":5,"DOUBLE YELLOW":4,"YELLOW":3,"SC":2,"VSC":2][flag] ?? 0}
    static func flag(phase:RacePhase,flags:[String])->String? {
        if phase == .red {return "RED"}
        if flags.contains("DOUBLE YELLOW") {return "DOUBLE YELLOW"}
        if flags.contains("YELLOW") {return "YELLOW"}
        if phase == .safetyCar {return "SC"}
        if phase == .virtualSafetyCar {return "VSC"}
        return nil
    }
}
