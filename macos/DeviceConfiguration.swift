// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation
import IOKit.hid

protocol FeatureChannel {
    func write(_ report:[UInt8]) throws
    func read() throws -> [UInt8]
}

/// Opens only the vendor settings collection, without seizing keyboard input.
final class SettingsFeatureChannel:FeatureChannel {
    private let device:IOHIDDevice
    private let cancellation:TransferCancellation?
    init(expectedRegistryID:UInt64?=nil,cancellation:TransferCancellation?=nil)throws {
        self.cancellation=cancellation;try cancellation?.check()
        let found=HIDTransport().scan().filter(\.isSettings)
        guard found.count==1,let item=found.first else{throw L99Error.message(T("Для чтения подключи одну L99 по USB."))}
        guard expectedRegistryID==nil || expectedRegistryID==item.id else{throw L99Error.message(T("USB-подключение L99 изменилось. Дождись повторного чтения настроек."))}
        device=try HIDTransport.device(registryID:item.id)
        let status=IOHIDDeviceOpen(device,0)
        guard status==kIOReturnSuccess else{throw L99Error.message(T("Не удалось открыть интерфейс настройки L99."))}
    }
    deinit{IOHIDDeviceClose(device,0)}
    func write(_ report:[UInt8])throws {
        guard report.count==64 else{throw L99Error.message(T("Неверная длина запроса L99."))}
        Thread.sleep(forTimeInterval:0.035);try cancellation?.check()
        let status=report.withUnsafeBufferPointer{IOHIDDeviceSetReport(device,kIOHIDReportTypeFeature,0,$0.baseAddress!,64)}
        guard status==kIOReturnSuccess else{throw L99Error.message(T("L99 отключилась во время обмена настройками."))}
    }
    func read()throws->[UInt8] {
        Thread.sleep(forTimeInterval:0.035);try cancellation?.check()
        var report=[UInt8](repeating:0,count:64),length=64
        let status=report.withUnsafeMutableBufferPointer{IOHIDDeviceGetReport(device,kIOHIDReportTypeFeature,0,$0.baseAddress!,&length)}
        guard status==kIOReturnSuccess,length==64 else{throw L99Error.message(T("Неполный ответ при чтении L99."))}
        try cancellation?.check();return report
    }
}

struct DeviceConfiguration:Codable,Equatable {
    var lighting:Data
    var main:Data
    var fn:Data
    var settings:Data
    var custom:Data
    var macros:Data
    var readAt:Date
    var decodedMacroSlots:[Int]=[]

    static let sections:[(String,UInt8,Int)]=[(T("Подсветка"),0x12,1),(T("Основной слой"),0x10,9),(T("Fn-слой"),0x26,9),(T("Настройки"),0x16,1),(T("Цвета клавиш"),0x22,9),(T("Макросы"),0x14,48)]
    static func command(_ code:UInt8,_ count:Int=0)->[UInt8]{var r=[UInt8](repeating:0,count:64);r[0]=4;r[1]=code;r[8]=UInt8(count);return r}
    static func isACK(_ report:[UInt8],_ code:UInt8)->Bool {report.count==64 && report[0]==4 && report[1]==code && report[3]==1}
    /// Only an enter/read/finish allowlist is used. No configuration data or flash-save command is sent.
    static func read(channel:FeatureChannel,progress:(String)->Void={_ in})throws->DeviceConfiguration {
        func acknowledged(_ code:UInt8)throws->[UInt8] {
            try channel.write(command(code));let response=try channel.read()
            guard isACK(response,code) else{throw L99Error.message(String(format:T("L99 не подтвердила чтение (%02X: %@)."),code,response.prefix(4).map{String(format:"%02X",$0)}.joined(separator:" ")))}
            return response
        }
        var areas=[Data]()
        for (name,opcode,count) in sections {
            progress(name)
            _ = try acknowledged(0x18)
            do {
                try channel.write(command(opcode,count))
                let first=try channel.read()
                guard first.count==64 else{throw L99Error.message(T("Неполный ответ L99."))}
                var blocks=[[UInt8]]()
                // Some read commands return the first data block immediately.
                // Others return an ACK first. Raw data byte 3 is never an ACK status.
                if !isACK(first,opcode){blocks.append(first)}
                while blocks.count<count+1 {blocks.append(try channel.read())}
                guard blocks.allSatisfy({$0.count==64}) else{throw L99Error.message(T("Неполные данные: \(name)."))}
                let end=try acknowledged(2)
                let expected=UInt32(end[4])|UInt32(end[5])<<8|UInt32(end[6])<<16|UInt32(end[7])<<24
                let sum=blocks.flatMap{$0}.reduce(UInt32(0)){$0 &+ UInt32($1)}
                guard sum==expected else{throw L99Error.message(T("Не совпала контрольная сумма: \(name). Настройки не загружены."))}
                // The final block participates in the checksum but lies beyond the requested area.
                areas.append(Data(blocks.prefix(count).flatMap{$0}))
            }catch{
                try? channel.write(command(2));_ = try? channel.read()
                throw error
            }
        }
        return DeviceConfiguration(lighting:areas[0],main:areas[1],fn:areas[2],settings:areas[3],custom:areas[4],macros:areas[5],readAt:Date())
    }
    func validate()throws {
        guard lighting.count==64,settings.count==64,main.count==576,fn.count==576,custom.count==576,macros.count==3072,
              decodedMacroSlots.allSatisfy({(0..<100).contains($0)}),Set(decodedMacroSlots).count==decodedMacroSlots.count else{
            throw L99Error.message(T("Неверный размер сохранённых настроек L99."))
        }
    }
    func decoded(previous:Profile,keys:[PhysicalKey])throws->Profile {
        try validate()
        var result=previous
        var snapshot=self
        let bodies=try MacroMemory.bodies(macros)
        let previousSlots=try MacroMemory.slots(previous)
        var parsed=[LocalMacro]()
        for slot in bodies.keys.sorted() {
            guard let body=bodies[slot],let steps=MacroMemory.steps(body) else{continue}
            let old=previous.macros.first{previousSlots[$0.id]==slot}
            var macro=LocalMacro();macro.slot=slot;macro.steps=steps
            if let old {macro.id=old.id;macro.name=old.name;macro.repeatCount=old.repeatCount}
            else{macro.name=T("Макрос \(slot+1)")}
            parsed.append(macro)
        }
        result.macros=parsed;snapshot.decodedMacroSlots=parsed.compactMap(\.slot)
        let light=[UInt8](lighting)
        if !light.allSatisfy({$0==255}) {
            guard light[0]<=128,light[9]<=5,light[10]<=5,light[11]<=3 else{throw L99Error.message(T("Неизвестные параметры подсветки; исходные данные сохранены только в снимке."))}
            result.mode=Int(light[0]);result.colorHex=light[1...3].map{String(format:"%02X",$0)}.joined()
            result.colorful=light[8]&1 != 0;result.brightness=Int(light[9]);result.speed=Int(light[10]);result.direction=Int(light[11])
        }
        let config=[UInt8](settings)
        guard config[6]<=3,(1...5).contains(config[8]) else{throw L99Error.message(T("Неизвестные параметры сна или отклика L99."))}
        result.disableWin=config[2]&1 != 0;result.disableAltF4=config[3]&1 != 0;result.disableAltTab=config[4]&1 != 0
        result.fnToggle=config[5]&1 != 0;result.sleepIndex=Int(config[6]);result.responseLevel=Int(config[8])
        result.bindings=[]
        for (isFn,table) in [(false,main),(true,fn)] {
            let data=[UInt8](table)
            for key in keys {
                let entry=Array(data[key.id*4..<key.id*4+4])
                if entry==[0,0,0,0]{continue}
                var b=KeyBinding(keyID:key.id,fnLayer:isFn,kind:5);b.rawEntry=Data(entry)
                if entry==[5,3,0,0]{b.kind=1}
                else if entry[0]==2,entry[3]==0 {
                    b.kind=2;b.modifiers=Int(entry[1]);b.usage=Int(entry[2])
                    if b.usage==0,entry[1].nonzeroBitCount==1 {b.usage=224+entry[1].trailingZeroBitCount;b.modifiers=0}
                }else if entry[0]==3,entry[3]==0{b.kind=3;b.usage=Int(entry[1])|Int(entry[2])<<8}
                else if entry[0]==6,entry[2]<=1,entry[3]>=1,let macro=parsed.first(where:{$0.slot==Int(entry[1])}) {
                    b.kind=4;b.macroID=macro.id;b.modifiers=Int(entry[3]);b.usage=Int(entry[1])
                }
                result.bindings.append(b)
            }
        }
        // Counts belong to assignments. A common count is also a useful editor default.
        for i in result.macros.indices {
            let counts=Set(result.bindings.filter{$0.macroID==result.macros[i].id}.map(\.modifiers))
            if counts.count==1,let count=counts.first {result.macros[i].repeatCount=count}
        }
        result.keyColors=[:]
        let colors=[UInt8](custom)
        for key in keys {
            let i=key.lightIndex*4
            if Int(colors[i])==key.lightIndex {result.keyColors[String(key.id)]=colors[i+1...i+3].map{String(format:"%02X",$0)}.joined()}
        }
        result.deviceConfiguration=snapshot
        return result
    }
}

enum MacroAssignments {
    static func count(_ binding:KeyBinding,macro:LocalMacro)->Int {binding.modifiers>0 ? binding.modifiers:macro.repeatCount}
    static func entry(_ binding:KeyBinding,macro:LocalMacro,slot:Int)->[UInt8] {
        let count=count(binding,macro:macro)
        if let raw=binding.rawEntry,raw.count==4,raw[0]==6,Int(raw[1])==slot,Int(raw[3])==count {return [UInt8](raw)}
        return [6,UInt8(slot),count>1 ? 1:0,UInt8(count)]
    }
    static func updateRepeats(from old:Profile,in profile:inout Profile) {
        let changed=Set(profile.macros.filter{m in old.macros.first(where:{$0.id==m.id}).map{$0.repeatCount != m.repeatCount} ?? false}.map(\.id))
        for i in profile.bindings.indices where profile.bindings[i].kind==4 && profile.bindings[i].macroID.map(changed.contains)==true {
            guard let macro=profile.macros.first(where:{$0.id==profile.bindings[i].macroID}) else{continue}
            profile.bindings[i].modifiers=macro.repeatCount
            profile.bindings[i].rawEntry=nil
        }
    }
}

enum MacroMemory {
    static let capacity=3072
    /// Include the index, each occupied body, block padding and the final block.
    static func usedBytes(_ profile:Profile,adding steps:Int=0,to id:UUID?=nil)throws->Int {
        let slots=try slots(profile)
        var sizes=[Int:Int]()
        if let snapshot=profile.deviceConfiguration {
            for (slot,body) in try bodies(snapshot.macros) where !snapshot.decodedMacroSlots.contains(slot) {sizes[slot]=body.count}
        }
        for macro in profile.macros {
            let count=macro.steps.count+(macro.id==id ? steps:0)
            if count>0 {sizes[slots[macro.id]!]=8+count*8}
            else if let snapshot=profile.deviceConfiguration,let slot=macro.slot,
                    let body=try bodies(snapshot.macros)[slot],self.steps(body)?.isEmpty==true {sizes[slot]=body.count}
        }
        return ((400+sizes.values.reduce(0,+)+63)/64+1)*64
    }
    static func canAppend(_ steps:Int,to id:UUID,in profile:Profile)->Bool {
        guard steps>=0,profile.macros.contains(where:{$0.id==id}),profile.macros.reduce(0,{$0+$1.steps.count})+steps<=337 else{return false}
        return (try? usedBytes(profile,adding:steps,to:id)).map{$0<=capacity} ?? false
    }
    static func remainingActions(for id:UUID,in profile:Profile)->Int {
        var low=0,high=337
        while low<high {
            let middle=(low+high+1)/2
            if canAppend(middle,to:id,in:profile){low=middle}else{high=middle-1}
        }
        return low
    }
    static func validateForWrite(_ profile:Profile)throws {
        guard try usedBytes(profile)<=capacity else{throw L99Error.message(T("Макросы не помещаются в память L99 (3072 байта с индексом и служебными блоками)."))}
        let originals=try profile.deviceConfiguration.map{try bodies($0.macros)} ?? [:]
        for macro in profile.macros {
            if let slot=macro.slot,let body=originals[slot],let previous=steps(body),
               previous.map({"\($0.action):\($0.usage):\($0.delay)"})==macro.steps.map({"\($0.action):\($0.usage):\($0.delay)"}) {continue}
            guard macro.steps.allSatisfy({(10...60000).contains($0.delay)}) else{throw L99Error.message(T("Задержки в изменённом макросе должны быть от 10 до 60000 мс."))}
        }
    }

    static func validateAssignments(_ profile:Profile)throws {
        for binding in profile.bindings where binding.kind==4 {
            guard let id=binding.macroID,let macro=profile.macros.first(where:{$0.id==id}),!macro.steps.isEmpty else{
                throw L99Error.message(T("В назначенном макросе нет действий. Добавь действия или убери назначение перед записью."))
            }
        }
    }
    static func bodies(_ data:Data)throws->[Int:Data] {
        guard data.count>=400 else{throw L99Error.message(T("Повреждён индекс макросов."))}
        let b=[UInt8](data);var result=[Int:Data]()
        for slot in 0..<100 {
            let i=slot*4,offset=Int(b[i])|Int(b[i+1])<<8
            if offset==0 || offset==65535 {continue}
            guard b[i+2]==0,b[i+3]==0,offset>=400,offset+8<=b.count else{throw L99Error.message(T("Неизвестный индекс макроса \(slot+1). Чтение остановлено без изменения клавиатуры."))}
            let count=Int(b[offset])|Int(b[offset+1])<<8,end=offset+8+count*4
            guard count<=700,end<=b.count else{throw L99Error.message(T("Макрос \(slot+1) выходит за границы памяти."))}
            result[slot]=Data(b[offset..<end])
        }
        return result
    }
    static func steps(_ body:Data)->[MacroStep]? {
        let b=[UInt8](body)
        guard b.count>=8,(b.count-8)%8==0,b[2..<8].allSatisfy({$0==0}) else{return nil}
        var result=[MacroStep]()
        for i in stride(from:8,to:b.count,by:8) {
            guard b[i]==0,b[i+1]==0,b[i+6]==0,b[i+7]==0x50 else{return nil}
            let action:String
            switch b[i+3]{case 0xb0:action="Key down";case 0x30:action="Key up";case 0x90:action="Mouse down";case 0x10:action="Mouse up";default:return nil}
            if action.hasPrefix("Mouse"),![1,2,4].contains(b[i+2]){return nil}
            let delay=Int(b[i+4])|Int(b[i+5])<<8
            guard delay<=60000 else{return nil}
            result.append(MacroStep(action:action,usage:Int(b[i+2]),delay:delay))
        }
        return result
    }
    /// Stable slots are essential: compacting a sparse device table would retarget keys.
    static func slots(_ p:Profile)throws->[UUID:Int] {
        var occupied=Set<Int>(),editable=Set<Int>(),used=Set<Int>(),result=[UUID:Int]()
        if let snapshot=p.deviceConfiguration {
            occupied=Set(try bodies(snapshot.macros).keys)
            editable=Set(snapshot.decodedMacroSlots)
        }
        for macro in p.macros where macro.slot != nil {
            let slot=macro.slot!
            guard (0..<100).contains(slot),(!occupied.contains(slot) || editable.contains(slot)),used.insert(slot).inserted,result[macro.id]==nil else{throw L99Error.message(T("Повторный или занятый слот макроса."))}
            occupied.insert(slot);result[macro.id]=slot
        }
        for macro in p.macros where macro.slot==nil {
            guard let slot=(0..<100).first(where:{!occupied.contains($0)}) else{throw L99Error.message(T("Все слоты макросов заняты."))}
            occupied.insert(slot);result[macro.id]=slot
        }
        return result
    }
    static func merge(generated:Data,profile:Profile)throws->Data {
        var raw:[Int:Data]=[:],unchanged=Set<Int>()
        if let snapshot=profile.deviceConfiguration {
            raw=try bodies(snapshot.macros)
            for slot in snapshot.decodedMacroSlots {
                if let macro=profile.macros.first(where:{$0.slot==slot}),let body=raw[slot],let previous=steps(body),
                   previous.map({"\($0.action):\($0.usage):\($0.delay)"})==macro.steps.map({"\($0.action):\($0.usage):\($0.delay)"}) {
                    unchanged.insert(slot)
                }else{raw.removeValue(forKey:slot)}
            }
        }
        for (slot,body) in try bodies(generated) where !unchanged.contains(slot){raw[slot]=body}
        var out=[UInt8](repeating:255,count:400)
        for slot in raw.keys.sorted() {
            let offset=out.count
            out[slot*4]=UInt8(offset&255);out[slot*4+1]=UInt8(offset>>8);out[slot*4+2]=0;out[slot*4+3]=0
            out += [UInt8](raw[slot]!)
        }
        let size=((out.count+63)/64+1)*64
        guard size<=3072 else{throw L99Error.message(T("Макросы не помещаются в проверенную область памяти L99. Уменьши число действий."))}
        out += Array(repeating:0,count:size-out.count);out[size-2]=0xaa;out[size-1]=0x55
        return Data(out)
    }
}
