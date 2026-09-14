import RaceCardDataKit
import Foundation
import Observation

@MainActor @Observable final class AppModel {
    let store = RaceStateStore()
    let identities = IdentityLibrary()
    let cache: HistoricalCache
    let historical: OpenF1HistoricalProvider
    let tokens = TokenManager()
    var live: OpenF1LiveProvider!
    var clock = ReplayClock(start:MockF1Provider.start,end:MockF1Provider.session.end,time:MockF1Provider.start,speed:1,playing:true)
    var didLaunch = false
    private(set) var replayOpeningTime = MockF1Provider.start
    private var replayLapStarts:[(driver:Int,lap:Int,start:Date)]=[]
    var showingBack = false
    var profile:ProfileRoute?
    var mockStartLights = false
    var pitStartFixture = false
    var referenceOverride: String?
    var timingSectorFixture = false
    var focusHovered = false
    var focusDetailOpen = false
    var focusDeadline: Date?
    func focusDriver(_ id: Int) { cancelTelemetry(); store.selected = id; store.drivers[id]?.telemetry=nil; telemetryAt = .distantPast; if store.mode == .live {connectStream()} else {scheduleTelemetry()}; focusDeadline = Date().addingTimeInterval(10) }
    func dismissFocus() { cancelTelemetry(); store.selected = nil; focusDeadline = nil; focusHovered = false; focusDetailOpen=false }
    func touchFocus(at now:Date = Date()) { focusDeadline = now.addingTimeInterval(10) }
    func advanceFocus(at now:Date) {
        if store.session?.isQualifying == true {return}
        guard store.selected != nil else { return }
        if focusHovered || focusDetailOpen || inspector || settings || !loading.isEmpty { touchFocus(at:now) }
        else if let focusDeadline, now >= focusDeadline { dismissFocus() }
    }
    var focusedEvents: [FeedEvent] { guard let selected=store.selected else { return [] }; return store.events.filter{$0.driverNumbers.contains(selected)} }

    var metadataLibrary = false
    @ObservationIgnored private var cachedTrackRepository:TrackMetadataRepository?
    var trackRepository:TrackMetadataRepository {
        let remote=identities.metadataRoot.appendingPathComponent("TrackMetadata")
        let root=FileManager.default.fileExists(atPath:remote.path) ? remote:Bundle.main.resourceURL?.appendingPathComponent("TrackMetadata")
        if cachedTrackRepository?.root != root {cachedTrackRepository=TrackMetadataRepository(root:root)}
        return cachedTrackRepository ?? TrackMetadataRepository(root:root)
    }
    var sessions: [SessionState] = []
    var loading = ""; var error: String?; var inspector = false; var settings = false; var picker = false
    var language: String { get { Localization.shared.language } set { Localization.shared.language = newValue } }
    var authStatus = "Not checked"
    var theme: String { didSet { UserDefaults.standard.set(theme,forKey:"theme") } }
    var precision: Int { didSet { UserDefaults.standard.set(precision,forKey:"precision") } }
    var defaultSpeed: Double { didSet { UserDefaults.standard.set(defaultSpeed,forKey:"speed") } }
    var spoilerFree: Bool { didSet { UserDefaults.standard.set(spoilerFree,forKey:"spoilerFree") } }
    var displayDelay: Double { didSet { UserDefaults.standard.set(displayDelay,forKey:"delay") } }
    private var loop: Task<Void,Never>?; private var liveTask: Task<Void,Never>?; private var operation: Task<Void,Never>?
    private var buffered: [(Date,NormalizedRecord)] = []
    private var generation = UUID()
    private var mock: [NormalizedRecord] = []
    private var mockStartAnchor:Date? {mock.first{$0.kind == "race_control" && EventNormalizer.classification($0.fields.s("message") ?? "") == "SESSION START"}?.date}
    private var positionRecoveryAt = Date.distantPast
    private var telemetryAt = Date.distantPast
    private var telemetryTask:Task<Void,Never>?
    private var telemetryRequest:UUID?
    private(set) var telemetryStatus:String?
    private var telemetryRows:[NormalizedRecord]=[]
    private var telemetryChunks:Set<Int>=[]
    private var telemetryRetryAfter=Date.distantPast
    private func applyTelemetryBuffer() {
        guard let id=store.selected,store.mode != .live,store.mode != .mock else{return}
        store.drivers[id]?.telemetry=TelemetryState.resolve(telemetryRows,driver:id,at:store.currentTime)
    }
    private func cancelTelemetry() {telemetryTask?.cancel();telemetryTask=nil;telemetryRequest=nil;telemetryAt = .distantPast;telemetryRows=[];telemetryChunks=[];telemetryRetryAfter = .distantPast;telemetryStatus=nil}
    private func scheduleTelemetry() {
        guard telemetryTask == nil,store.selected != nil,store.mode != .live else{return}
        let request=UUID();telemetryRequest=request
        telemetryTask=Task { [weak self] in
            guard let self else{return};await refreshTelemetry()
            if telemetryRequest==request {telemetryTask=nil;telemetryRequest=nil}
        }
    }
    init(cachePath: String? = nil, historicalTransport:URLSession = .shared) {
        let defaults = UserDefaults.standard
        theme = defaults.string(forKey:"theme") ?? "Light"; precision = defaults.object(forKey:"precision") as? Int ?? 3; defaultSpeed = defaults.object(forKey:"speed") as? Double ?? 1; spoilerFree = defaults.object(forKey:"spoilerFree") as? Bool ?? true; displayDelay = defaults.double(forKey:"delay")
        let folder = RaceCardStorage.applicationSupport
        do { try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true); cache = try HistoricalCache(path:cachePath ?? folder.appendingPathComponent("history.sqlite").path) } catch { fatalError("RaceCard cannot open its local cache: \(error.localizedDescription)") }
        historical = OpenF1HistoricalProvider(cache:cache,transport:historicalTransport); live = OpenF1LiveProvider(tokens:tokens)
    }
    private var qualifyingLiveRecords:[String:NormalizedRecord]=[:]
    var qualifyingTimeline=QualifyingTimeline()
    var qualifying=QualifyingSnapshot()
    var qualifyingSlots=QualifyingSlots()
    var qualifyingRankMotion=QualifyingRankMotion()
    var qualifyingAnimateRanks=false
    func updateQualifying(resetMotion:Bool=false) {
        guard store.session?.isQualifying == true else {qualifying = .init();return}
        let previousPhase=qualifying.phase
        qualifying=qualifyingTimeline.snapshot(at:store.currentTime,drivers:store.drivers,pits:store.drivers.values.flatMap(\.pits))
        qualifyingAnimateRanks = !resetMotion && previousPhase==qualifying.phase && (clock.playing || store.mode == .live)
        qualifyingRankMotion.update(qualifying,at:Date(),reset:resetMotion)
        qualifyingSlots.update(qualifying,at:Date())
    }
    func qualifyingPhaseLabel(_ phase:Int)->String {store.session?.qualifyingPhaseTitle(phase) ?? "Q\(phase)"}
    func pinQualifying(_ driver:Int?,slot:Int) {qualifyingSlots.pin(driver,slot:slot)}
    func start() { guard loop == nil else { return }; loadMock(); Task {if let records=try? await cache.cachedDriverSnapshots() {await identities.importSnapshots(records)}}; loop = Task { [weak self] in
        var last = Date()
        while !Task.isCancelled { do { try await Task.sleep(for:.milliseconds(200)) } catch { return }; guard let self else { return }; let now = Date(); let elapsed = max(0,now.timeIntervalSince(last)); last = now; await self.tick(elapsed,now:now) }
    } }
    private func cancelMode() { qualifyingRankMotion = .init();showingBack=false;qualifyingLiveRecords=[:];qualifyingTimeline = .init();qualifying = .init();qualifyingSlots = .init(); dismissFocus(); operation?.cancel(); liveTask?.cancel(); generation = UUID(); buffered = []; error = nil; loading = ""; inspector = false }
    func loadMock() {
        cancelMode(); mock = pitStartFixture ? PitStartFixture.records() : MockF1Provider.records(includeStartLights:mockStartLights); store.reset(MockF1Provider.session,mode:.mock); store.raceStart.factualAnchor=mockStartAnchor; store.track = MockF1Provider.track
        if timingSectorFixture {
            mock.append(OpenF1Mapper.map("race_control",["date":.string(Dates.iso(MockF1Provider.start.addingTimeInterval(35))),"scope":.string("TimingSector"),"sector":.number(2),"flag":.string("DOUBLE YELLOW"),"message":.string("DOUBLE YELLOW IN TIMING SECTOR 2")],session:MockF1Provider.session))
        }
        replayOpeningTime = MockF1Provider.start
        clock = .init(start:MockF1Provider.start,end:MockF1Provider.session.end,time:MockF1Provider.start,speed:defaultSpeed,playing:true)
        store.ingest(mock.filter { $0.date <= clock.time }); store.recordPositionSamples(mock.filter{$0.kind == "location" && $0.date >= clock.time.addingTimeInterval(-2) && $0.date <= clock.time.addingTimeInterval(2)}); store.currentTime = clock.time
        identities.refresh(MockF1Provider.session,drivers:Array(store.drivers.values))
        Task { await identities.updateRemote() }
    }
    func listSessions(year: Int) async { loading = "Finding \(year) sessions…"; defer { loading = "" }; do { sessions = try await historical.sessions(year:year) } catch { self.error = error.localizedDescription } }
    func openHistorical(_ session: SessionState,replay: Bool = true) {
        cancelMode(); let gen = generation
        operation = Task {
            do {
                loading = "Opening historical session…"
                let s = try await historical.prepare(session) { [weak self] message in guard let self else { return }; await MainActor.run { if self.generation == gen { self.loading = message } } }
                try Task.checkCancellation(); guard gen == generation else { return }
                store.reset(s,mode:replay ? .replay : .historical)
                let laps = try await cache.read(session:s.id,after:.distantPast,through:s.isQualifying ? .distantFuture:s.end,kind:"laps")
                replayLapStarts=laps.compactMap{r in guard let id=r.driver,let lap=r.fields.i("lap_number"),let date=Dates.parse(r.fields.s("date_start")) else{return nil};return (id,lap,date)}
                let control=try await cache.read(session:s.id,after:.distantPast,through:.distantFuture,kind:"race_control")
                if s.isQualifying {
                    let results=try await cache.read(session:s.id,after:.distantPast,through:.distantFuture,kind:"session_result")
                    let roster=try await cache.read(session:s.id,after:.distantPast,through:.distantFuture,kind:"drivers")
                    qualifyingTimeline=QualifyingTimeline(records:laps+control+results+roster)
                } else {qualifyingTimeline = .init()}
                let start = ReplayClock.factualStart(session:s,laps:laps,control:control)
                let domainStart=min(s.start,control.map(\.date).min() ?? s.start)
                let domainEnd=max(s.end,control.map(\.date).max() ?? s.end)
                replayOpeningTime = start
                // Open at Lap 1, while retaining source-backed pre-start replay access.
                clock = .init(start:domainStart,end:domainEnd,time:start,speed:defaultSpeed,playing:false)
                loading = "Aligning circuit to OpenF1 coordinates…"
                store.track = try await historical.circuit(s)
                var target = replay ? start : s.end
                let args=ProcessInfo.processInfo.arguments
                if let sessionIndex=args.firstIndex(of:"--historical"),args.indices.contains(sessionIndex+1),args[sessionIndex+1] == String(s.id),
                   let i=args.firstIndex(of:"--historical-cursor"),args.indices.contains(i+1),let cursor=Dates.parse(args[i+1]) {target=max(clock.start,min(clock.end,cursor))}
                let locationTime = replay ? target : (laps.map(\.date).max() ?? target)
                loading = "Loading car positions…"
                let positions=try await historical.locationsIfAvailable(s,from:locationTime.addingTimeInterval(-120),through:locationTime.addingTimeInterval(2))
                try await rebuild(to:target,generation:gen)
                guard gen == generation else{return};store.positionDataUnavailable = !positions;store.positionDataMessage = await historical.positionFailure(s.id)
                identities.refresh(s,drivers:Array(store.drivers.values))
                loading = ""; picker = false
            } catch is CancellationError {} catch { if gen == generation { self.error = error.localizedDescription; loading = "" } }
        }
    }
    func openHistoricalKey(_ key: Int,replay: Bool = true) async {
        do { let session = try await historical.session(key:key); openHistorical(session,replay:replay) } catch { self.error = error.localizedDescription }
    }
    func togglePlayback() {
        guard loading.isEmpty, store.mode != .live else { return }
        if store.mode == .historical || (!clock.playing && clock.time >= clock.end) {
            seek(replayOpeningTime, resumePlaying:true)
        } else {
            clock.playing.toggle()
        }
    }
    func seek(_ target: Date, resumePlaying: Bool? = nil) {
        guard store.mode != .live else { return }
        touchFocus();cancelTelemetry();qualifyingSlots.automatic=[];qualifyingSlots.changedAt = .distantPast
        if store.mode == .historical { store.mode = .replay }
        let selected=store.selected; operation?.cancel(); let gen = UUID(); generation = gen; let playing = resumePlaying ?? clock.playing; clock.playing = false
        operation = Task { do {
            if store.mode == .mock { store.isRebuilding = true; defer { store.isRebuilding = false; store.clearMovements() }; let track = store.track; store.reset(MockF1Provider.session,mode:.mock); store.raceStart.factualAnchor=mockStartAnchor; store.track = track; clock.seek(target); store.ingest(mock.filter { $0.date <= clock.time }); store.recordPositionSamples(mock.filter{$0.kind == "location" && $0.date >= clock.time.addingTimeInterval(-2) && $0.date <= clock.time.addingTimeInterval(2)}); store.currentTime = clock.time }
            else if let s = store.session {
                loading = "Seeking…"
                let positions=try await historical.locationsIfAvailable(s,from:max(clock.start,target.addingTimeInterval(-120)),through:min(clock.end,target.addingTimeInterval(2)))
                try await rebuild(to:target,generation:gen)
                guard gen == generation else{return};store.positionDataUnavailable = !positions;store.positionDataMessage = await historical.positionFailure(s.id)
            }
            if gen == generation { store.selected=selected;telemetryAt = .distantPast; clock.playing = playing; loading = ""; scheduleTelemetry() }
        } catch is CancellationError {} catch { if gen == generation { loading = ""; self.error = error.localizedDescription } } }
    }
    func seekLap(_ number: Int) async {
        guard let s = store.session else { return }
        if store.mode == .mock { seek(s.start.addingTimeInterval(Double(number-1)*15)); return }
        do {
            let records = try await cache.read(session:s.id,after:.distantPast,through:s.end,kind:"laps")
            let date = number == 1 ? ReplayClock.firstLapStart(session:s,laps:records) : records.filter{$0.fields.i("lap_number") == number}.compactMap{Dates.parse($0.fields.s("date_start"))}.min()
            if let date {seek(date)}
        } catch { self.error = error.localizedDescription }
    }
    private func rebuild(to target: Date,generation gen: UUID) async throws {
        guard let s = store.session else { return }; let mode = store.mode
        store.isRebuilding = true; defer { store.isRebuilding = false; store.clearMovements() }
        store.reset(s,mode:mode,preserveTrack:true); store.raceStart.factualAnchor = replayOpeningTime; clock.seek(target)
        // Driver identity is session metadata, not a future track position or result.
        let roster=try await cache.read(session:s.id,after:.distantPast,through:.distantFuture,kind:"drivers")
        store.ingest(roster.map{var r=$0;r.date=clock.start;return r})
        var offset = 0
        while true {
            let rows = try await cache.read(session:s.id,after:.distantPast,through:clock.time,limit:5000,offset:offset,rebuild:true,locationAfter:mode == .historical ? nil:target.addingTimeInterval(-120))
            try Task.checkCancellation(); guard gen == generation else { return }
            store.ingest(rows.filter { $0.kind != "car_data" && ($0.kind != "location" || mode == .historical || $0.date > target.addingTimeInterval(-120)) })
            if rows.count < 5000 { break }; offset += rows.count
        }
        // Before-GP values may be known from the final endpoint; the UI never exposes current values early.
        let championships = try await cache.read(session:s.id,after:s.end.addingTimeInterval(-1),through:s.end)
        store.ingest(championships.filter { $0.kind.hasPrefix("championship_") })
        store.recordPositionSamples(try await cache.read(session:s.id,after:clock.time.addingTimeInterval(-2),through:clock.time.addingTimeInterval(2),kind:"location"))
        store.currentTime = clock.time
        applyFactualLapStarts()
        store.raceStart.advance(at:clock.time)
        updateQualifying(resetMotion:true)
        if mode == .replay && s.isRace && store.raceStart.hasStarted {
            // Lap records publish completed timing; the race clock still begins on Lap 1.
            for id in Array(store.drivers.keys) { if var driver = store.drivers[id] { driver.currentLap = max(1,driver.currentLap); store.drivers[id] = driver } }
        }
    }
    private func applyFactualLapStarts() {
        guard store.mode == .replay,clock.time>=replayOpeningTime else{return}
        for record in replayLapStarts {
            guard record.start<=clock.time,record.lap>(store.drivers[record.driver]?.currentLap ?? 0) else{continue}
            store.drivers[record.driver]?.currentLap=record.lap
        }
    }
    func recoverHistoricalPositions(at now:Date = Date()) async {
        guard loading.isEmpty,!clock.playing,store.mode == .replay,store.positionDataUnavailable,
              now.timeIntervalSince(positionRecoveryAt)>=60,let session=store.session else{return}
        positionRecoveryAt=now
        let cursor=clock.time,gen=generation
        do {
            let available=try await historical.locationsIfAvailable(session,from:cursor.addingTimeInterval(-2),through:cursor.addingTimeInterval(2))
            guard gen==generation,clock.time==cursor,!clock.playing else{return}
            let samples=try await cache.read(session:session.id,after:cursor.addingTimeInterval(-2),through:cursor.addingTimeInterval(2),kind:"location")
            guard gen==generation,clock.time==cursor,!clock.playing else{return}
            store.recordPositionSamples(samples)
            store.positionDataUnavailable = !available
            store.positionDataMessage = await historical.positionFailure(session.id)
        } catch { /* Keep cached timing and retry on the next interval. */ }
    }
    private func tick(_ elapsed: Double,now: Date) async {
        store.advanceNotices(at:now); advanceFocus(at:now)
        store.presentationSpeed = clock.playing ? clock.speed : 0
        guard loading.isEmpty else { return }
        await recoverHistoricalPositions(at:now)
        if store.mode == .live {
            store.currentTime = now.addingTimeInterval(-displayDelay)
            let ready = buffered.filter { $0.0.addingTimeInterval(displayDelay) <= now }; buffered.removeAll { $0.0.addingTimeInterval(displayDelay) <= now }; store.ingest(ready.map(\.1))
            if store.session?.isQualifying == true {
                for (_,record) in ready where ["drivers","laps","race_control","session_result"].contains(record.kind) {
                    let key=record.kind=="laps" ? "lap:\(record.driver ?? 0):\(record.fields.i("lap_number") ?? 0)":record.id
                    qualifyingLiveRecords[key]=record
                }
                if !ready.isEmpty {qualifyingTimeline=QualifyingTimeline(records:Array(qualifyingLiveRecords.values))}
            }
        } else if clock.playing && (store.mode == .mock || store.mode == .replay) {
            let previous = clock.time; var next = clock; next.advance(elapsed); let gen = generation
            do {
                if store.mode == .mock { store.ingest(mock.filter { $0.date > previous && $0.date <= next.time });store.recordPositionSamples(mock.filter{$0.kind == "location" && $0.date >= previous && $0.date <= next.time.addingTimeInterval(2)}) }
                else if let s = store.session {
                    let positions=try await historical.locationsIfAvailable(s,from:previous,through:next.time.addingTimeInterval(2))
                    let rows = try await cache.read(session:s.id,after:previous,through:next.time)
                    let positionsAhead = try await cache.read(session:s.id,after:previous.addingTimeInterval(-1),through:next.time.addingTimeInterval(2),kind:"location")
                    store.recordPositionSamples(positionsAhead)
                    guard gen == generation, clock.playing, clock.time == previous else { return }; store.ingest(rows.filter { $0.kind != "car_data" });store.positionDataUnavailable = !positions;store.positionDataMessage = await historical.positionFailure(s.id)
                }
                next.speed = clock.speed
                clock = next; store.currentTime = clock.time;applyFactualLapStarts()
            } catch { clock.playing = false; self.error = error.localizedDescription }
        }
        updateQualifying()
        applyTelemetryBuffer()
        if store.selected != nil,now.timeIntervalSince(telemetryAt)>0.2 {telemetryAt=now;scheduleTelemetry()}
    }
    func refreshTelemetry() async {
        guard !Task.isCancelled,let id=store.selected else{return}
        let cursor=store.currentTime,gen=generation
        if store.mode == .mock {store.drivers[id]?.telemetry=MockF1Provider.telemetry(driver:id,time:cursor);return}
        guard store.mode != .live,let session=store.session else{return}
        applyTelemetryBuffer()
        let currentChunk=Int(floor(cursor.timeIntervalSince1970/30))
        // Fetch ahead while playback consumes the current window. A paused replay needs no prefetch.
        let ahead=clock.playing ? max(10,clock.speed*5):0
        let nextChunk=Int(floor(cursor.addingTimeInterval(ahead).timeIntervalSince1970/30))
        guard let chunk=Array(currentChunk...max(currentChunk,nextChunk)).first(where:{!telemetryChunks.contains($0)}) else{return}
        let from=Date(timeIntervalSince1970:Double(chunk)*30-5)
        let through=Date(timeIntervalSince1970:Double(chunk+1)*30)
        func accept(_ rows:[NormalizedRecord]) {
            let retained=telemetryRows.filter{$0.date>=store.currentTime.addingTimeInterval(-35) && $0.date<=store.currentTime.addingTimeInterval(180)}
            telemetryRows=Array(Dictionary((retained+rows).map{($0.id,$0)},uniquingKeysWith:{_,new in new}).values)
            telemetryChunks=telemetryChunks.filter{abs($0-currentChunk)<=6}
            applyTelemetryBuffer()
        }
        do {
            // Existing real samples remain usable even if the service is currently restricted.
            let cached=try await cache.read(session:session.id,after:from,through:through,kind:"car_data",driver:id)
            guard !Task.isCancelled,generation==gen,store.selected==id else{return}
            accept(cached)
            guard Date()>=telemetryRetryAfter else{return}
            telemetryStatus="Loading telemetry…"
            let rows=try await historical.telemetry(session,driver:id,time:Date(timeIntervalSince1970:Double(chunk)*30))
            guard !Task.isCancelled,generation==gen,store.selected==id else{return}
            telemetryStatus=nil
            telemetryChunks.insert(chunk)
            accept(rows)
        } catch {
            guard !Task.isCancelled,generation==gen,store.selected==id else{return}
            if case ProviderError.liveAccess=error {
                telemetryStatus="Telemetry temporarily restricted by OpenF1"
                telemetryRetryAfter=Date().addingTimeInterval(60)
            } else {
                telemetryStatus="Could not load telemetry. Retrying…"
                telemetryRetryAfter=Date().addingTimeInterval(5)
            }
            applyTelemetryBuffer()
        }
    }

    func setInspector(_ value: Bool) { inspector = value; telemetryAt = .distantPast; if store.mode == .live { connectStream() } }
    func verifyCredentials(_ credentials: Credentials) async {
        do { try CredentialVault.save(credentials); await tokens.invalidate(); _ = try await tokens.access(); authStatus = "Authenticated · Sponsor access ready" } catch { authStatus = error.localizedDescription }
    }
    func openLive(_ session: SessionState) {
        cancelMode()
        operation = Task {
            do {
                guard session.isLive() else { throw ProviderError.invalidResponse }
                loading = "Authenticating live access…"; let token = try await tokens.access()
                var active = session
                let meeting = try await historical.fetch("meetings",query:[.init(name:"meeting_key",value:String(session.meeting))],token:token)
                active.title = meeting.first?.s("meeting_name") ?? session.title
                store.reset(active,mode:.live); store.connection.reconnecting = true
                // One REST bootstrap, followed exclusively by MQTT push.
                var referenceLap: [String: JSONValue]?
                for kind in ["drivers","starting_grid","laps","stints","pit","position","intervals","race_control","weather","session_result","championship_drivers","championship_teams"] {
                    if !session.isRace && kind.hasPrefix("championship") { continue }
                    let rows = try await historical.fetch(kind,query:[.init(name:"session_key",value:String(session.id))],token:token)
                    if kind == "laps" { referenceLap = rows.first { ($0.n("lap_duration") ?? 0) > 0 && ($0.i("lap_number") ?? 0) >= 2 && !$0.b("is_pit_out_lap") } }
                    let now = Date(); buffered += rows.map { (now,kind == "pit" ? OpenF1HistoricalProvider.normalizedPit(OpenF1Mapper.map(kind,$0,session:session,received:now)):OpenF1Mapper.map(kind,$0,session:session,received:now)) }
                }
                if let lap = referenceLap, let driver = lap.i("driver_number"), let start = Dates.parse(lap.s("date_start")), let duration = lap.n("lap_duration") {
                    let points = try await historical.fetch("location",query:[.init(name:"session_key",value:String(session.id)),.init(name:"driver_number",value:String(driver)),.init(name:"date>",value:Dates.iso(start)),.init(name:"date<",value:Dates.iso(start.addingTimeInterval(duration)))],token:token)
                    store.track = points.compactMap { f in guard let x = f.n("x"),let y = f.n("y"),x != 0 || y != 0 else { return nil }; return TrackLocationState(x:x,y:y,date:Dates.parse(f.s("date")) ?? start) }
                }
                loading = ""; picker = false; connectStream()
            } catch { loading = ""; self.error = error.localizedDescription }
        }
    }
    private func connectStream() {
        liveTask?.cancel(); guard let s = store.session else { return }; let gen = generation
        liveTask = Task { await live.run(session:s,telemetry:inspector || store.selected != nil,receive: { [weak self] packet in
            guard let self, let rows = try? OpenF1Mapper.rows(packet.data) else { return }
            await MainActor.run {
                guard self.generation == gen else { return }
                for row in rows where row.i("session_key") == s.id {
                    if packet.endpoint == "car_data" && (row.i("driver_number") != self.store.selected) { continue }
                    let mapped = OpenF1Mapper.map(packet.endpoint,row,session:s,received:packet.received)
                    let r = packet.endpoint == "pit" ? OpenF1HistoricalProvider.normalizedPit(mapped):mapped
                    self.buffered.append((packet.received,r))
                    if let sourceDate = Dates.parse(row.s("date")) { self.store.connection.lastReceived = max(self.store.connection.lastReceived ?? .distantPast,min(sourceDate,packet.received)) }
                }
            }
        },status:{ [weak self] connected in guard let self else { return }; await MainActor.run { guard self.generation == gen else { return }; self.store.connection.connected = connected; self.store.connection.reconnecting = !connected } }) }
    }
}
