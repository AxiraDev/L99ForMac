// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation
import IOKit.hid

final class MusicSession: @unchecked Sendable {
    let capture=SystemAudioCapture()
    let output:MusicHIDOutput
    let target:USBTarget
    let connection:TransferCancellation
    let cancellation:TransferCancellation
    init(target:USBTarget,connection:TransferCancellation) {
        self.target=target;self.connection=connection;cancellation=TransferCancellation(parent:connection)
        output=MusicHIDOutput(registryID:target.registryID,cancellation:connection)
    }
    private let lock=NSLock()
    private var cancelled=false
    var isCancelled:Bool {lock.lock();defer{lock.unlock()};return cancelled}
    func cancel(){lock.lock();cancelled=true;lock.unlock();cancellation.cancel()}
}

struct MusicPalette:Identifiable {
    let id:Int
    let name:String
    static var all:[MusicPalette] {[
        .init(id:1,name:T("Зелёный → жёлтый → красный")),.init(id:2,name:T("Радуга")),
        .init(id:3,name:T("Обратная радуга")),.init(id:4,name:T("Градиент")),.init(id:5,name:T("Смена спектра")),
        .init(id:6,name:T("Белый")),.init(id:7,name:T("Красный")),.init(id:8,name:T("Оранжевый")),
        .init(id:9,name:T("Жёлтый")),.init(id:10,name:T("Зелёный")),.init(id:11,name:T("Голубой"))
    ]}
}

/// Confined to AppModel.queue together with all other keyboard writes.
final class MusicHIDOutput: @unchecked Sendable {
    private var device:IOHIDDevice?
    private let registryID:UInt64
    private let connection:TransferCancellation
    init(registryID:UInt64,cancellation:TransferCancellation){self.registryID=registryID;self.connection=cancellation}
    private(set) var framesSent=0
    deinit {close()}
    static func packets(_ levels:[UInt8],foreground:Int,background:Int,brightness:Int)throws->[WirePacket] {
        guard levels.count==18,(0...11).contains(foreground),(0...11).contains(background),(0...100).contains(brightness) else{throw L99Error.message(T("Неверные параметры музыкального эффекта."))}
        var bytes=[UInt8](repeating:0,count:256),flags=[UInt8](repeating:0,count:4)
        let count=bytes.withUnsafeMutableBufferPointer {b in flags.withUnsafeMutableBufferPointer {f in
            levels.withUnsafeBufferPointer {l99_build_music($0.baseAddress!,UInt8(foreground),UInt8(background),UInt8(brightness),b.baseAddress!,f.baseAddress!,4)}
        }}
        guard count==4 else{throw L99Error.message(T("Не удалось подготовить музыкальные уровни."))}
        return (0..<4).map{WirePacket(payload:Array(bytes[$0*64..<($0+1)*64]),acknowledgement:flags[$0] != 0)}
    }
    func send(_ levels:[UInt8],foreground:Int,background:Int,brightness:Int,cancellation:TransferCancellation?=nil)throws {
        try connection.check();try cancellation?.check()
        if device==nil {
            let found=HIDTransport().scan().filter(\.isSettings)
            guard found.count==1,let item=found.first else{throw L99Error.message(T("Для музыкального эффекта подключи одну L99 по USB."))}
            guard item.id==registryID else{throw L99Error.message(T("Подключение L99 изменилось. Запусти музыку заново."))}
            let opened=try HIDTransport.device(registryID:item.id)
            let result=IOHIDDeviceOpen(opened,IOOptionBits(kIOHIDOptionsTypeNone))
            guard result==kIOReturnSuccess else{throw L99Error.message(String(format:T("Не удалось открыть L99: 0x%08X"),result))}
            device=opened
        }
        guard let device else{return}
        for (index,packet) in try Self.packets(levels,foreground:foreground,background:background,brightness:brightness).enumerated() {
            // Short streaming delays, with at most one repeat of a command on FF.
            // Raw level data must never be retried or interpreted as an ACK.
            var confirmed=false
            var lastAck:UInt8=0
            for attempt in 0..<2 {
                Thread.sleep(forTimeInterval:0.005);try connection.check();try cancellation?.check()
                let sent=packet.payload.withUnsafeBufferPointer{IOHIDDeviceSetReport(device,kIOHIDReportTypeFeature,0,$0.baseAddress!,64)}
                guard sent==kIOReturnSuccess else{throw L99Error.message(T("L99 отключилась во время музыкальной передачи."))}
                if !packet.acknowledgement {confirmed=true;break}
                Thread.sleep(forTimeInterval:0.005);try connection.check();try cancellation?.check()
                var response=packet.payload,length=64
                let read=response.withUnsafeMutableBufferPointer{IOHIDDeviceGetReport(device,kIOHIDReportTypeFeature,0,$0.baseAddress!,&length)}
                guard read==kIOReturnSuccess,length==64 else{throw L99Error.message(T("L99 не ответила на музыкальный кадр."))}
                lastAck=response[3]
                if response[0]==packet.payload[0],response[1]==packet.payload[1],response[3]==1 {confirmed=true;break}
                if response[3] != 0xff || attempt==1 {break}
            }
            guard confirmed else{throw L99Error.message(String(format:T("L99 не подтвердила музыкальный пакет %d (статус %02X). Передача остановлена."),index+1,lastAck))}
        }
        framesSent+=1
    }
    func close() {if let device {IOHIDDeviceClose(device,IOOptionBits(kIOHIDOptionsTypeNone));self.device=nil}}
}
