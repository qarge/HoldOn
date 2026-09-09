// Simulates a real ⌘Q hold: flagsChanged(⌘ down), key down, wait, key up, flagsChanged(⌘ up).
import Cocoa
let seconds = Double(CommandLine.arguments[1]) ?? 0.1
let key = CGKeyCode(CommandLine.arguments.count > 2 ? UInt16(CommandLine.arguments[2])! : 12)
let src = CGEventSource(stateID: .hidSystemState)

func flags(_ down: Bool) {
    let e = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: down)!
    e.type = .flagsChanged
    e.flags = down ? .maskCommand : []
    e.post(tap: .cghidEventTap)
}
func stroke(_ down: Bool) {
    let e = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: down)!
    e.flags = .maskCommand
    e.post(tap: .cghidEventTap)
}

flags(true)
usleep(30_000)
stroke(true)
Thread.sleep(forTimeInterval: seconds)
stroke(false)
usleep(30_000)
flags(false)
