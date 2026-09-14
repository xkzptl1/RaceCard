import SwiftUI

struct SessionPicker: View {
    @Bindable var model: AppModel
    @State private var year = Calendar.current.component(.year,from:Date())
    @State private var filter = ""
    @State private var replay = true
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text("Choose a session").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }
            HStack { Picker("Year",selection:$year) { ForEach(2023...Calendar.current.component(.year,from:Date()),id:\.self) { Text(String($0)).tag($0) } }.frame(width:140); TextField("Search circuit or session",text:$filter).accessibilityIdentifier("sessionSearch"); Toggle("Start at Lap 1",isOn:$replay).toggleStyle(.switch).controlSize(.small) }
            Button("Run offline demo") { model.loadMock(); dismiss() }.accessibilityIdentifier("mockButton")
            if !model.loading.isEmpty { ProgressView(L10n.text(model.loading)).controlSize(.small) }
            if let error = model.error { Text(L10n.failure(error)).font(.caption).foregroundStyle(.orange) }
            List(model.sessions.filter { filter.isEmpty || "\($0.id) \($0.title) \($0.circuit) \($0.type) \(L10n.text($0.title)) \(L10n.text($0.circuit)) \(L10n.text($0.type))".localizedCaseInsensitiveContains(filter) }) { s in
                Button { if s.isLive() { model.openLive(s) } else { model.openHistorical(s,replay:replay) } } label: { HStack { VStack(alignment:.leading) { Text("\(L10n.text(s.title)) · \(L10n.text(s.type))").fontWeight(.medium); Text("\(L10n.text(s.circuit)) · \(s.start.formatted(.dateTime.year().month().day().locale(Locale(identifier:model.language))))").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(s.isLive() ? L10n.text("LIVE · SPONSOR") : s.end < Date() ? "\(s.id)  →" : L10n.text("UPCOMING")).font(.caption.monospaced()) } }.buttonStyle(.plain).accessibilityIdentifier("session-\(s.id)").disabled(s.start > Date().addingTimeInterval(1800))
            }.listStyle(.inset)
        }.padding(20).frame(width:570,height:530).task(id:year) { await model.listSessions(year:year) }.environment(\.locale,Locale(identifier:model.language))
    }
}
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var username = ""
    @State private var password = ""
    @State private var saving = false
    @AppStorage("metadataManifestURL") private var metadataURL=""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            HStack { Text("\(Product.name) Settings").font(.title2.bold()); Spacer(); Button("Done") { dismiss() } }.padding()
            Form {
                Section("OpenF1") { TextField("Username",text:$username); SecureField("Password",text:$password); HStack { Button(L10n.text(saving ? "Checking…" : "Save in Keychain & verify")) { saving = true; Task { await model.verifyCredentials(.init(username:username,password:password)); password = ""; saving = false } }.disabled(saving || username.isEmpty || password.isEmpty); Button("Remove credentials") { do { try CredentialVault.delete(); username = ""; password = ""; model.authStatus = "Credentials removed"; Task { await model.tokens.invalidate() } } catch { model.authStatus = error.localizedDescription } } }; Text(L10n.failure(model.authStatus)).font(.caption).textSelection(.enabled); Text("Live timing needs OpenF1 Sponsor access. Passwords stay in macOS Keychain; access tokens remain in memory.").font(.caption).foregroundStyle(.secondary) }
                Section("Metadata updates") {
                    Text(L10n.text("Active metadata")+": "+model.identities.activeVersion).font(.caption).textSelection(.enabled).accessibilityIdentifier("activeMetadataVersion")
                    TextField("Manifest URL",text:$metadataURL).accessibilityIdentifier("metadataManifestURL")
                    Button("Check for updates") {Task {await model.identities.updateRemote()}}
                    Button("Use previous version") {Task {await model.identities.rollback()}}
                    if let diagnostic=model.identities.diagnostic {Text(diagnostic).font(.caption)}
                }
                Section("Replay") { Picker("Default speed",selection:$model.defaultSpeed) { ForEach([1.0,2,5,10,50],id:\.self) { Text("\(Int($0))×").tag($0) } }; Toggle("Spoiler-free mode",isOn:$model.spoilerFree) }
                Section("Display") { Picker("Language",selection:$model.language) { Text("English").tag("en"); Text("日本語").tag("ja") }.accessibilityIdentifier("languagePicker"); Text("Race events follow your language. Hover to see the source message.").font(.caption).foregroundStyle(.secondary); Picker("Theme",selection:$model.theme) { ForEach(["System","Light","Dark"],id:\.self) { Text(L10n.text($0)).tag($0) } }.accessibilityIdentifier("themePicker"); Picker("Timing precision",selection:$model.precision) { ForEach(1...3,id:\.self) { Text("\($0) decimals").tag($0) } } }
                Section("Live") { HStack { Text("Display delay"); Slider(value:$model.displayDelay,in:0...120,step:1); Text("\(Int(model.displayDelay))s").monospacedDigit() }; Text("All incoming live state is buffered by this delay. Freshness reports the latest source timestamp age.").font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped)
        }.frame(width:540,height:650).environment(\.locale,Locale(identifier:model.language)).task { do { username = try CredentialVault.read()?.username ?? "" } catch { model.authStatus = error.localizedDescription } }
    }
}
struct InspectorView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { VStack(alignment:.leading) { Text(driver.map(DriverNameResolver.full) ?? L10n.text("Driver")).font(.title2.bold()); Text(driver?.team ?? "").foregroundStyle(.secondary) }; Spacer(); Button("Done") { dismiss() }.accessibilityIdentifier("closeInspector") }
            if let d = driver {
                ScrollView {
                    VStack(alignment:.leading,spacing:15) {
                        if let t = d.telemetry {
                            GroupBox("Telemetry · \(t.date.formatted(date:.omitted,time:.standard))") { HStack { metric("SPEED",t.speed.map { "\($0) km/h" }); metric("GEAR",t.gear.map(String.init)); metric("RPM",t.rpm.map(String.init)); metric("THROTTLE",t.throttle.map { "\($0)%" }); metric("BRAKE",t.brake.map { "\($0)%" }); metric("DRS",t.drs.map { [10,12,14].contains($0) ? "ON" : [0,1].contains($0) ? "OFF" : "Code \($0)" }) }.padding(5) }
                        } else { Text("Telemetry appears when selected-driver samples are available.").font(.caption).foregroundStyle(.secondary) }
                        if model.store.session?.isQualifying == true {QualifyingTimingCard(model:model,driver:d,slot:nil)} else if let l = d.lastLap {
                            GroupBox("Laps / sectors") { VStack(alignment:.leading,spacing:9) { HStack { metric("LAST · L\(l.number)",Timing.lap(l.duration,precision:model.precision)); metric("BEST",Timing.lap(d.bestLap?.duration,precision:model.precision)) }; HStack { ForEach(0..<3,id:\.self) { i in metric("S\(i+1)",l.sectors[i].map { String(format:"%.*fs",model.precision,$0) }) } }; HStack { ForEach(0..<3,id:\.self) { i in metric(["INTERMEDIATE 1","INTERMEDIATE 2","SPEED TRAP"][i],l.speeds[i].map { "\(Int($0)) km/h" }) } }; ForEach(0..<3,id:\.self) { i in if !l.segments[i].isEmpty { HStack(spacing:3) { Text("S\(i+1)").font(.caption); ForEach(Array(l.segments[i].enumerated()),id:\.offset) { _,v in RoundedRectangle(cornerRadius:2).fill(v == 2051 ? .purple : v == 2049 ? .green : v == 2048 ? .yellow : .gray).frame(height:7).help("Provider mini-sector status \(v)") } } } } }.padding(5) }
                        }
                        if !d.stints.isEmpty { GroupBox("Stints") { VStack(alignment:.leading,spacing:7) { ForEach(d.stints.sorted { $0.id < $1.id }) { stint in HStack { Text("\(stint.id) · \(L10n.text(stint.compound))").fontWeight(.semibold); Spacer(); Text("L\(stint.start)\(stint.end.flatMap { end in model.store.mode == .historical || model.clock.time >= model.clock.end || end <= d.currentLap ? "–\(end)" : nil } ?? "")"); if let prior = stint.initialAge { Text(L10n.text("Prior usage")+" · \(prior)L") } } }; if let age = d.tyreAge { Text("Current tyre age: \(age) laps").foregroundStyle(.secondary) } }.font(.caption).frame(maxWidth:.infinity,alignment:.leading).padding(5) } }
                        if !d.pits.isEmpty { GroupBox("Pit history") { VStack(alignment:.leading,spacing:7) { ForEach(d.pits) { pit in VStack(alignment:.leading,spacing:3) { Text(model.language == "ja" ? "\(pit.lap)周目":"Lap \(pit.lap)").fontWeight(.semibold); Text(PitTimingPresentation(stopDuration:pit.stopDuration,laneDuration:pit.laneDuration,suspended:pit.intersects(model.store.suspensions)).detail(model.language)).fixedSize(horizontal:false,vertical:true) } } }.font(.caption.monospaced()).padding(5) } }
                    }
                }
            }
        }.padding(20).frame(width:560,height:520).environment(\.locale,Locale(identifier:model.language))
    }
    var driver: DriverState? { model.store.selected.flatMap { model.store.drivers[$0] } }
    func metric(_ label: String,_ value: String?) -> some View { Group { if let value { VStack(alignment:.leading,spacing:5) { Text(L10n.text(label)).font(.system(size:8,weight:.bold)).foregroundStyle(.secondary); Text(L10n.text(value)).font(.system(size:12,weight:.semibold,design:.monospaced)) }.frame(maxWidth:.infinity,alignment:.leading) } } }
}
