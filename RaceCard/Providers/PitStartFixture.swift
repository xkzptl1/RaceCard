import Foundation

/// Explicit synthetic regression scenario; never supplied to Historical or Live providers.
enum PitStartFixture {
    static func records()->[NormalizedRecord] {
        var records=MockF1Provider.records().filter{!($0.kind=="intervals" && $0.driver==10)}.filter{!["position","starting_grid","race_control","laps","pit","stints"].contains($0.kind) || $0.kind=="stints" && $0.date==MockF1Provider.start}
        func add(_ kind:String,_ t:Double,_ f:[String:JSONValue]) {
            var fields=f;fields["date"] = .string(Dates.iso(MockF1Provider.start.addingTimeInterval(t)))
            records.append(OpenF1Mapper.map(kind,fields,session:MockF1Provider.session))
        }
        let order=[10]+MockF1Provider.numbers.filter{![10,14,30].contains($0)}
        for (i,id) in order.enumerated(){add("starting_grid",0,["driver_number":.number(Double(id)),"position":.number(Double(i+1))])}
        for id in [14,30] {add("starting_grid",0,["driver_number":.number(Double(id)),"pit_lane_start":.bool(true)])}
        add("race_control",1,["message":.string("FORMATION LAP STARTED")])
        add("race_control",10,["message":.string("GRID FORMING")])
        add("race_control",15,["message":.string("START LIGHTS")])
        add("race_control",20,["message":.string("LIGHTS OUT"),"flag":.string("GREEN")])
        for (i,id) in order.enumerated(){add("position",20,["driver_number":.number(Double(id)),"position":.number(Double(i+1))])}
        add("intervals",20,["driver_number":.number(10),"gap_to_leader":.null])
        add("position",30,["driver_number":.number(14),"position":.number(21)])
        add("position",40,["driver_number":.number(30),"position":.number(22)])
        add("race_control",50,["message":.string("SAFETY CAR DEPLOYED")])
        add("race_control",55,["message":.string("CAR 14 - 5 SECOND TIME PENALTY")])
        add("race_control",65,["message":.string("SAFETY CAR ENDED"),"flag":.string("GREEN")])
        return records.sorted{$0.date<$1.date}
    }
}
