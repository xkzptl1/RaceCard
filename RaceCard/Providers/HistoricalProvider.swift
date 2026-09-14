import Foundation

enum ProviderError: LocalizedError {
    case liveAccess, http(Int), noCredentials, invalidResponse
    var errorDescription: String? { switch self { case .liveAccess: return "OpenF1 access is temporarily restricted. Cached historical data remains available. Live access requires Sponsor credentials."; case .http(let code): return "OpenF1 returned HTTP \(code). Last known data is retained. Retry when the service is available."; case .noCredentials: return "Enter your OpenF1 Sponsor credentials in Settings. Historical and Mock modes work without credentials."; case .invalidResponse: return "OpenF1 returned an unexpected response." } }
}
actor OpenF1HistoricalProvider {
    let cache: HistoricalCache
    let transport: URLSession
    private var positionRetryAfter:[Int:Date] = [:]
    private var positionFailures:[Int:String] = [:]
    func positionFailure(_ session:Int)->String? { positionFailures[session] }
    init(cache: HistoricalCache, transport: URLSession = .shared) { self.cache = cache; self.transport = transport }
    func fetch(_ endpoint: String, query: [URLQueryItem], token: String? = nil, timeout:TimeInterval = 120, attempts:Int = 5) async throws -> [[String: JSONValue]] {
        var components = URLComponents(string:"https://api.openf1.org/v1/\(endpoint)")!; components.queryItems = query
        var request = URLRequest(url:components.url!); request.timeoutInterval = timeout; if let token { request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization") }
        for attempt in 0..<max(1,attempts) {
            try Task.checkCancellation()
            let (data,response) = try await transport.data(for:request)
            guard let response = response as? HTTPURLResponse else { throw ProviderError.invalidResponse }
            if response.statusCode == 404 { return [] }
            if response.statusCode == 401 || response.statusCode == 403 { throw ProviderError.liveAccess }
            if response.statusCode == 429 || response.statusCode >= 500 {
                if attempt < attempts-1 { let wait = Double(response.value(forHTTPHeaderField:"Retry-After") ?? "") ?? pow(2,Double(attempt+1)); try await Task.sleep(for:.seconds(min(wait,30))); continue }
            }
            guard response.statusCode == 200 else { throw ProviderError.http(response.statusCode) }
            return try OpenF1Mapper.rows(data)
        }; throw ProviderError.invalidResponse
    }
    func sessions(year: Int) async throws -> [SessionState] {
        do { let rows = try await fetch("sessions",query:[.init(name:"year",value:String(year))]).compactMap(OpenF1Mapper.session).sorted { $0.start > $1.start }; try await cache.metadata("sessions:\(year)",data:JSONEncoder().encode(rows)); return rows }
        catch { if let data = try await cache.metadata("sessions:\(year)") { return try JSONDecoder().decode([SessionState].self,from:data) }; throw error }
    }
    func session(key: Int) async throws -> SessionState {
        if let data = try await cache.metadata("session:\(key)"), let cached = try? JSONDecoder().decode(SessionState.self,from:data), cached.end < Date().addingTimeInterval(-1800) { return cached }
        guard let session = try await fetch("sessions",query:[.init(name:"session_key",value:String(key))]).compactMap(OpenF1Mapper.session).first else { throw ProviderError.invalidResponse }; return session
    }
    func prepare(_ input: SessionState, progress: @escaping @Sendable (String) async -> Void) async throws -> SessionState {
        guard !input.isLive() else { throw ProviderError.liveAccess }
        var session = input
        let q = [URLQueryItem(name:"session_key",value:String(session.id))]
        if let data = try await cache.metadata("session:\(session.id)"), let saved = try? JSONDecoder().decode(SessionState.self,from:data) { session.title = saved.title }
        else { let meetings = try await fetch("meetings",query:[.init(name:"meeting_key",value:String(session.meeting))]); session.title = meetings.first?.s("meeting_name") ?? session.title }
        for kind in ["drivers","starting_grid","laps","stints","pit","position","intervals","race_control","weather","overtakes","session_result","championship_drivers","championship_teams"] {
            if !session.isRace && ["intervals","championship_drivers","championship_teams"].contains(kind) { continue }
            if try await cache.has(kind,session:session.id) { continue }
            await progress("Fetching \(kind.replacingOccurrences(of:"_",with:" "))…")
            let rows = try await fetch(kind,query:q)
            var records = rows.map { OpenF1Mapper.map(kind,$0,session:session) }
            if kind == "stints" {
                let laps = try await cache.read(session:session.id,after:.distantPast,through:.distantFuture,kind:"laps")
                for i in records.indices { let r = records[i]; if let lap = laps.first(where: { $0.driver == r.driver && $0.fields.i("lap_number") == r.fields.i("lap_start") }) { records[i].date = Dates.parse(lap.fields.s("date_start")) ?? lap.date } }
            }
            try await cache.write(records,session:session.id); try await cache.mark(kind,session:session.id)
            try await Task.sleep(for:.milliseconds(350))
        }
        // A missing first-lap start must not publish its completed time at scheduled session start.
        // The next lap's start is the strongest available completion timestamp.
        if try await !cache.has("timestamp-normalization-v2",session:session.id) {
            var laps = try await cache.read(session:session.id,after:.distantPast,through:.distantFuture,kind:"laps")
            for i in laps.indices where Dates.parse(laps[i].fields.s("date_start")) == nil {
                guard let duration = laps[i].fields.n("lap_duration") else { continue }
                let driver = laps[i].driver; let number = laps[i].fields.i("lap_number") ?? 0
                let next = laps.first { $0.driver == driver && $0.fields.i("lap_number") == number+1 }
                let completion = Dates.parse(next?.fields.s("date_start")) ?? session.end
                laps[i].fields["_inferred_lap_start"] = .bool(true)
                laps[i].date = completion; laps[i].fields["date_start"] = .string(Dates.iso(completion.addingTimeInterval(-duration)))
            }
            try await cache.write(laps,session:session.id)
            var stints = try await cache.read(session:session.id,after:.distantPast,through:.distantFuture,kind:"stints")
            for i in stints.indices {
                if (stints[i].fields.i("stint_number") ?? 1) == 1 { stints[i].date = session.start }
                else if let lap = laps.first(where: { $0.driver == stints[i].driver && $0.fields.i("lap_number") == stints[i].fields.i("lap_start") }) { stints[i].date = Dates.parse(lap.fields.s("date_start")) ?? lap.date }
            }
            try await cache.write(stints,session:session.id); try await cache.mark("timestamp-normalization-v2",session:session.id)
        }
        if session.isQualifying,try await !cache.has("qualifying-source-v1",session:session.id) {
            // Older race-oriented cache normalization inferred missing first-lap starts.
            // Qualifying requires the original raw start to avoid inventing sector timestamps.
            let rows=try await fetch("laps",query:q)
            try await cache.write(rows.map{OpenF1Mapper.map("laps",$0,session:session)},session:session.id)
            try await cache.mark("qualifying-source-v1",session:session.id)
        }
        if try await !cache.has("pit-exit-timestamps-v2",session:session.id) {
            let pits=try await cache.read(session:session.id,after:.distantPast,through:.distantFuture,kind:"pit")
            try await cache.write(pits.map(Self.normalizedPit),session:session.id)
            try await cache.mark("pit-exit-timestamps-v2",session:session.id)
        }
        if try await !cache.has("stint-boundaries-v7",session:session.id) {
            let laps=try await cache.read(session:session.id,after:.distantPast,through:.distantFuture,kind:"laps")
            let pits=try await cache.read(session:session.id,after:.distantPast,through:.distantFuture,kind:"pit")
            let stints=try await cache.read(session:session.id,after:.distantPast,through:.distantFuture,kind:"stints")
            try await cache.write(Self.normalizedStints(stints,laps:laps,pits:pits,session:session),session:session.id)
            try await cache.mark("stint-boundaries-v7",session:session.id)
        }
        let results = try await cache.read(session:session.id,after:.distantPast,through:.distantFuture,kind:"session_result")
        session.totalLaps = results.compactMap { $0.fields.i("number_of_laps") }.max()
        try await cache.metadata("session:\(session.id)",data:JSONEncoder().encode(session))
        return session
    }
    // OpenF1 PitStop/PitStopSeries/PitLaneTimeCollection publish the completed lane time.
    // Preserve the original reporting timestamp and normalize the interval once, including cached sessions.
    nonisolated static func normalizedPit(_ input:NormalizedRecord)->NormalizedRecord {
        var r=input
        guard let reported=Dates.parse(r.fields.s("date")) else{return r}
        r.date=reported
        r.fields.removeValue(forKey:"_pit_exit_date")
        r.fields.removeValue(forKey:"_pit_timestamp_source")
        guard let lane=r.fields.n("lane_duration"),lane.isFinite,lane>0 else{return r}
        r.fields["_pit_exit_date"] = .string(Dates.iso(reported))
        r.fields["_pit_timestamp_source"] = .string("OpenF1 completed PitStop/PitLaneTimeCollection")
        r.date=reported.addingTimeInterval(-lane)
        return r
    }
    nonisolated static func normalizedStints(_ records:[NormalizedRecord],laps:[NormalizedRecord],pits:[NormalizedRecord],session:SessionState)->[NormalizedRecord] {
        records.map { input in
            var r=input
            r.fields.removeValue(forKey:"_boundary_unresolved")
            if r.fields.i("stint_number")==1 {r.date=ReplayClock.firstLapStart(session:session,laps:laps);r.fields["_boundary_source"] = .string("first_race_lap_start");return r}
            guard let lap=r.fields.i("lap_start"),lap>0 else {r.fields["_boundary_unresolved"] = .bool(true);r.date=session.end;return r}
            let start=laps.first{$0.driver==r.driver && $0.fields.i("lap_number")==lap}.flatMap{Dates.parse($0.fields.s("date_start"))}
            let candidates=pits.filter{$0.driver==r.driver && ($0.fields.i("lap_number")==lap-1 || $0.fields.i("lap_number")==lap)}
            let pit=candidates.min{abs($0.date.timeIntervalSince(start ?? $0.date)) < abs($1.date.timeIntervalSince(start ?? $1.date))}
            if let start {r.date=start;r.fields["_boundary_source"] = .string("lap_start")}
            else if let pit {r.date=pit.date;r.fields["_boundary_source"] = .string("pit_entry")}
            else {r.date=session.end;r.fields["_boundary_unresolved"] = .bool(true);return r}
            if let pit {
                // The set is certainly fitted by the recorded pit exit; never announce it before entry.
                let exit=pit.date.addingTimeInterval(max(0,pit.fields.n("lane_duration") ?? 0))
                r.date=max(r.date,exit);r.fields["_boundary_source"] = .string("lap_start_and_pit")
            }
            return r
        }
    }
    func locations(_ session: SessionState, from: Date, through: Date, driver: Int? = nil) async throws {
        let first = Int(floor(from.timeIntervalSince1970 / 120)); let last = Int(floor(through.timeIntervalSince1970 / 120))
        guard first <= last else { return }
        for chunk in first...last {
            let resource = "location:\(driver ?? 0):\(chunk)"
            if try await cache.has(resource,session:session.id) { continue }
            var query: [URLQueryItem] = [.init(name:"session_key",value:String(session.id)),.init(name:"date>",value:Dates.iso(Date(timeIntervalSince1970:Double(chunk)*120))),.init(name:"date<",value:Dates.iso(Date(timeIntervalSince1970:Double(chunk+1)*120)))]
            if let driver { query.append(.init(name:"driver_number",value:String(driver))) }
            let records = try await fetch("location",query:query).map { OpenF1Mapper.map("location",$0,session:session) }
            try await cache.write(records,session:session.id); try await cache.mark(resource,session:session.id)
        }
    }
    func locationsIfAvailable(_ session:SessionState,from:Date,through:Date,driver:Int? = nil) async throws -> Bool {
        let first=Int(floor(from.timeIntervalSince1970/120)),last=Int(floor(through.timeIntervalSince1970/120))
        guard first<=last else{return true}
        var cached=true
        for chunk in first...last {
            if try await !cache.has("location:\(driver ?? 0):\(chunk)",session:session.id) {cached=false;break}
        }
        if cached {positionFailures[session.id]=nil;return true}
        if let retry=positionRetryAfter[session.id],retry>Date() {return false}
        do {try await locations(session,from:from,through:through,driver:driver);positionRetryAfter[session.id]=nil;positionFailures[session.id]=nil;return true}
        catch is CancellationError {throw CancellationError()}
        catch {
            try Task.checkCancellation()
            positionRetryAfter[session.id]=Date().addingTimeInterval(60)
            if case ProviderError.liveAccess = error {
                positionFailures[session.id]="Historical positions temporarily restricted by provider · retrying automatically"
            } else {
                positionFailures[session.id]="Car positions could not load · retrying automatically"
            }
            return false
        }
    }
    func circuit(_ session: SessionState) async throws -> [TrackLocationState] {
        let laps = try await cache.read(session:session.id,after:.distantPast,through:.distantFuture,kind:"laps",limit:2000)
        guard let lap = laps.first(where: { ($0.fields.i("lap_number") ?? 0) >= 2 && ($0.fields.n("lap_duration") ?? 0) > 0 && !$0.fields.b("is_pit_out_lap") }), let driver = lap.driver, let start = Dates.parse(lap.fields.s("date_start")), let duration = lap.fields.n("lap_duration") else { return [] }
        guard try await locationsIfAvailable(session,from:start,through:start.addingTimeInterval(duration),driver:driver) else{return []}
        let points = try await cache.read(session:session.id,after:start,through:start.addingTimeInterval(duration),kind:"location",driver:driver)
        return points.compactMap { r in guard let x = r.fields.n("x"), let y = r.fields.n("y"), x != 0 || y != 0 else { return nil }; return TrackLocationState(x:x,y:y,date:r.date) }
    }
    func telemetry(_ session: SessionState, driver: Int, time: Date) async throws -> [NormalizedRecord] {
        let chunk = Int(time.timeIntervalSince1970 / 30); let resource = "car_data:\(driver):\(chunk)"
        if try await !cache.has(resource,session:session.id) {
            let rows = try await fetch("car_data",query:[.init(name:"session_key",value:String(session.id)),.init(name:"driver_number",value:String(driver)),.init(name:"date>",value:Dates.iso(Date(timeIntervalSince1970:Double(chunk)*30-5))),.init(name:"date<",value:Dates.iso(Date(timeIntervalSince1970:Double(chunk+1)*30)))],timeout:10,attempts:1)
            try await cache.write(rows.map { OpenF1Mapper.map("car_data",$0,session:session) },session:session.id); try await cache.mark(resource,session:session.id)
        }
        return try await cache.read(session:session.id,after:Date(timeIntervalSince1970:Double(chunk)*30-5),through:Date(timeIntervalSince1970:Double(chunk+1)*30),kind:"car_data",driver:driver)
    }
}
