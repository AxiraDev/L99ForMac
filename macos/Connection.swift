// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation

struct USBTarget:Equatable,Sendable {
    let registryID:UInt64
    let generation:UInt64
}

/// Main-thread state. A wake invalidates even an unchanged registry ID.
struct USBConnection {
    private(set) var registryID:UInt64?
    private(set) var generation:UInt64=0
    private(set) var sleeping=false
    private(set) var ready=false
    private(set) var reading=false
    private(set) var failures=0
    private(set) var nextRead=Date.distantPast
    var target:USBTarget? {sleeping ? nil:registryID.map{USBTarget(registryID:$0,generation:generation)}}
    func contains(_ target:USBTarget)->Bool {self.target==target}
    @discardableResult mutating func discover(_ id:UInt64?)->Bool {
        guard id != registryID else{return false}
        registryID=id;invalidate();return true
    }
    mutating func sleep(){sleeping=true;invalidate()}
    mutating func wake(){sleeping=false;invalidate()}
    mutating func invalidate() {
        generation &+= 1;ready=false;reading=false;failures=0;nextRead = .distantPast
    }
    mutating func needsRead(){ready=false;reading=false;nextRead = .distantPast}
    mutating func beginRead(now:Date,manual:Bool=false)->USBTarget? {
        guard let target,!reading,manual || (!ready && now>=nextRead) else{return nil}
        reading=true;ready=false;return target
    }
    @discardableResult mutating func readSucceeded(_ target:USBTarget)->Bool {
        guard contains(target),reading else{return false}
        reading=false;ready=true;failures=0;nextRead = .distantPast;return true
    }
    @discardableResult mutating func readFailed(_ target:USBTarget,now:Date,retry:Bool=true)->Bool {
        guard contains(target) else{return false}
        reading=false;ready=false;failures+=1
        nextRead=retry ? now.addingTimeInterval(failures==1 ? 5:failures==2 ? 15:30):.distantFuture
        return true
    }
    func shouldRead(now:Date)->Bool {target != nil && !ready && !reading && now>=nextRead}
}

/// Shared by queued work. Parent invalidation cancels every task on an old USB connection.
final class TransferCancellation:@unchecked Sendable {
    private let lock=NSLock()
    private var reason:String?
    private let parent:TransferCancellation?
    init(parent:TransferCancellation?=nil){self.parent=parent}
    func cancel(_ message:String=T("Операция остановлена.")){lock.lock();reason=message;lock.unlock()}
    var isCancelled:Bool {lock.lock();let own=reason != nil;lock.unlock();return own || parent?.isCancelled == true}
    func check()throws {
        lock.lock();let message=reason;lock.unlock()
        if let message{throw L99Error.message(message)}
        try parent?.check()
    }
}

enum USBOperationKind:Equatable {case keyboard,screen}
final class USBOperation:@unchecked Sendable {
    let kind:USBOperationKind
    let target:USBTarget
    let cancellation:TransferCancellation
    init(_ kind:USBOperationKind,target:USBTarget,parent:TransferCancellation) {
        self.kind=kind;self.target=target;cancellation=TransferCancellation(parent:parent)
    }
}

enum FeatureTransaction {
    static func send(_ packets:[WirePacket],channel:FeatureChannel,cancellation:TransferCancellation?=nil)throws->[String] {
        guard packets.allSatisfy({$0.payload.count==64}) else{throw L99Error.message(T("Неверная длина пакета."))}
        var log=[String]()
        for (i,packet) in packets.enumerated() {
            try cancellation?.check();try channel.write(packet.payload)
            log.append("TX \(i+1): "+packet.payload.map{String(format:"%02x",$0)}.joined())
            if packet.acknowledgement {
                try cancellation?.check();let response=try channel.read()
                guard response.count==64,response[0]==packet.payload[0],response[1]==packet.payload[1],response[3]==1 else{
                    throw L99Error.message(T("L99 не подтвердила команду \(i+1). Передача остановлена; настройки будут прочитаны заново."))
                }
                log.append("ACK \(i+1): "+response.map{String(format:"%02x",$0)}.joined())
            }
        }
        try cancellation?.check();return log
    }
}

/// Derived from the actual outgoing packets, rather than just a successful ACK.
struct ConfigurationWrite {
    let revision:Int
    let committed:Set<String>
    private(set) var regions:[UInt8:Data]=[:]
    init(packets:[WirePacket],revision:Int,committed:Set<String>)throws {
        self.revision=revision;self.committed=committed
        var i=0
        while i<packets.count {
            let p=packets[i].payload
            guard p.count==64 else{throw L99Error.message(T("Неверный размер пакета проверки."))}
            if p[0]==4,[0x13,0x11,0x27,0x17,0x23,0x15].contains(p[1]) {
                let count=Int(p[8])
                guard count>0,i+count<packets.count else{throw L99Error.message(T("Неполная таблица для проверки записи."))}
                regions[p[1]]=Data(packets[(i+1)...(i+count)].flatMap(\.payload));i+=count
            }
            i+=1
        }
        guard !regions.isEmpty else{throw L99Error.message(T("Нет настроек для проверки записи."))}
    }
    func matches(_ raw:DeviceConfiguration)throws->Bool {
        try raw.validate()
        for (code,written) in regions {
            let actual:Data
            switch code {
            case 0x13:
                actual=raw.lighting
                guard written.count==64 else{return false}
                for i in [0,1,2,3,9,10,11] where actual[i] != written[i]{return false}
                if actual[8]&1 != written[8]&1{return false}
            case 0x17:
                actual=raw.settings
                guard written.count==64 else{return false}
                for i in 2...5 where actual[i]&1 != written[i]&1{return false}
                if actual[6] != written[6] || actual[8] != written[8]{return false}
            case 0x15:
                if try MacroMemory.bodies(raw.macros) != MacroMemory.bodies(written){return false}
            case 0x11,0x27,0x23:
                actual=code==0x11 ? raw.main:code==0x27 ? raw.fn:raw.custom
                guard written.count==576,actual.prefix(574)==written.prefix(574) else{return false}
            default:return false
            }
        }
        return true
    }
}

/// Reconcile a fresh device snapshot with edits that have not yet been applied.
enum ProfileReconciliation {
    static func merge(incoming:Profile,draft:Profile,pending:Set<String>)throws->(Profile,Set<String>) {
        var result=incoming,pending=pending
        if pending.contains("lighting") {result.mode=draft.mode;result.colorHex=draft.colorHex;result.brightness=draft.brightness;result.speed=draft.speed;result.direction=draft.direction;result.colorful=draft.colorful}
        if pending.contains("settings") {result.disableWin=draft.disableWin;result.disableAltF4=draft.disableAltF4;result.disableAltTab=draft.disableAltTab;result.fnToggle=draft.fnToggle;result.sleepIndex=draft.sleepIndex;result.responseLevel=draft.responseLevel}
        if pending.contains("custom"){result.keyColors=draft.keyColors}
        if pending.contains("macros") {
            result.macros=draft.macros
            let oldSlots=Set(draft.deviceConfiguration?.decodedMacroSlots ?? [])
            // A macro added on the device since the previous snapshot is not a local deletion.
            for fresh in incoming.macros where !oldSlots.contains(fresh.slot ?? -1) && !result.macros.contains(where:{$0.id==fresh.id}) {
                for i in result.macros.indices where result.macros[i].slot==fresh.slot {result.macros[i].slot=nil}
                result.macros.append(fresh)
            }
        }
        for fn in [false,true] where pending.contains(fn ? "fn":"main") {
            let bindings=draft.bindings.filter{$0.fnLayer==fn}
            result.bindings.removeAll{$0.fnLayer==fn};result.bindings += bindings
            for binding in bindings where binding.kind==4 {
                guard let id=binding.macroID else{throw L99Error.message(T("Локальному назначению не хватает макроса."))}
                if !result.macros.contains(where:{$0.id==id}) {
                    guard let macro=draft.macros.first(where:{$0.id==id}) else{throw L99Error.message(T("Макрос локального назначения отсутствует."))}
                    result.macros.append(macro);pending.insert("macros")
                }
            }
        }
        let nativeIDs=Set(incoming.macros.map(\.id))
        let opaqueSlots:Set<Int>
        if let raw=incoming.deviceConfiguration {opaqueSlots=Set(try MacroMemory.bodies(raw.macros).keys).subtracting(raw.decodedMacroSlots)}else{opaqueSlots=[]}
        var occupied=opaqueSlots
        for m in result.macros where nativeIDs.contains(m.id) {if let slot=m.slot{occupied.insert(slot)}}
        for i in result.macros.indices where !nativeIDs.contains(result.macros[i].id) {
            if let slot=result.macros[i].slot {
                if occupied.contains(slot){result.macros[i].slot=nil}else{occupied.insert(slot)}
            }
        }
        for i in result.bindings.indices where result.bindings[i].kind==4 && !result.macros.contains(where:{$0.id==result.bindings[i].macroID}) {
            result.bindings[i].kind=5;result.bindings[i].macroID=nil
        }
        return (result,pending)
    }
}
