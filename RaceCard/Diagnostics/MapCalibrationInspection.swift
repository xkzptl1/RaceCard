#if DEBUG
import Foundation

/// Native visual QA adapter for recorded OpenF1 payloads. It uses the production
/// mapper, state store, coordinate registration and map renderer. Release builds
/// do not include this entry point.
extension AppModel {
    func inspectCalibration(at file:URL) {
        struct Capture:Decodable {
            struct Sample:Decodable {let lap:[String:JSONValue];let locations:[[String:JSONValue]]}
            let session:[String:JSONValue];let samples:[Sample];let drivers:[[String:JSONValue]]
        }
        do {
            let capture=try JSONDecoder().decode(Capture.self,from:Data(contentsOf:file))
            guard var session=OpenF1Mapper.session(capture.session),capture.samples.count>=2 else {throw ProviderError.invalidResponse}
            session.title="Historical calibration · "+session.circuit
            let sample=capture.samples[1]
            guard let number=sample.lap.i("driver_number"),let date=Dates.parse(sample.locations[sample.locations.count/2].s("date")) else {throw ProviderError.invalidResponse}
            store.reset(session,mode:.historical)
            store.track=capture.samples[0].locations.compactMap {row in
                guard let x=row.n("x"),let y=row.n("y"),let time=Dates.parse(row.s("date")) else{return nil}
                return .init(x:x,y:y,date:time)
            }
            var records=capture.drivers.filter{$0.i("driver_number")==number}.map{OpenF1Mapper.map("drivers",$0,session:session)}
            records += sample.locations.map{OpenF1Mapper.map("location",$0,session:session)}
            records += capture.samples.map{OpenF1Mapper.map("laps",$0.lap,session:session)}
            store.ingest(records.filter{$0.date<=date})
            store.recordPositionSamples(records.filter{$0.kind=="location" && abs($0.date.timeIntervalSince(date))<2})
            store.currentTime=date;store.selected=number
            clock = .init(start:session.start,end:session.end,time:date,speed:1,playing:false)
            loading="";showingBack=false
        } catch {self.error="Calibration inspection: "+error.localizedDescription}
    }
}
#endif
