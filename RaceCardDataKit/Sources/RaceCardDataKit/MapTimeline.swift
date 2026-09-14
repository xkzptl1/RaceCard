import Foundation

public struct Coordinate: Codable, Equatable, Sendable {
    public var x: Double; public var y: Double
    public init(x:Double,y:Double) {self.x=x;self.y=y}
}
public struct CircuitCoordinateTransform: Codable, Sendable {
    public var circuitKey:Int
    public var sessionKey:Int
    public var scale:Double
    public var rotation:Double
    public var translation:Coordinate
    public var flipY:Bool
    public var affineMatrix:[Double]?
    public var staticGeometryPath:String?
    public var canonicalCenterline:[Coordinate]?
    public var referenceCenterline:[Coordinate]?
    public var validation:Validation
    public struct Validation:Codable,Sendable {
        public var sampleCount:Int
        public var meanDistance:Double
        public var p95Distance:Double
        public var maxDistance:Double
        public var sourceURLs:[String]
    }
    public func apply(_ point:Coordinate)->Coordinate {
        if let m=affineMatrix,m.count==4 {return Coordinate(x:m[0]*point.x+m[1]*point.y+translation.x,y:m[2]*point.x+m[3]*point.y+translation.y)}
        let y=flipY ? -point.y:point.y, c=cos(rotation), s=sin(rotation)
        return Coordinate(x:scale*(c*point.x-s*y)+translation.x,y:scale*(s*point.x+c*y)+translation.y)
    }
    public func validated(for samples:[Coordinate],session:Int,sourceURL:String)->CircuitCoordinateTransform? {
        guard let centerline=referenceCenterline,centerline.count>20,samples.count>30 else{return nil}
        let distances=samples.map {point -> Double in
            let p=apply(point)
            return centerline.reduce(Double.infinity) {min($0,hypot(p.x-$1.x,p.y-$1.y))}
        }.sorted()
        let mean=distances.reduce(0,+)/Double(distances.count),p95=distances[min(distances.count-1,Int(Double(distances.count)*0.95))],maximum=distances.last!
        guard mean<0.012,p95<0.03,maximum<0.08 else{return nil}
        var result=self;result.sessionKey=session;result.validation=Validation(sampleCount:samples.count,meanDistance:mean,p95Distance:p95,maxDistance:maximum,sourceURLs:validation.sourceURLs+[sourceURL]);return result
    }
    public var isValid:Bool {
        (affineMatrix.map{$0.count==4 && $0.allSatisfy(\.isFinite) && abs($0[0]*$0[3]-$0[1]*$0[2])>1e-16} ?? true) && (staticGeometryPath.map{MetadataValidator.safePath($0)} ?? true) && scale.isFinite && scale>0 && rotation.isFinite && translation.x.isFinite && translation.y.isFinite && validation.sampleCount>0 && !validation.sourceURLs.isEmpty && [validation.meanDistance,validation.p95Distance,validation.maxDistance].allSatisfy{$0.isFinite && $0>=0} && validation.meanDistance<=validation.p95Distance && validation.p95Distance<=validation.maxDistance
    }
}
public struct PositionSample:Codable,Equatable,Sendable {
    public var time:Date; public var position:Coordinate
    public init(time:Date,position:Coordinate) {self.time=time;self.position=position}
}
public enum PositionInterpolator {
    /// No extrapolation. A discontinuity or a missing interval returns the last factual
    /// position, rather than inventing a trajectory across the circuit.
    public static func position(at cursor:Date,samples:[PositionSample],maximumGap:TimeInterval=2,maximumDistance:Double=1500)->Coordinate? {
        guard !samples.isEmpty else {return nil}
        var low=0,high=samples.count
        while low<high {let middle=(low+high)/2;if samples[middle].time<=cursor {low=middle+1}else{high=middle}}
        guard low>0 else{return nil}
        let a=samples[low-1]
        guard low<samples.count else{return a.position}
        let b=samples[low],duration=b.time.timeIntervalSince(a.time)
        guard duration>0,duration<=maximumGap,hypot(b.position.x-a.position.x,b.position.y-a.position.y)<=maximumDistance else{return a.position}
        let t=min(1,max(0,cursor.timeIntervalSince(a.time)/duration))
        return Coordinate(x:a.position.x+(b.position.x-a.position.x)*t,y:a.position.y+(b.position.y-a.position.y)*t)
    }
}
public struct StartLightTimeline:Sendable {
    public enum AnchorSource:String,Sendable {case explicitStart,firstLapStart}
    public var anchor:Date
    public var source:AnchorSource
    public init(anchor:Date,source:AnchorSource) {self.anchor=anchor;self.source=source}
    public struct State:Equatable,Sendable {public var illuminated:Int;public var opacity:Double;public init(illuminated:Int,opacity:Double){self.illuminated=illuminated;self.opacity=opacity}}
    public func state(at cursor:Date)->State? {
        let elapsed=cursor.timeIntervalSince(anchor)
        guard elapsed>=(-5),elapsed<3 else{return nil}
        return State(illuminated:elapsed<0 ? 5:0,opacity:elapsed<1 ? 1:max(0,1-(elapsed-1)/2))
    }
}
