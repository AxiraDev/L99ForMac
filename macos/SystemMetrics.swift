// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation
import IOKit
import Darwin

struct MacMetrics: Codable {
    let date: Date
    let cpu: Double?
    let gpu: Double?
    let cpuTemperature: Double?
    let gpuTemperature: Double?
    let temperatureSource: String

    static let empty=MacMetrics(date:Date(),cpu:nil,gpu:nil,cpuTemperature:nil,gpuTemperature:nil,temperatureSource:"")
    func packets() throws -> [WirePacket] {
        var calendar=Calendar(identifier:.gregorian)
        calendar.timeZone = .current
        let c=calendar.dateComponents([.year,.month,.day,.hour,.minute,.second,.weekday],from:date)
        func byte(_ value:Double?,limit:Int)->UInt8 {UInt8(max(0,min(limit,Int((value ?? 0).rounded()))))}
        var value=L99Realtime(year:UInt16(c.year ?? 2000),month:UInt8(c.month ?? 1),day:UInt8(c.day ?? 1),
            hour:UInt8(c.hour ?? 0),minute:UInt8(c.minute ?? 0),second:UInt8(c.second ?? 0),weekday:UInt8((c.weekday ?? 1)-1),
            cpu:byte(cpu,limit:100),cpu_temperature:byte(cpuTemperature,limit:125),gpu:byte(gpu,limit:100),
            gpu_temperature:byte(gpuTemperature,limit:125),display_temperature:byte(cpuTemperature,limit:125))
        var bytes=[UInt8](repeating:0,count:256),flags=[UInt8](repeating:0,count:4)
        let count=bytes.withUnsafeMutableBufferPointer { b in flags.withUnsafeMutableBufferPointer { f in
            l99_build_realtime(&value,b.baseAddress!,f.baseAddress!,4)
        }}
        guard count==4 else {throw L99Error.message(T("Не удалось подготовить дату и показатели Mac."))}
        return (0..<4).map { WirePacket(payload:Array(bytes[$0*64..<($0+1)*64]),acknowledgement:flags[$0] != 0) }
    }
}

/// All mutable sampler state, including the lazy sensor client, is lock-protected.
final class MacMetricsSampler: @unchecked Sendable {
    private let lock=NSLock()
    private let host=mach_host_self()
    private var previous:[UInt32]?
    private lazy var thermal=ThermalSensors()
    init() {previous=cpuTicks()}
    deinit {mach_port_deallocate(mach_task_self_,host)}

    func sample() -> MacMetrics {
        lock.lock();defer{lock.unlock()}
        let current=cpuTicks()
        var load:Double?
        if let current,let previous {
            let delta=zip(current,previous).map {UInt64($0 &- $1)}
            let total=delta.reduce(0,+)
            if total>0 {load=100*Double(total-delta[Int(CPU_STATE_IDLE)])/Double(total)}
        }
        previous=current
        let temperatures=thermal.read()
        let cpuValues=temperatures.filter {$0.name.hasPrefix("pACC") || $0.name.hasPrefix("eACC")}.map(\.value)
        let socValues=temperatures.filter {$0.name.hasPrefix("PMGR SOC Die Temp")}.map(\.value)
        let cpu=cpuValues.isEmpty ? socValues:cpuValues
        let gpu=temperatures.filter {$0.name.hasPrefix("GPU MTR Temp")}.map(\.value)
        func mean(_ a:[Double])->Double? {a.isEmpty ? nil:a.reduce(0,+)/Double(a.count)}
        return MacMetrics(date:Date(),cpu:load,gpu:gpuUsage(),cpuTemperature:mean(cpu),gpuTemperature:mean(gpu),
            temperatureSource:cpuValues.isEmpty ? (socValues.isEmpty ? T("Датчики недоступны"):T("Среднее датчиков SoC")):T("Среднее датчиков CPU"))
    }

    private func cpuTicks()->[UInt32]? {
        var info=host_cpu_load_info()
        var count=mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size/MemoryLayout<integer_t>.size)
        let result=withUnsafeMutablePointer(to:&info) {pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) {host_statistics(host,HOST_CPU_LOAD_INFO,$0,&count)}
        }
        guard result==KERN_SUCCESS else{return nil}
        return [info.cpu_ticks.0,info.cpu_ticks.1,info.cpu_ticks.2,info.cpu_ticks.3]
    }

    private func gpuUsage()->Double? {
        var iterator:io_iterator_t=0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOAccelerator"),&iterator)==KERN_SUCCESS else{return nil}
        defer{IOObjectRelease(iterator)}
        var loads:[Double]=[]
        while case let service=IOIteratorNext(iterator),service != 0 {
            defer{IOObjectRelease(service)}
            guard let stats=IORegistryEntryCreateCFProperty(service,"PerformanceStatistics" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? [String:Any] else{continue}
            for key in ["Device Utilization %","GPU Activity(%)","Renderer Utilization %"] {
                if let v=(stats[key] as? NSNumber)?.doubleValue,v.isFinite,(0...100).contains(v) {loads.append(v);break}
            }
        }
        return loads.max()
    }
}

/// Temperature-only matching: this client never subscribes to keyboard input.
/// IOKit exports these sensor APIs, but they are not in the public macOS SDK.
/// Resolve them dynamically so missing APIs produce unavailable readings.
private final class ThermalSensors {
    struct Reading {let name:String;let value:Double}
    typealias Create = @convention(c) (CFAllocator?) -> Unmanaged<CFTypeRef>?
    typealias Match = @convention(c) (CFTypeRef,CFDictionary) -> Int32
    typealias Services = @convention(c) (CFTypeRef) -> Unmanaged<CFArray>?
    typealias Property = @convention(c) (CFTypeRef,CFString) -> Unmanaged<CFTypeRef>?
    typealias Event = @convention(c) (CFTypeRef,Int64,Int32,Int64) -> Unmanaged<CFTypeRef>?
    typealias Value = @convention(c) (CFTypeRef,Int32) -> Double
    private let library:UnsafeMutableRawPointer?
    private var client:CFTypeRef?
    private var entries:[CFTypeRef]=[]
    private var copyServices:Services?
    private var copyProperty:Property?
    private var copyEvent:Event?
    private var getValue:Value?
    init() {
        library=dlopen("/System/Library/Frameworks/IOKit.framework/IOKit",RTLD_LAZY)
        func resolve<T>(_ name:String,_ type:T.Type)->T? {
            guard let library,let address=dlsym(library,name) else{return nil}
            return unsafeBitCast(address,to:type)
        }
        guard let create=resolve("IOHIDEventSystemClientCreate",Create.self),
              let match=resolve("IOHIDEventSystemClientSetMatching",Match.self) else{return}
        copyServices=resolve("IOHIDEventSystemClientCopyServices",Services.self)
        copyProperty=resolve("IOHIDServiceClientCopyProperty",Property.self)
        copyEvent=resolve("IOHIDServiceClientCopyEvent",Event.self)
        getValue=resolve("IOHIDEventGetFloatValue",Value.self)
        client=create(kCFAllocatorDefault)?.takeRetainedValue()
        if let client {_ = match(client,["PrimaryUsagePage":0xff00,"PrimaryUsage":5] as CFDictionary)}
    }
    deinit {entries=[];client=nil;if let library{dlclose(library)}}
    func read()->[Reading] {
        guard let client,let copyServices,let copyProperty,let copyEvent,let getValue else{return []}
        if entries.isEmpty {entries=copyServices(client)?.takeRetainedValue() as? [CFTypeRef] ?? []}
        return entries.compactMap {service in
            guard let name=copyProperty(service,"Product" as CFString)?.takeRetainedValue() as? String,
                  let event=copyEvent(service,15,0,0)?.takeRetainedValue() else{return nil}
            let value=getValue(event,15<<16)
            guard value.isFinite,(1...125).contains(value) else{return nil}
            return Reading(name:name,value:value)
        }
    }
}
