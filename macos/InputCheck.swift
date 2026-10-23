// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import AppKit
import SwiftUI

struct CheckedInput:Identifiable {
    let id:Int
    let seconds:Double
    let mouse:Bool
    let usage:Int
    let down:Bool
    let modifiers:Int
}

/// A bounded, in-memory log. It records observed releases, never synthesizes them.
struct InputCheckLog {
    private(set) var events:[CheckedInput]=[]
    private(set) var heldKeys=Set<Int>()
    private(set) var heldMouse=Set<Int>()
    private(set) var count=0
    private var origin:TimeInterval?
    static func accepts(active:Bool,keyWindow:Bool,focused:Bool)->Bool {active && keyWindow && focused}
    mutating func append(mouse:Bool,usage:Int,down:Bool,modifiers:Int=0,at time:TimeInterval) {
        if origin==nil {origin=time}
        count+=1
        if mouse {if down{heldMouse.insert(usage)}else{heldMouse.remove(usage)}}
        else{if down{heldKeys.insert(usage)}else{heldKeys.remove(usage)}}
        events.append(CheckedInput(id:count,seconds:max(0,time-origin!),mouse:mouse,usage:usage,down:down,modifiers:modifiers))
        if events.count>100 {events.removeFirst(events.count-100)}
    }
}

@MainActor final class InputCheckModel:ObservableObject {
    @Published private(set) var active=false
    @Published private(set) var log=InputCheckLog()
    func start(){log=InputCheckLog();active=true}
    func stop(){active=false}
    func clear(){stop();log=InputCheckLog()}
    func record(mouse:Bool,usage:Int,down:Bool,modifiers:Int=0,at time:TimeInterval) {
        guard active else{return}
        log.append(mouse:mouse,usage:usage,down:down,modifiers:modifiers,at:time)
    }
    func label(_ event:CheckedInput,keys:[PhysicalKey]=[])->String {
        let names=[224:"Ctrl",225:"Shift",226:"Option",227:"Command",228:T("Правый Ctrl"),229:T("Правый Shift"),230:T("Правый Option"),231:T("Правый Command")]
        let name=event.mouse ? ([1:T("Левая кнопка мыши"),2:T("Правая кнопка мыши"),4:T("Средняя кнопка мыши")][event.usage] ?? T("Кнопка мыши \(event.usage)")):(names[event.usage] ?? keys.first{$0.usage==event.usage}?.name ?? T("Клавиша \(event.usage)"))
        return String(format:T("%.3f с · %@ · %@"),event.seconds,name,event.down ? T("нажата"):T("отпущена"))
    }
}

@MainActor struct InputCheckPad:NSViewRepresentable {
    @ObservedObject var model:InputCheckModel
    @Environment(\.locale) private var locale
    func makeNSView(context:Context)->InputCheckPadView {InputCheckPadView(model:model)}
    func updateNSView(_ view:InputCheckPadView,context:Context){let _=locale;view.setAccessibilityLabel(T("Область проверки клавиш и мыши"));view.synchronize()}
    static func dismantleNSView(_ view:InputCheckPadView,coordinator:()){view.uninstall()}
}

@MainActor final class InputCheckPadView:NSView {
    private weak var model:InputCheckModel?
    private var monitor:Any?
    private var focusObserver:NSObjectProtocol?
    init(model:InputCheckModel){
        self.model=model;super.init(frame:.zero)
        setAccessibilityElement(true);setAccessibilityRole(.group)
        setAccessibilityLabel(T("Область проверки клавиш и мыши"))
    }
    required init?(coder:NSCoder){fatalError("Not supported")}
    override var acceptsFirstResponder:Bool {true}
    override func hitTest(_ point:NSPoint)->NSView? {bounds.contains(convert(point,from:superview)) ? self:nil}
    override func viewDidMoveToWindow(){super.viewDidMoveToWindow();synchronize()}
    func synchronize(){
        guard let model,model.active,let window else{uninstall();needsDisplay=true;return}
        if monitor==nil {
            monitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp,.flagsChanged]){[weak self] event in
                guard let self,let model=self.model,
                      InputCheckLog.accepts(active:model.active,keyWindow:self.window?.isKeyWindow==true,focused:self.window?.firstResponder===self) else{return event}
                if event.type == .keyDown,event.keyCode==53 {model.stop();self.uninstall();return nil}
                guard !event.isARepeat,let usage=MacKeys.usages[event.keyCode] else{return nil}
                var down=event.type == .keyDown
                if event.type == .flagsChanged {
                    let flag:NSEvent.ModifierFlags
                    switch usage {case 224,228:flag = .control;case 225,229:flag = .shift;case 226,230:flag = .option;case 227,231:flag = .command;default:return nil}
                    down=event.modifierFlags.contains(flag) && !model.log.heldKeys.contains(usage)
                }
                model.record(mouse:false,usage:usage,down:down,modifiers:Int(event.modifierFlags.rawValue),at:event.timestamp)
                return nil
            }
            focusObserver=NotificationCenter.default.addObserver(forName:NSWindow.didResignKeyNotification,object:window,queue:.main){[weak self] _ in
                MainActor.assumeIsolated {self?.model?.stop();self?.uninstall()}
            }
            window.makeFirstResponder(self)
        }
        needsDisplay=true
    }
    func uninstall(){
        if let monitor{NSEvent.removeMonitor(monitor)};monitor=nil
        if let focusObserver{NotificationCenter.default.removeObserver(focusObserver)};focusObserver=nil
    }
    override func resignFirstResponder()->Bool {model?.stop();uninstall();needsDisplay=true;return true}
    private func mouse(_ event:NSEvent,down:Bool){
        guard let model,InputCheckLog.accepts(active:model.active,keyWindow:window?.isKeyWindow==true,focused:window?.firstResponder===self) else{return}
        guard (0...2).contains(event.buttonNumber) else{return}
        model.record(mouse:true,usage:1<<event.buttonNumber,down:down,at:event.timestamp)
    }
    override func mouseDown(with event:NSEvent){mouse(event,down:true)}
    override func mouseUp(with event:NSEvent){mouse(event,down:false)}
    override func rightMouseDown(with event:NSEvent){mouse(event,down:true)}
    override func rightMouseUp(with event:NSEvent){mouse(event,down:false)}
    override func otherMouseDown(with event:NSEvent){mouse(event,down:true)}
    override func otherMouseUp(with event:NSEvent){mouse(event,down:false)}
    override func draw(_ dirtyRect:NSRect){
        let active=model?.active==true
        (active ? NSColor.systemTeal.withAlphaComponent(0.15):NSColor.controlBackgroundColor).setFill()
        let shape=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:10,yRadius:10);shape.fill()
        (active ? NSColor.systemTeal:NSColor.separatorColor).setStroke();shape.lineWidth=2;shape.stroke()
        let message=active ? T("Проверка активна · наведи курсор сюда для мыши · Esc — остановить"):T("Нажми «Начать проверку событий»")
        let text=NSAttributedString(string:message,attributes:[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.labelColor])
        text.draw(at:NSPoint(x:max(12,(bounds.width-text.size().width)/2),y:max(8,(bounds.height-text.size().height)/2)))
    }
}
