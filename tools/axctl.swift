// axctl — minimal AX fallback CLI (replaces blocked osascript/System Events route)
// Subcommands:
//   list <app|pid>              — windows with logical frames
//   tree <app|pid> [depth]      — UI tree (default depth 2)
//   press <app|pid> <title>     — find element by title, perform AXPress
//   actions <app|pid> <title>   — list available actions of matched element
//   activate <app>              — bring app to front (NSRunningApplication)
import AppKit
import ApplicationServices

func resolveTarget(_ arg: String) -> (pid: pid_t, name: String)? {
    if let pid = Int32(arg), let app = NSRunningApplication(processIdentifier: pid) {
        return (pid, app.localizedName ?? "?")
    }
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == arg }) {
        return (app.processIdentifier, app.localizedName ?? arg)
    }
    // case-insensitive localized-name fallback
    let lower = arg.lowercased()
    if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName?.lowercased() == lower }) {
        return (app.processIdentifier, app.localizedName ?? arg)
    }
    return nil
}

func attrStr(_ el: AXUIElement, _ attr: CFString) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr, &v) == .success else { return nil }
    return v as? String
}

func frameOf(_ el: AXUIElement) -> CGRect? {
    var p: CFTypeRef?, s: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &p) == .success,
          AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &s) == .success,
          let pa = p, let sa = s,
          CFGetTypeID(pa) == AXValueGetTypeID(), CFGetTypeID(sa) == AXValueGetTypeID() else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(unsafeBitCast(pa, to: AXValue.self), .cgPoint, &pt)
    AXValueGetValue(unsafeBitCast(sa, to: AXValue.self), .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}

func children(_ el: AXUIElement) -> [AXUIElement] {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &v) == .success,
          let arr = v as? [AXUIElement] else { return [] }
    return arr
}

func printTree(_ el: AXUIElement, depth: Int, maxDepth: Int, path: String, counter: inout Int) {
    guard depth <= maxDepth else { return }
    counter += 1
    let role = attrStr(el, kAXRoleAttribute as CFString) ?? "?"
    let title = attrStr(el, kAXTitleAttribute as CFString) ?? ""
    let val = attrStr(el, kAXValueAttribute as CFString) ?? ""
    let desc = attrStr(el, kAXDescriptionAttribute as CFString) ?? ""
    var frameDesc = ""
    if let f = frameOf(el) { frameDesc = " frame=(\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width))x\(Int(f.height)))" }
    let info = [title, desc, val].filter { !$0.isEmpty }.joined(separator: " | ")
    print(String(repeating: "  ", count: depth) + "[\(path)] <\(role)> \(info)\(frameDesc)")
    for (i, c) in children(el).enumerated() {
        printTree(c, depth: depth + 1, maxDepth: maxDepth, path: "\(path)/\(i)", counter: &counter)
    }
}

func findFirst(_ el: AXUIElement, title: String, path: String) -> (el: AXUIElement, path: String)? {
    let candidates = [attrStr(el, kAXTitleAttribute as CFString),
                      attrStr(el, kAXDescriptionAttribute as CFString),
                      attrStr(el, kAXValueAttribute as CFString)]
    if candidates.contains(where: { $0?.localizedCaseInsensitiveContains(title) == true }) {
        return (el, path)
    }
    for (i, c) in children(el).enumerated() {
        if let hit = findFirst(c, title: title, path: "\(path)/\(i)") { return hit }
    }
    return nil
}

func appElement(_ t: (pid: pid_t, name: String)) -> AXUIElement { AXUIElementCreateApplication(t.pid) }

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("usage: axctl <list|tree|press|actions|activate> <app|pid> [arg]")
    exit(2)
}
let cmd = args[1], targetArg = args[2]

if cmd == "activate" {
    guard let t = resolveTarget(targetArg) else { print("APP-NOT-RUNNING"); exit(1) }
    NSRunningApplication(processIdentifier: t.pid)?.activate()
    print("activated \(t.name)")
    exit(0)
}

guard let t = resolveTarget(targetArg) else { print("APP-NOT-RUNNING"); exit(1) }
let appEl = appElement(t)

switch cmd {
case "list":
    var ref: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(appEl, kAXWindowsAttribute as CFString, &ref)
    guard err == .success else { print("AX-ERR \(err.rawValue)"); exit(1) }
    let wins = (ref as? [AXUIElement]) ?? []
    print("windows=\(wins.count)")
    for w in wins {
        let t = attrStr(w, kAXTitleAttribute as CFString) ?? "?"
        let f = frameOf(w).map { " frame=(\(Int($0.origin.x)),\(Int($0.origin.y)),\(Int($0.width))x\(Int($0.height)))" } ?? ""
        print("  '\(t)'\(f)")
    }
case "tree":
    let depth = args.count > 3 ? (Int(args[3]) ?? 2) : 2
    var counter = 0
    for c in children(appEl) { printTree(c, depth: 1, maxDepth: depth, path: "w", counter: &counter) }
case "actions", "press":
    guard args.count >= 4 else { print("need title arg"); exit(2) }
    guard let hit = findFirst(appEl, title: args[3], path: "w") else { print("ELEMENT-NOT-FOUND"); exit(1) }
    var names: CFArray?
    AXUIElementCopyActionNames(hit.el, &names)
    let acts = (names as? [String]) ?? []
    if cmd == "actions" { print("matched path=\(hit.path) actions=\(acts)") }
    else {
        guard acts.contains("AXPress") else { print("NO-AXPRESS actions=\(acts)"); exit(1) }
        let perr = AXUIElementPerformAction(hit.el, "AXPress" as CFString)
        print(perr == .success ? "PRESSED path=\(hit.path)" : "PRESS-ERR \(perr.rawValue)")
    }
default:
    print("unknown cmd"); exit(2)
}