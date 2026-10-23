// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import AppKit

/// Standard macOS virtual key locations mapped to USB keyboard usages.
enum MacKeys {
    static let usages:[UInt16:Int]=[
        0:4,1:22,2:7,3:9,4:11,5:10,6:29,7:27,8:6,9:25,11:5,12:20,13:26,14:8,15:21,16:28,17:23,
        18:30,19:31,20:32,21:33,22:35,23:34,24:46,25:38,26:36,27:45,28:37,29:39,30:48,31:18,32:24,33:47,34:12,35:19,36:40,37:15,38:13,39:52,40:14,41:51,42:49,43:54,44:56,45:17,46:16,47:55,48:43,49:44,50:53,51:42,53:41,
        54:231,55:227,56:225,57:57,58:226,59:224,60:229,61:230,62:228,
        65:99,67:85,69:87,71:83,75:84,76:88,78:86,81:103,82:98,83:89,84:90,85:91,86:92,87:93,88:94,89:95,91:96,92:97,
        96:62,97:63,98:64,99:60,100:65,101:66,103:68,105:104,106:107,107:105,109:67,111:69,113:106,114:73,115:74,116:75,117:76,118:61,119:77,120:59,121:78,122:58,123:80,124:79,125:81,126:82
    ]
}

enum MacroChord {
    static func steps(usage:Int,modifiers:Int,delay:Int=50)throws->[MacroStep] {
        guard (4...223).contains(usage),(0...255).contains(modifiers),(10...60000).contains(delay) else{throw L99Error.message(T("Некорректное сочетание или задержка."))}
        let held=(0..<8).filter{modifiers & (1<<$0) != 0}.map{224+$0}
        return held.map{MacroStep(usage:$0,delay:delay)} +
            [MacroStep(usage:usage,delay:delay),MacroStep(action:"Key up",usage:usage,delay:delay)] +
            held.reversed().map{MacroStep(action:"Key up",usage:$0,delay:delay)}
    }
}

/// Tracks press order and reserves one future release for every held key.
struct MacroCapture {
    private(set) var held:[Int]=[]
    mutating func accept(usage:Int,down:Bool,commit:(Int)->Bool)->Bool {
        if down ? held.contains(usage):!held.contains(usage) {return true}
        var next=held
        if down {next.append(usage)}else{next.removeAll{$0==usage}}
        guard commit(next.count) else{return false}
        held=next;return true
    }
    mutating func finish()->[Int] {let keys=Array(held.reversed());held=[];return keys}
}

enum MacroSequence {
    static func releases(for steps:[MacroStep])->[MacroStep] {
        var held:[MacroStep]=[]
        for step in steps {
            let mouse=step.action.hasPrefix("Mouse"),down=step.action.hasSuffix("down")
            held.removeAll{$0.usage==step.usage && $0.action.hasPrefix("Mouse")==mouse}
            if down {held.append(step)}
        }
        return held.reversed().map{MacroStep(action:$0.action.hasPrefix("Mouse") ? "Mouse up":"Key up",usage:$0.usage,delay:10)}
    }
}

@MainActor final class MacroRecorder {
    private var monitor:Any?
    private var focusObservers:[NSObjectProtocol]=[]
    private var previous:TimeInterval=0
    private var capture=MacroCapture()
    private var record:((Int,Bool,Int,Int)->Bool)?
    var stopped:(()->Void)?
    func start(record:@escaping (Int,Bool,Int,Int)->Bool) {
        stop();self.record=record;previous=ProcessInfo.processInfo.systemUptime
        for name in [NSApplication.didResignActiveNotification,NSWindow.didResignKeyNotification] {
            focusObservers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main){[weak self] _ in
                MainActor.assumeIsolated {self?.stop();self?.stopped?()}
            })
        }
        monitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp,.flagsChanged]){[weak self] event in
            guard let self else{return event}
            if event.keyCode==53 && event.type == .keyDown {self.stop();self.stopped?();return nil}
            guard !event.isARepeat,let usage=MacKeys.usages[event.keyCode] else{return event}
            var down=event.type == .keyDown
            if event.type == .flagsChanged {
                let flag:NSEvent.ModifierFlags
                switch usage {case 224,228:flag = .control;case 225,229:flag = .shift;case 226,230:flag = .option;case 227,231:flag = .command
                case 57:
                    if !self.append(57,true) || !self.append(57,false) {self.stop();self.stopped?()}
                    return nil
                default:return event}
                down=event.modifierFlags.contains(flag) && !self.capture.held.contains(usage)
            }else{
                // Some input sources attach flags without separate modifier events.
                for (flag,left,right):(NSEvent.ModifierFlags,Int,Int) in [(.control,224,228),(.shift,225,229),(.option,226,230),(.command,227,231)] {
                    if event.modifierFlags.contains(flag) {
                        if !self.capture.held.contains(left) && !self.capture.held.contains(right),!self.append(left,true) {self.stop();self.stopped?();return nil}
                    }else{
                        for key in [left,right] where self.capture.held.contains(key) {
                            if !self.append(key,false) {self.stop();self.stopped?();return nil}
                        }
                    }
                }
            }
            if !self.append(usage,down) {self.stop();self.stopped?()}
            return nil
        }
    }
    private func append(_ usage:Int,_ down:Bool)->Bool {
        let now=ProcessInfo.processInfo.systemUptime
        let delay=Int(min(60000,max(10,(now-previous)*1000)))
        let accepted=capture.accept(usage:usage,down:down){reserved in record?(usage,down,delay,reserved) ?? false}
        if accepted {previous=now};return accepted
    }
    func stop(){
        if let monitor{NSEvent.removeMonitor(monitor)};monitor=nil
        for observer in focusObservers {NotificationCenter.default.removeObserver(observer)};focusObservers=[]
        let release=record,keys=capture.finish();record=nil
        for (i,usage) in keys.enumerated() {_ = release?(usage,false,10,keys.count-i-1)}
    }
}

/// One key, only inside this application's window and after an explicit button press.
@MainActor final class KeySelectionRecorder {
    private var monitor:Any?
    func start(selected:@escaping(Int)->Void,cancelled:@escaping()->Void) {
        stop()
        monitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.flagsChanged]){[weak self] event in
            guard let self else{return event}
            guard !event.isARepeat else{return nil}
            if event.type == .keyDown,event.keyCode==53 {self.stop();cancelled();return nil}
            guard let usage=MacKeys.usages[event.keyCode] else{return event}
            if event.type == .flagsChanged {
                let flag:NSEvent.ModifierFlags
                switch usage {case 224,228:flag = .control;case 225,229:flag = .shift;case 226,230:flag = .option;case 227,231:flag = .command;default:return event}
                guard event.modifierFlags.contains(flag) else{return nil}
            }
            self.stop();selected(usage);return nil
        }
    }
    func stop(){if let monitor {NSEvent.removeMonitor(monitor)};monitor=nil}
}
