// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation
import AppKit
import IOKit
import IOKit.hid

struct HIDInterface: Identifiable {
    let id: UInt64
    let product: String
    let usagePage: Int
    let usage: Int
    let featureSize: Int
    let inputSize: Int
    let outputSize: Int
    let descriptor: Data
    var isSettings: Bool { usagePage == 0xff13 && usage == 1 && featureSize == 64 }
    var summary: String {
        String(format: "usage %04X:%04X · feature %d · input %d · output %d", usagePage, usage, featureSize, inputSize, outputSize)
    }
}

struct WirePacket {
    let payload: [UInt8]
    let acknowledgement: Bool
}

enum L99Error: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

final class HIDTransport {
    /// Reads registry properties only; never opens/seizes the keyboard or sends reports.
    func scan() -> [HIDInterface] {
        var iterator:io_iterator_t=0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOHIDDevice"),&iterator)==KERN_SUCCESS else{return []}
        defer{IOObjectRelease(iterator)}
        var interfaces=[HIDInterface]()
        while case let service=IOIteratorNext(iterator),service != 0 {
            defer{IOObjectRelease(service)}
            func property(_ key:String)->Any? {IORegistryEntryCreateCFProperty(service,key as CFString,kCFAllocatorDefault,0)?.takeRetainedValue()}
            func integer(_ key:String)->Int {(property(key) as? NSNumber)?.intValue ?? 0}
            guard integer(kIOHIDVendorIDKey)==0x0c45,integer(kIOHIDProductIDKey)==0x800a else{continue}
            var id:UInt64=0
            guard IORegistryEntryGetRegistryEntryID(service,&id)==KERN_SUCCESS else{continue}
            interfaces.append(HIDInterface(id:id,product:property(kIOHIDProductKey) as? String ?? "AULA L99",
                usagePage:integer(kIOHIDPrimaryUsagePageKey),usage:integer(kIOHIDPrimaryUsageKey),
                featureSize:integer(kIOHIDMaxFeatureReportSizeKey),inputSize:integer(kIOHIDMaxInputReportSizeKey),outputSize:integer(kIOHIDMaxOutputReportSizeKey),
                descriptor:property(kIOHIDReportDescriptorKey) as? Data ?? Data()))
        }
        return interfaces.sorted{$0.usagePage<$1.usagePage}
    }
    /// Create a HID client only for an actual transaction, never for status polling.
    static func device(registryID:UInt64)throws->IOHIDDevice {
        let service=IOServiceGetMatchingService(kIOMainPortDefault,IORegistryEntryIDMatching(registryID))
        guard service != 0 else{throw L99Error.message(T("USB-подключение L99 изменилось."))}
        defer{IOObjectRelease(service)}
        guard let device=IOHIDDeviceCreate(kCFAllocatorDefault,service) else{throw L99Error.message(T("Не удалось открыть подключение L99."))}
        return device
    }

    func diagnosticJSON() -> Data {
        let interfaces = scan().map { item -> [String: Any] in
            ["product":item.product, "vendorID":0x0c45, "productID":0x800a,
             "usagePage":item.usagePage, "usage":item.usage, "featureSize":item.featureSize,
             "inputSize":item.inputSize, "outputSize":item.outputSize,
             "reportDescriptor":item.descriptor.map {String(format:"%02x",$0)}.joined(),
             "settingsInterface":item.isSettings]
        }
        return (try? JSONSerialization.data(withJSONObject: ["reportsSent":0,"interfaces":interfaces], options:[.prettyPrinted,.sortedKeys])) ?? Data()
    }

    /// Called for Apply or enabled clock/telemetry sync on the serial worker queue.
    /// A failed ACK aborts the transaction. Never retries writes or flashes firmware.
    func send(_ packets:[WirePacket],expectedRegistryID:UInt64?=nil,cancellation:TransferCancellation?=nil)throws->[String] {
        try cancellation?.check()
        guard !packets.isEmpty else{return []}
        let channel=try SettingsFeatureChannel(expectedRegistryID:expectedRegistryID,cancellation:cancellation)
        return try FeatureTransaction.send(packets,channel:channel,cancellation:cancellation)
    }

}

enum ProtocolCore {
    static func lighting(_ p: Profile) throws -> [WirePacket] {
        try p.deviceConfiguration?.validate()
        let color=NSColor(hex:p.colorHex)
        var packets=try build { bytes,flags in
            l99_build_lighting(UInt8(p.mode),UInt8((color.redComponent*255).rounded()),UInt8((color.greenComponent*255).rounded()),UInt8((color.blueComponent*255).rounded()),UInt8(p.brightness),UInt8(p.speed),UInt8(p.direction),p.colorful ? 1:0,bytes,flags,32)
        }
        if let snapshot=p.deviceConfiguration {
            var data=[UInt8](snapshot.lighting)
            for i in [0,1,2,3,9,10,11,14,15]{data[i]=packets[2].payload[i]}
            data[8]=(data[8]&0xfe)|(packets[2].payload[8]&1)
            packets[2]=WirePacket(payload:data,acknowledgement:false)
        }
        return packets
    }
    static func settings(_ p: Profile) throws -> [WirePacket] {
        try p.deviceConfiguration?.validate()
        var packets=try build { bytes,flags in
            l99_build_settings(p.disableWin ? 1:0,p.disableAltF4 ? 1:0,p.disableAltTab ? 1:0,p.fnToggle ? 1:0,UInt8(p.sleepIndex),UInt8(p.responseLevel),bytes,flags,32)
        }
        if let snapshot=p.deviceConfiguration {
            var data=[UInt8](snapshot.settings)
            for i in 2...5{data[i]=(data[i]&0xfe)|(packets[2].payload[i]&1)}
            for i in [1,6,8,62,63]{data[i]=packets[2].payload[i]}
            packets[2]=WirePacket(payload:data,acknowledgement:false)
        }
        return packets
    }
    static func keymap(_ p: Profile, fnLayer: Bool) throws -> [WirePacket] {
        try MacroMemory.validateAssignments(p)
        try p.deviceConfiguration?.validate()
        let slots=try MacroMemory.slots(p)
        let selected=p.bindings.filter{$0.fnLayer==fnLayer}
        let values=selected.filter{$0.kind != 5}.map { b in
            L99Binding(index:UInt16(b.keyID),kind:UInt8(b.kind),modifiers:UInt8(b.kind==4 ? (b.macroID.flatMap{id in p.macros.first{$0.id==id}.map{MacroAssignments.count(b,macro:$0)}} ?? 1):b.modifiers),usage:UInt16(b.macroID.flatMap{slots[$0]} ?? b.usage))
        }
        var packets=try build { bytes,flags in
            values.withUnsafeBufferPointer {l99_build_keymap($0.baseAddress,$0.count,fnLayer ? 1:0,bytes,flags,32)}
        }
        var table=p.deviceConfiguration.map{[UInt8](fnLayer ? $0.fn:$0.main)} ?? [UInt8](repeating:0,count:576)
        let generated=packets[2..<11].flatMap(\.payload)
        for b in selected {
            let i=b.keyID*4
            var entry=b.kind==0 ? [UInt8](repeating:0,count:4):(b.rawEntry.map{[UInt8]($0)} ?? Array(generated[i..<i+4]))
            if b.kind==4,let id=b.macroID,let slot=slots[id],let macro=p.macros.first(where:{$0.id==id}) {
                entry=MacroAssignments.entry(b,macro:macro,slot:slot)
            }
            table.replaceSubrange(i..<i+4,with:entry)
        }
        table[574]=0xaa;table[575]=0x55
        for i in 0..<9{packets[2+i]=WirePacket(payload:Array(table[i*64..<(i+1)*64]),acknowledgement:false)}
        return packets
    }
    /// The exported assignment stream is the same complete operation sent by Apply.
    static func assignmentUpdate(_ profile:Profile,fnLayer:Bool)throws->[WirePacket] {
        let dependencies=profile.bindings.contains{$0.kind==4 && $0.fnLayer==fnLayer}
            ? try detachedMacroKeymaps(profile)+macros(profile):[]
        return dependencies + (try keymap(profile,fnLayer:fnLayer))
    }
    static func custom(_ p: Profile,keys: [PhysicalKey]) throws -> [WirePacket] {
        try p.deviceConfiguration?.validate()
        let colors=keys.map { key -> L99KeyColor in
            let c=NSColor(hex:p.keyColors[String(key.id)] ?? "000000")
            return L99KeyColor(index:UInt16(key.lightIndex),r:UInt8((c.redComponent*255).rounded()),g:UInt8((c.greenComponent*255).rounded()),b:UInt8((c.blueComponent*255).rounded()))
        }
        var packets=try build {bytes,flags in colors.withUnsafeBufferPointer {l99_build_custom($0.baseAddress,$0.count,UInt8(p.brightness),bytes,flags,128)}}
        if let snapshot=p.deviceConfiguration,let header=packets.firstIndex(where:{$0.payload[0]==4 && $0.payload[1]==0x23}) {
            var light=[UInt8](snapshot.lighting)
            for i in [0,1,2,3,9,10,11,14,15]{light[i]=packets[2].payload[i]}
            light[8]=(light[8]&0xfe)|(packets[2].payload[8]&1)
            packets[2]=WirePacket(payload:light,acknowledgement:false)
            var table=[UInt8](snapshot.custom)
            for (key,color) in zip(keys,colors) where p.keyColors[String(key.id)] != nil {
                let i=Int(color.index)*4;table.replaceSubrange(i..<i+4,with:[UInt8(color.index),color.r,color.g,color.b])
            }
            table[574]=0xaa;table[575]=0x55
            for i in 0..<9{packets[header+1+i]=WirePacket(payload:Array(table[i*64..<(i+1)*64]),acknowledgement:false)}
        }
        return packets
    }
    /// Reconcile existing macro references without applying unrelated key drafts.
    static func detachedMacroKeymaps(_ p:Profile)throws->[WirePacket] {
        guard let snapshot=p.deviceConfiguration else{return []}
        try snapshot.validate()
        let slots=try MacroMemory.slots(p),alive=Set(slots.values),decoded=Set(snapshot.decodedMacroSlots)
        var packets=[WirePacket]()
        for fn in [false,true] {
            var data=[UInt8](fn ? snapshot.fn:snapshot.main),changed=false
            for i in stride(from:0,to:568,by:4) where data[i]==6 && decoded.contains(Int(data[i+1])) {
                var entry=Array(data[i..<i+4])
                if !alive.contains(Int(data[i+1])) {entry=[0,0,0,0]}
                else if let binding=p.bindings.first(where:{$0.keyID==i/4 && $0.fnLayer==fn && $0.kind==4}),
                        let macro=p.macros.first(where:{$0.id==binding.macroID}),slots[macro.id]==Int(data[i+1]) {
                    entry=MacroAssignments.entry(binding,macro:macro,slot:Int(data[i+1]))
                }
                if entry != Array(data[i..<i+4]) {data.replaceSubrange(i..<i+4,with:entry);changed=true}
            }
            if changed {
                var copy=p,raw=snapshot;copy.bindings=[]
                if fn{raw.fn=Data(data)}else{raw.main=Data(data)}
                copy.deviceConfiguration=raw;packets += try keymap(copy,fnLayer:fn)
            }
        }
        return packets
    }
    /// Standalone macro editing must commit after the final macro data block.
    /// Assignment writes already commit at the end of their keymap stream.
    static func macroUpdate(_ p:Profile)throws->[WirePacket] {
        try detachedMacroKeymaps(p)+macros(p)+[WirePacket(payload:DeviceConfiguration.command(0xf0),acknowledgement:true)]
    }
    static func macros(_ p: Profile) throws -> [WirePacket] {
        try MacroMemory.validateForWrite(p)
        try MacroMemory.validateAssignments(p)
        try p.deviceConfiguration?.validate()
        let slots=try MacroMemory.slots(p)
        var records:[L99MacroEvent]=[]
        for macro in p.macros {
            for step in macro.steps {
                let action:UInt8=step.action=="Key down" ? 0:step.action=="Key up" ? 1:step.action=="Mouse down" ? 2:3
                records.append(L99MacroEvent(slot:UInt16(slots[macro.id]!),usage:UInt16(step.usage),delay_ms:UInt16(step.delay),action:action))
            }
        }
        let generated=try build {bytes,flags in records.withUnsafeBufferPointer {l99_build_macros($0.baseAddress,$0.count,100,bytes,flags,128)}}
        let data=try MacroMemory.merge(generated:Data(generated.dropFirst(2).dropLast().flatMap(\.payload)),profile:p)
        var setup=generated[1].payload;setup[8]=UInt8(data.count/64)
        var packets=[generated[0],WirePacket(payload:setup,acknowledgement:true)]
        let bytes=[UInt8](data)
        for i in stride(from:0,to:bytes.count,by:64){packets.append(WirePacket(payload:Array(bytes[i..<i+64]),acknowledgement:false))}
        packets.append(generated.last!);return packets
    }
    private static func build(_ operation: (UnsafeMutablePointer<UInt8>,UnsafeMutablePointer<UInt8>) -> Int32) throws -> [WirePacket] {
        var bytes=[UInt8](repeating:0,count:64*128), flags=[UInt8](repeating:0,count:128)
        let count=bytes.withUnsafeMutableBufferPointer { b in flags.withUnsafeMutableBufferPointer { f in operation(b.baseAddress!,f.baseAddress!) } }
        guard count > 0 && count <= 128 else { throw L99Error.message(T("Параметры не прошли проверку протокола (\(count)).")) }
        return (0..<Int(count)).map { WirePacket(payload:Array(bytes[$0*64..<($0+1)*64]),acknowledgement:flags[$0] != 0) }
    }
}
