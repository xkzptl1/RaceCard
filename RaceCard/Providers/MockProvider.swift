import Foundation

enum MockF1Provider {
    static let start = Date(timeIntervalSince1970: 1_780_000_000)
    static var session: SessionState { SessionState(id: -1,meeting: -1,title:"Demo Grand Prix",circuit:"RaceCard test circuit · deterministic simulation",type:"Race",start:start,end:start.addingTimeInterval(300),totalLaps:20) }
    static let names = ["NOR","VER","LEC","PIA","RUS","HAM","ALO","SAI","STR","TSU","GAS","OCO","ALB","HUL","LAW","BEA","HAD","BOR","ANT","DOO","PER","BOT"]
    static let numbers = [4,1,16,81,63,44,14,55,18,22,10,31,23,27,30,87,6,5,12,7,11,77]
    static let colors = ["E87924","3775CF","D83D49","E87924","25A59A","D83D49","26877B","417CC5","26877B","3775CF","D45AA1","A4A7AF","417CC5","6AA938","4866AA","A4A7AF","4866AA","6AA938","25A59A","D45AA1","AAAAAD","AAAAAD"]
    static let teams = ["McLaren","Red Bull Racing","Ferrari","McLaren","Mercedes","Ferrari","Aston Martin","Williams","Aston Martin","Racing Bulls","Alpine","Haas F1 Team","Williams","Audi","Racing Bulls","Haas F1 Team","Red Bull Racing","Audi","Mercedes","Alpine","Cadillac","Cadillac"]
    static func point(_ phase: Double, date: Date) -> TrackLocationState { let a = phase * 2 * Double.pi; return .init(x:cos(a)*1000 + sin(3*a)*240,y:sin(a)*640 + cos(2*a)*180,date:date) }
    static var track: [TrackLocationState] { (0...240).map { point(Double($0)/240,date:start) } }
    static func records(includeStartLights:Bool=false) -> [NormalizedRecord] {
        var all: [NormalizedRecord] = []
        func add(_ kind: String, _ sec: Double, _ fields: [String: JSONValue]) { var f = fields; f["date"] = .string(Dates.iso(start.addingTimeInterval(sec))); all.append(OpenF1Mapper.map(kind,f,session:session,received:start.addingTimeInterval(sec))) }
        for i in 0..<numbers.count {
            let d: [String: JSONValue] = ["driver_number":.number(Double(numbers[i]))]
            add("drivers",0,d.merging(["name_acronym":.string(names[i]),"full_name":.string(DriverNameResolver.fullNames[names[i]] ?? names[i]),"team_name":.string(teams[i]),"team_colour":.string(colors[i])]) { _,b in b })
            add("position",0,d.merging(["position":.number(Double(i+1))]) { _,b in b })
            add("starting_grid",0,d.merging(["position":.number(Double(i+1))]) { _,b in b })
            add("stints",0,d.merging(["stint_number":.number(1),"compound":.string(["SOFT","MEDIUM","HARD","INTERMEDIATE","WET"][i%5]),"lap_start":.number(1),"tyre_age_at_start":.number(Double(i%2))]) { _,b in b })
            add("championship_drivers",0,d.merging(["points_start":.number(Double(180-i*7)),"points_current":.number(Double(205-i*8)),"position_start":.number(Double(i+1)),"position_current":.number(Double(i+1))]) { _,b in b })
        }
        for (i,team) in Array(Set(teams)).sorted().enumerated() { add("championship_teams",0,["team_name":.string(team),"points_start":.number(Double(350-i*20)),"points_current":.number(Double(380-i*21)),"position_start":.number(Double(i+1)),"position_current":.number(Double(i+1))]) }
        for t in stride(from:0,through:300,by:1) {
            for i in 0..<numbers.count {
                let id = Double(numbers[i]); let time = Double(t); let p = point((i == 19 ? min(time,135) : time)/15 - Double(i)*0.018,date:start.addingTimeInterval(time))
                add("location",time,["driver_number":.number(id),"x":.number(p.x),"y":.number(p.y)])
                if t%5 == 0 { add("intervals",time,["driver_number":.number(id),"gap_to_leader":.number(Double(t >= 105 ? (i == 0 ? 1 : i == 1 ? 0 : i) : i)*1.837),"interval":.number((t >= 105 ? i == 1 : i == 0) ? 0 : 1.837)]) }
                if t > 0 && t%15 == 0 && !(i == 19 && t > 135) { add("laps",time,["driver_number":.number(id),"lap_number":.number(Double(t/15)),"lap_duration":.number(90.5+Double(i)*0.14-time/2000),"date_start":.string(Dates.iso(start.addingTimeInterval(time-15))),"duration_sector_1":.number(28.234),"duration_sector_2":.number(34.617),"duration_sector_3":.number(27.649),"st_speed":.number(321),"i1_speed":.number(295),"i2_speed":.number(288)]) }
            }
        }
        for (t,flag,message,driver) in [(0,"GREEN","SESSION START",0),(35,"YELLOW","YELLOW FLAG · sector 2",0),(55,"","SAFETY CAR DEPLOYED",0),(80,"","SAFETY CAR IN THIS LAP",0),(90,"GREEN","GREEN FLAG",0),(135,"YELLOW","CAR 7 (DOO) STOPPED AT TURN 8",7),(155,"GREEN","GREEN FLAG",0),(300,"CHEQUERED","SESSION END",0)] { if includeStartLights && t == 0 { continue }; var f: [String:JSONValue] = ["flag":.string(flag),"message":.string(message),"lap_number":.number(Double(t/15))]; if driver > 0 { f["driver_number"] = .number(Double(driver)) }; if flag == "YELLOW" { f["sector"] = .number(2) }; add("race_control",Double(t),f) }
        if includeStartLights {
            // Authored source records for UI verification; never used in Historical or Live.
            for count in 1...5 {add("race_control",Double(count),["start_lights":.number(Double(count)),"message":.string("START LIGHTS")])}
            add("race_control",6,["message":.string("SESSION START"),"flag":.string("GREEN")])
        }
        add("pit",100,["driver_number":.number(4),"lap_number":.number(7),"stop_duration":.number(2.41),"lane_duration":.number(22.8)])
        add("stints",123,["driver_number":.number(4),"stint_number":.number(2),"lap_start":.number(8),"compound":.string("HARD"),"tyre_age_at_start":.number(0)])
        add("position",105,["driver_number":.number(4),"position":.number(2)]); add("position",105,["driver_number":.number(1),"position":.number(1)])
        add("intervals",105,["driver_number":.number(4),"gap_to_leader":.number(1.837),"interval":.number(1.837)]); add("intervals",105,["driver_number":.number(1),"gap_to_leader":.number(0),"interval":.number(0)])
        add("overtakes",105,["overtaking_driver_number":.number(1),"overtaken_driver_number":.number(4),"position":.number(1)])
        for (t,message) in [(20,"DRS ENABLED"),(160,"VIRTUAL SAFETY CAR DEPLOYED"),(170,"VIRTUAL SAFETY CAR ENDING"),(175,"SESSION RESUMED"),(195,"CAR 1 (VER) - 5 SECOND TIME PENALTY"),(205,"SESSION SUSPENDED"),(215,"SESSION RESUMED"),(225,"DOUBLE YELLOW IN TRACK SECTOR 2"),(235,"GREEN LIGHT")] {
            add("race_control",Double(t),["message":.string(message),"flag":.string(t == 205 ? "RED" : t == 225 ? "DOUBLE YELLOW" : t == 235 ? "GREEN" : ""),"sector":.number(2)])
        }
        // Coherent multi-car snapshot and a later single-place exchange exercise the tower motion.
        for i in 0..<5 { add("position",12,["driver_number":.number(Double(numbers[i])),"position":.number(Double((i+2)%5+1))]) }
        for i in 0..<5 { add("position",22,["driver_number":.number(Double(numbers[i])),"position":.number(Double(i+1))]) }
        for (t,rain) in [(0,0),(180,1)] { add("weather",Double(t),["air_temperature":.number(24),"track_temperature":.number(rain == 0 ? 38 : 32),"rainfall":.number(Double(rain)),"humidity":.number(62),"wind_speed":.number(2.4)]) }
        for i in 0..<numbers.count { add("session_result",300,["driver_number":.number(Double(numbers[i])),"position":.number(Double(i == 0 ? 2 : i == 1 ? 1 : i+1)),"gap_to_leader":.number(Double(i == 0 ? 1 : i == 1 ? 0 : i)*1.837),"number_of_laps":.number(i == 19 ? 9 : 20),"dnf":.bool(i == 19)]) }
        return all.sorted { $0.date < $1.date }
    }
    static func telemetry(driver: Int,time: Date) -> TelemetryState { .init(speed:250+Int(50*sin(time.timeIntervalSince(start))),gear:7,rpm:11240,throttle:98,brake:0,drs:12,date:time) }
}
