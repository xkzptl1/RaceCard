import SwiftUI
import AppKit

struct FeedView: View {
    let events: [FeedEvent]
    var language: String = "ja"
    var fontSize: CGFloat = 12
    var qualifying = false
    @State private var unread = 0
    @State private var jump = 0
    var body: some View {
        VStack(spacing:6) {
            HStack { Label(L10n.text(qualifying ? "Session feed":"Race feed",language:language),systemImage:"dot.radiowaves.left.and.right").font(.system(size:12,weight:.bold)); Spacer(); if unread > 0 { Button("\(unread) new ↑") { jump += 1 }.accessibilityIdentifier("newEvents") }; Text("NEWEST FIRST").font(.system(size:9)).foregroundStyle(.secondary) }
            if events.isEmpty { ContentUnavailableView(L10n.text(qualifying ? "Waiting for session events":"Waiting for race events",language:language),systemImage:"text.alignleft",description:Text("Events appear when their source timestamp is reached.")).frame(maxHeight:.infinity) }
            else { NativeFeed(events:events,jump:jump,unread:$unread,language:language,fontSize:fontSize).accessibilityIdentifier("eventFeed") }
        }.padding(10).background(.background,in:RoundedRectangle(cornerRadius:12))
    }
}
struct NativeFeed: NSViewRepresentable {
    let events: [FeedEvent]; let jump: Int; @Binding var unread: Int; var language: String = "ja"; var fontSize: CGFloat = 12
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let table = NSTableView(); table.headerView = nil; table.rowHeight = 66; table.intercellSpacing = .zero; table.backgroundColor = .clear; table.selectionHighlightStyle = .none
        let column = NSTableColumn(identifier:.init("event")); column.resizingMask = .autoresizingMask; table.addTableColumn(column); table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; table.delegate = context.coordinator; table.dataSource = context.coordinator
        scroll.documentView = table; context.coordinator.table = table; context.coordinator.scroll = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observer = NotificationCenter.default.addObserver(forName:NSView.boundsDidChangeNotification,object:scroll.contentView,queue:.main) { [weak c = context.coordinator] _ in MainActor.assumeIsolated { c?.scrolled() } }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView,context: Context) { context.coordinator.update(self) }
    @MainActor final class Coordinator: NSObject,NSTableViewDataSource,NSTableViewDelegate {
        var parent: NativeFeed; var events: [FeedEvent] = []; weak var table: NSTableView?; weak var scroll: NSScrollView?; var observer: NSObjectProtocol?; var lastJump = 0; var count = 0
        init(_ parent: NativeFeed) { self.parent = parent }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
        func numberOfRows(in tableView: NSTableView) -> Int { events.count }
        func tableView(_ tableView: NSTableView,viewFor tableColumn: NSTableColumn?,row: Int) -> NSView? {
            let event = events[row]; let id = NSUserInterfaceItemIdentifier("feedCell")
            let cell = (tableView.makeView(withIdentifier:id,owner:self) as? FeedCell) ?? FeedCell(); cell.identifier = id; cell.update(event,language:parent.language,fontSize:parent.fontSize); return cell
        }
        func update(_ new: NativeFeed) {
            let languageChanged = parent.language != new.language || parent.fontSize != new.fontSize
            parent = new; guard let table, let scroll else { return }
            guard events != new.events || lastJump != new.jump || languageChanged else { return }
            let origin = scroll.contentView.bounds.origin.y; let atTop = origin < 4
            let row = max(0,table.row(at:NSPoint(x:1,y:origin+1))); let anchor = events.indices.contains(row) ? events[row].id : nil; let offset = origin - table.rect(ofRow:row).minY
            let oldIDs = Set(events.map(\.id)); let additions = new.events.filter { !oldIDs.contains($0.id) }.count
            let jump = lastJump != new.jump; lastJump = new.jump; events = new.events; table.reloadData(); table.layoutSubtreeIfNeeded()
            if atTop || jump { scroll.contentView.scroll(to:.zero); count = 0 }
            else if let anchor, let index = events.firstIndex(where: { $0.id == anchor }) { scroll.contentView.scroll(to:NSPoint(x:0,y:table.rect(ofRow:index).minY+offset)); count += additions }
            else { scroll.contentView.scroll(to:.zero); count = 0 }
            scroll.reflectScrolledClipView(scroll.contentView); publish()
        }
        func scrolled() { if (scroll?.contentView.bounds.origin.y ?? 0) < 4 { count = 0; publish() } }
        func publish() { let value = count; if parent.unread != value { DispatchQueue.main.async { self.parent.unread = value } } }
    }
}
final class FeedCell: NSTableCellView {
    let icon = NSImageView(); let rail = NSView(); let heading = NSTextField(labelWithString:""); let detail = NSTextField(labelWithString:"")
    override init(frame frameRect: NSRect) { super.init(frame:frameRect); for v in [rail,icon,heading,detail] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }; rail.wantsLayer = true; heading.font = .monospacedSystemFont(ofSize:9,weight:.medium); heading.textColor = .secondaryLabelColor; detail.font = .systemFont(ofSize:11,weight:.medium); detail.lineBreakMode = .byWordWrapping; detail.maximumNumberOfLines = 2
        NSLayoutConstraint.activate([rail.leadingAnchor.constraint(equalTo:leadingAnchor),rail.widthAnchor.constraint(equalToConstant:3),rail.topAnchor.constraint(equalTo:topAnchor,constant:5),rail.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-5),icon.leadingAnchor.constraint(equalTo:leadingAnchor,constant:10),icon.topAnchor.constraint(equalTo:topAnchor,constant:7),icon.widthAnchor.constraint(equalToConstant:12),icon.heightAnchor.constraint(equalToConstant:12),heading.leadingAnchor.constraint(equalTo:leadingAnchor,constant:27),heading.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-6),heading.topAnchor.constraint(equalTo:topAnchor,constant:7),detail.leadingAnchor.constraint(equalTo:heading.leadingAnchor),detail.trailingAnchor.constraint(equalTo:heading.trailingAnchor),detail.topAnchor.constraint(equalTo:heading.bottomAnchor,constant:4)])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func update(_ e: FeedEvent,language: String,fontSize: CGFloat) { icon.image = NSImage(systemSymbolName:EventColor.symbol(e.category),accessibilityDescription:e.category); icon.contentTintColor = NSColor(EventColor.color(e.category)); detail.font = .systemFont(ofSize:fontSize,weight:.semibold); detail.textColor = .labelColor; let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; heading.stringValue = "\(e.lap.map { "L\($0)  " } ?? "")\(f.string(from:e.date))  •  \(L10n.text(e.category,language:language))"; detail.stringValue = e.localizedText(language)
        if e.category == "PIT",let fields=e.facts?.fields,!fields.b("includes_suspension"),let occupancy=PitTimingPresentation(stopDuration:fields.n("stop_duration"),laneDuration:fields.n("lane_duration"),suspended:false).occupancy(language) {
            let value=NSMutableAttributedString(string:e.localizedText(language),attributes:[.font:NSFont.systemFont(ofSize:fontSize,weight:.semibold),.foregroundColor:NSColor.labelColor])
            let range=(value.string as NSString).range(of:occupancy)
            if range.location != NSNotFound {value.addAttributes([.font:NSFont.systemFont(ofSize:max(11,fontSize-1),weight:.regular),.foregroundColor:NSColor.secondaryLabelColor],range:range)}
            detail.attributedStringValue=value
        }
        rail.layer?.backgroundColor = NSColor(EventColor.color(e.category)).cgColor; setAccessibilityLabel("\(heading.stringValue) \(e.localizedText(language))"); toolTip = e.localizedDetail(language) }
}
enum EventColor { static func symbol(_ category:String)->String { switch category {case "SAFETY CAR":return "car.side.fill";case "VSC":return "exclamationmark.triangle.fill";case "PIT","TYRE CHANGE":return "tire";case "FASTEST LAP":return "stopwatch.fill";case "PENALTY","INVESTIGATION":return "exclamationmark.circle.fill";case "CAR STOPPED","RETIRED","MECHANICAL":return "car.side.hill.down.fill";default:return "flag.fill"} }; static func color(_ category: String) -> Color { if category.contains("RED") || category == "MECHANICAL" { return .red }; if ["YELLOW FLAG","DOUBLE YELLOW","SAFETY CAR","VSC"].contains(category) { return .yellow }; if ["GREEN","RESTART","OVERTAKE"].contains(category) { return .green }; if category == "FASTEST LAP" { return .purple }; if ["PIT","TYRE CHANGE"].contains(category) { return .blue }; if ["PENALTY","INVESTIGATION"].contains(category) { return .orange }; return .gray } }
