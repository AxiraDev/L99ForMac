// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation
import IOKit
import Darwin

enum ScreenDestination: String, CaseIterable, Identifiable {
    case photo="Photo Frame",background="Фон рабочего стола",animation="GIF"
    var id: Self {self}
    var address: UInt32 {switch self {case .photo:return 0x041e0000;case .background:return 0x04180000;case .animation:return 0x04240000}}
    var capacity: Int {self == .animation ? 200*307220:0x60000}
}

struct DisplayEndpoint {let path:String;let registryID:UInt64}

/// The display is a second USB device, separate from the keyboard's HID interfaces.
final class DisplayTransport {
    private var fd: Int32 = -1
    private var previous=termios()
    private var received=[UInt8]()
    private let cancellation:TransferCancellation?
    static func port()->String?{endpoint()?.path}
    static func endpoint() -> DisplayEndpoint? {
        var iterator:io_iterator_t=0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,IOServiceMatching("IOSerialBSDClient"),&iterator)==KERN_SUCCESS else{return nil}
        defer{IOObjectRelease(iterator)}
        var paths=[DisplayEndpoint]()
        while case let service=IOIteratorNext(iterator),service != 0 {
            defer{IOObjectRelease(service)}
            guard let path=IORegistryEntryCreateCFProperty(service,"IOCalloutDevice" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? String else{continue}
            var parent=service
            IOObjectRetain(parent)
            defer{IOObjectRelease(parent)}
            while parent != 0 {
                let vendor=IORegistryEntryCreateCFProperty(parent,"idVendor" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? NSNumber
                let product=IORegistryEntryCreateCFProperty(parent,"idProduct" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() as? NSNumber
                if vendor?.intValue==0xeeef && product?.intValue==0x268a {
                    var registryID:UInt64=0;IORegistryEntryGetRegistryEntryID(service,&registryID)
                    paths.append(DisplayEndpoint(path:path,registryID:registryID));break
                }
                var next:io_registry_entry_t=0
                guard IORegistryEntryGetParentEntry(parent,kIOServicePlane,&next)==KERN_SUCCESS else{break}
                IOObjectRelease(parent);parent=next
            }
        }
        return paths.count==1 ? paths[0]:nil
    }
    init(expectedRegistryID:UInt64?=nil,cancellation:TransferCancellation?=nil) throws {
        self.cancellation=cancellation;try cancellation?.check()
        guard let endpoint=Self.endpoint() else{throw L99Error.message(T("Не найден USB-порт экрана L99. Подключи клавиатуру кабелем."))}
        guard expectedRegistryID==nil || expectedRegistryID==endpoint.registryID else{throw L99Error.message(T("USB-подключение экрана изменилось. Начни загрузку заново."))}
        fd=Darwin.open(endpoint.path,O_RDWR|O_NOCTTY|O_NONBLOCK)
        guard fd>=0 else{throw L99Error.message(T("Не удалось открыть экран: \(String(cString:strerror(errno)))."))}
        guard tcgetattr(fd,&previous)==0 else{Darwin.close(fd);fd = -1;throw L99Error.message(T("Не удалось прочитать параметры экрана."))}
        var config=previous;cfmakeraw(&config)
        config.c_cflag=tcflag_t(CS8|CREAD|CLOCAL)
        cfsetispeed(&config,speed_t(B115200));cfsetospeed(&config,speed_t(B115200))
        guard tcsetattr(fd,TCSANOW,&config)==0 else{Darwin.close(fd);fd = -1;throw L99Error.message(T("Не удалось настроить USB-порт экрана."))}
        tcflush(fd,TCIOFLUSH)
    }
    deinit {if fd>=0 {tcsetattr(fd,TCSANOW,&previous);Darwin.close(fd)}}
    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var value:UInt16=0xffff
        for b in bytes {value ^= UInt16(b);for _ in 0..<8{value=(value>>1) ^ (value&1 != 0 ? 0xa001:0)}}
        return value
    }
    static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var value:UInt32=0
        for b in bytes {value ^= UInt32(b);for _ in 0..<8{value=(value>>1) ^ (value&1 != 0 ? 0xedb88320:0)}}
        return value
    }
    static func be(_ number:UInt32)->[UInt8] {[(UInt8(truncatingIfNeeded:number>>24)),UInt8(truncatingIfNeeded:number>>16),UInt8(truncatingIfNeeded:number>>8),UInt8(truncatingIfNeeded:number)]}
    static func number(_ bytes:ArraySlice<UInt8>)->UInt32 {bytes.reduce(0){($0<<8)|UInt32($1)}}
    private func write(_ bytes:[UInt8]) throws {
        let deadline=ProcessInfo.processInfo.systemUptime+3
        var offset=0
        while offset<bytes.count {
            try cancellation?.check()
            let count=bytes.withUnsafeBytes{Darwin.write(fd,$0.baseAddress!.advanced(by:offset),bytes.count-offset)}
            if count>0 {offset+=count;continue}
            guard errno==EAGAIN || errno==EINTR else{throw L99Error.message(T("USB-экран отключён при отправке."))}
            guard ProcessInfo.processInfo.systemUptime<deadline else{throw L99Error.message(T("Экран не принимает данные."))}
            var descriptor=pollfd(fd:fd,events:Int16(POLLOUT),revents:0);_ = poll(&descriptor,1,25)
        }
    }
    private func response(timeout:Double) throws -> [UInt8] {
        let deadline=ProcessInfo.processInfo.systemUptime+timeout
        while ProcessInfo.processInfo.systemUptime<deadline {
            try cancellation?.check()
            while received.count>=3 {
                if received[0] != 0x5a || received[1] != 0xa5 {received.removeFirst();continue}
                let length=Int(received[2]);guard (3...64).contains(length) else{throw L99Error.message(T("Экран вернул неверную длину ответа."))}
                if received.count<length+3{break}
                let frame=Array(received.prefix(length+3));received.removeFirst(length+3)
                let body=Array(frame[3..<(frame.count-2)])
                let crc=UInt16(frame[frame.count-2])|UInt16(frame[frame.count-1])<<8
                guard Self.crc16(body)==crc else{throw L99Error.message(T("Ошибка контрольной суммы ответа экрана."))}
                return body
            }
            var descriptor=pollfd(fd:fd,events:Int16(POLLIN),revents:0)
            let result=poll(&descriptor,1,25)
            if result>0 {
                guard descriptor.revents & Int16(POLLHUP|POLLERR|POLLNVAL)==0 else{throw L99Error.message(T("USB-экран отключён."))}
                var buffer=[UInt8](repeating:0,count:4096)
                let count=Darwin.read(fd,&buffer,buffer.count)
                if count>0{received += buffer.prefix(count)}
                else if count==0 || (errno != EAGAIN && errno != EINTR){throw L99Error.message(T("USB-экран отключён при чтении."))}
            }
        }
        throw L99Error.message(T("Экран не подтвердил запись. Переподключи USB и повтори загрузку."))
    }
    private func request(_ command:UInt8,address:UInt32,data:[UInt8]) throws -> [UInt8] {
        let body=[command]+Self.be(address)+data
        let length=body.count+2
        let crc=Self.crc16(body)
        let frame:[UInt8]=[0x5a,0xa5,UInt8((length>>16)&255),UInt8((length>>8)&255),UInt8(length&255)]+body+[UInt8(crc&255),UInt8(crc>>8)]
        try write(frame)
        let ack=try response(timeout:3)
        guard ack==[command,0xff] else{throw L99Error.message(T("Экран отклонил команду \(command): \(ack)."))}
        let result=try response(timeout:3)
        guard result.count>=5,result[0]==command,Self.number(result[1..<5])==address else{throw L99Error.message(T("Экран подтвердил другую область изображения."))}
        return result
    }
    func upload(_ data:Data,to destination:ScreenDestination,progress:(Double)->Void) throws -> [String] {
        guard data.count>11,data.count<=destination.capacity else{throw L99Error.message(T("Изображение не помещается в память \(destination.rawValue)."))}
        let bytes=[UInt8](data)
        var checks=0
        for base in stride(from:0,to:bytes.count,by:0x20000) {
            try cancellation?.check()
            let end=min(base+0x20000,bytes.count)
            for offset in stride(from:base,to:end,by:2048) {
                let next=min(offset+2048,end)
                _ = try request(0x64,address:destination.address+UInt32(offset),data:Array(bytes[offset..<next]))
                progress(Double(next)/Double(bytes.count)*0.98)
            }
            let result=try request(0x66,address:destination.address+UInt32(base),data:Self.be(UInt32(end-base)))
            guard result.count==9,Self.number(result[5..<9])==Self.crc32(bytes[base..<end]) else{throw L99Error.message(T("Проверка записанной картинки не прошла. Повтори загрузку."))}
            checks+=1
        }
        try cancellation?.check();progress(1)
        return ["DISPLAY: \(destination.rawValue), \(bytes.count) bytes, \(checks) memory CRC checks passed."]
    }
}
