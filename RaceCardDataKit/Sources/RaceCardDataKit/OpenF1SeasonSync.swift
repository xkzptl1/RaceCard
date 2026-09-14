import Foundation

public extension OpenF1Sync {
    func synchronizeSeason(_ season:Int,through dateLimit:String,excluding selectedSession:Int,transport:URLSession = .shared,onBatch:@Sendable ([DriverSnapshot]) async -> Void) async throws {
        func fetch(_ url:URL) async throws -> [[String:Any]] {
            let (data,response)=try await transport.data(from:url)
            guard (response as? HTTPURLResponse)?.statusCode==200,let rows=try JSONSerialization.jsonObject(with:data) as? [[String:Any]] else {throw URLError(.badServerResponse)}
            return rows
        }
        let sessions=try await fetch(URL(string:"https://api.openf1.org/v1/sessions?year=\(season)")!)
        let known=Set(snapshots().map(\.sessionKey))
        for session in sessions.sorted(by:{($0["date_start"] as? String ?? "")>($1["date_start"] as? String ?? "")}) {
            try Task.checkCancellation()
            guard let key=session["session_key"] as? Int,key != selectedSession,!known.contains(key),let date=session["date_start"] as? String,date<=dateLimit else {continue}
            let source="https://api.openf1.org/v1/drivers?session_key=\(key)"
            let rows=try await fetch(URL(string:source)!)
            let incoming=rows.compactMap {row -> DriverSnapshot? in
                guard let number=row["driver_number"] as? Int,let name=row["full_name"] as? String,!name.isEmpty else{return nil}
                return .init(identityID:DriverRegistry.stableID(name),season:season,sessionKey:key,meetingKey:session["meeting_key"] as? Int ?? 0,date:date,number:number,fullName:name,acronym:row["name_acronym"] as? String ?? "",team:row["team_name"] as? String ?? "",teamColor:row["team_colour"] as? String ?? "888888",headshotURL:row["headshot_url"] as? String,sourceURL:source)
            }
            try merge(incoming);await onBatch(incoming)
            try await Task.sleep(for:.seconds(3))
        }
    }
}
