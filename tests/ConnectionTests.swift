// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation

private func check(_ value:Bool,_ message:String)throws {if !value{throw L99Error.message("TEST FAILED: "+message)}}
private func mustFail(_ operation:()throws->Void)throws {do{try operation()}catch{return};throw L99Error.message("TEST FAILED: expected failure")}
private func reply(_ opcode:UInt8)->[UInt8]{var p=DeviceConfiguration.command(opcode);p[3]=1;return p}
private final class TransactionChannel:FeatureChannel {
    var writes=[[UInt8]](),replies:[[UInt8]],onWrite:(Int)->Void={_ in}
    init(_ replies:[[UInt8]]){self.replies=replies}
    func write(_ report:[UInt8])throws {writes.append(report);onWrite(writes.count)}
    func read()throws->[UInt8]{guard !replies.isEmpty else{throw L99Error.message("Missing fake ACK")};return replies.removeFirst()}
}
private func emptySnapshot()->DeviceConfiguration {
    var light=Data(repeating:0,count:64);light[9]=5;light[10]=3
    var settings=Data(repeating:0,count:64);settings[6]=2;settings[8]=5
    return DeviceConfiguration(lighting:light,main:Data(repeating:0,count:576),fn:Data(repeating:0,count:576),settings:settings,custom:Data(repeating:0,count:576),macros:Data(repeating:255,count:3072),readAt:Date())
}
private func macroMemory(_ entries:[Int:Data])->Data {
    var data=Data(repeating:255,count:3072),offset=400
    for slot in entries.keys.sorted() {
        data[slot*4]=UInt8(offset&255);data[slot*4+1]=UInt8(offset>>8);data[slot*4+2]=0;data[slot*4+3]=0
        let body=entries[slot]!;data.replaceSubrange(offset..<offset+body.count,with:body);offset+=body.count
    };return data
}
private let macroBody=Data([2,0,0,0,0,0,0,0,0,0,4,0xb0,0,0,0,0x50])
private let opaqueBody=Data([1,0,0,0,0,0,0,0,1,2,3,0x77])

struct ConnectionTests {
    static func run()throws {
        var passed=0
        func test(_ name:String,_ operation:()throws->Void)throws{try operation();passed+=1;print("PASS "+name)}
        let now=Date(timeIntervalSince1970:100)
        try test("reconnect rejects stale read completion") {
            var link=USBConnection();link.discover(10)
            let old=link.beginRead(now:now)!
            link.discover(nil);link.discover(20)
            let fresh=link.beginRead(now:now)!
            try check(!link.readSucceeded(old) && link.reading && !link.ready,"old callback changed new connection")
            try check(link.readSucceeded(fresh) && link.ready,"fresh read rejected")
        }
        try test("sleep/wake requires a new read even for the same registry ID") {
            var link=USBConnection();link.discover(10);let old=link.beginRead(now:now)!;link.readSucceeded(old)
            link.sleep();try check(link.target==nil && !link.ready,"sleep kept write access")
            link.wake();try check(link.target!.registryID==10 && link.target != old && link.shouldRead(now:now),"wake reused a verified snapshot")
        }
        try test("read retries use 5, 15, and 30 second delays without duplicate reads") {
            var link=USBConnection();link.discover(10)
            var date=now
            for delay in [5.0,15,30,30] {
                let target=link.beginRead(now:date)!
                try check(link.beginRead(now:date)==nil,"duplicate read started")
                link.readFailed(target,now:date)
                try check(!link.shouldRead(now:date.addingTimeInterval(delay-0.1)) && link.shouldRead(now:date.addingTimeInterval(delay)),"retry deadline incorrect")
                date=date.addingTimeInterval(delay)
            }
        }
        try test("unsupported data does not loop but permits a manual retry") {
            var link=USBConnection();link.discover(10);let target=link.beginRead(now:now)!
            link.readFailed(target,now:now,retry:false)
            try check(!link.shouldRead(now:now.addingTimeInterval(100000)),"invalid data retried automatically")
            try check(link.beginRead(now:now,manual:true) != nil,"manual retry blocked")
        }
        let packets=[WirePacket(payload:DeviceConfiguration.command(0x18),acknowledgement:true),WirePacket(payload:DeviceConfiguration.command(0x11,1),acknowledgement:true),WirePacket(payload:[UInt8](repeating:0,count:64),acknowledgement:false),WirePacket(payload:DeviceConfiguration.command(0xf0),acknowledgement:true)]
        try test("cancelled connection sends no queued configuration packets") {
            let parent=TransferCancellation(),child=TransferCancellation(parent:parent),channel=TransactionChannel([])
            parent.cancel("Disconnected")
            try mustFail{_ = try FeatureTransaction.send(packets,channel:channel,cancellation:child)}
            try check(channel.writes.isEmpty,"old queue wrote to a new connection")
        }
        try test("mid-transfer cancellation stops before more data or flash-save") {
            let token=TransferCancellation(),channel=TransactionChannel([reply(0x18)])
            channel.onWrite={if $0==2{token.cancel()}}
            try mustFail{_ = try FeatureTransaction.send(packets,channel:channel,cancellation:token)}
            try check(channel.writes.count==2 && !channel.writes.contains{$0[1]==0xf0},"continued after cancellation")
        }
        try test("an unrelated or short ACK cannot confirm a command") {
            for response in [reply(2),[4,0x18,0,1]] {
                let channel=TransactionChannel([response])
                try mustFail{_ = try FeatureTransaction.send(packets,channel:channel)}
                try check(channel.writes.count==1,"continued after wrong ACK")
            }
        }
        try test("good transactions keep data reports separate from ACK reads") {
            let channel=TransactionChannel([reply(0x18),reply(0x11),reply(0xf0)])
            let log=try FeatureTransaction.send(packets,channel:channel)
            try check(channel.writes.count==4 && channel.replies.isEmpty && log.count==7,"wrong report sequencing")
        }
        try test("readback detects a silently unchanged keymap") {
            var p=Profile();p.bindings=[KeyBinding(keyID:1,fnLayer:false,kind:2,usage:5)]
            let packets=try ProtocolCore.keymap(p,fnLayer:false),expected=try ConfigurationWrite(packets:packets,revision:3,committed:["main"])
            var raw=emptySnapshot();try check(try !expected.matches(raw),"ACK was treated as proof of applying settings")
            raw.main=Data(packets[2..<11].flatMap(\.payload));try check(try expected.matches(raw),"matching table rejected")
        }
        try test("readback ignores settings write flags but checks applied values") {
            var p=Profile();p.sleepIndex=2;p.responseLevel=5
            let expected=try ConfigurationWrite(packets:ProtocolCore.settings(p),revision:1,committed:["settings"])
            var raw=emptySnapshot();try check(try expected.matches(raw),"write-only fields required in persistent settings")
            raw.settings[8]=4;try check(try !expected.matches(raw),"wrong response level accepted")
        }
        try test("unchanged decoded macros retain exact body bytes including zero delays") {
            var raw=emptySnapshot();raw.macros=macroMemory([8:macroBody])
            let p=try raw.decoded(previous:Profile(),keys:[]),packets=try ProtocolCore.macros(p)
            let stored=try MacroMemory.bodies(Data(packets.dropFirst(2).dropLast().flatMap(\.payload)))
            try check(stored[8]==macroBody,"unmodified macro was normalized")
            let expected=try ConfigurationWrite(packets:packets,revision:1,committed:["macros"])
            try check(try expected.matches(raw),"macro body comparison failed")
        }
        try test("new device macros survive reconciliation with a local macro edit") {
            var original=emptySnapshot();original.macros=macroMemory([0:macroBody])
            var draft=try original.decoded(previous:Profile(),keys:[]);draft.macros[0].steps[0].usage=6
            var fresh=original;fresh.macros=macroMemory([0:macroBody,20:macroBody])
            let incoming=try fresh.decoded(previous:draft,keys:[])
            let merged=try ProfileReconciliation.merge(incoming:incoming,draft:draft,pending:["macros"])
            try check(merged.0.macros.count==2 && merged.0.macros.first{$0.slot==0}!.steps[0].usage==6 && merged.0.macros.contains{$0.slot==20},"new device macro was deleted by a local draft")
        }
        try test("local macro binding survives reconnect when its slot became opaque") {
            var original=emptySnapshot();original.macros=macroMemory([0:macroBody])
            var draft=try original.decoded(previous:Profile(),keys:[])
            let id=draft.macros[0].id;draft.bindings=[KeyBinding(keyID:1,fnLayer:false,kind:4,macroID:id)]
            var fresh=original;fresh.macros=macroMemory([0:opaqueBody])
            let incoming=try fresh.decoded(previous:draft,keys:[])
            let merged=try ProfileReconciliation.merge(incoming:incoming,draft:draft,pending:["main"])
            try ProfileValidation.validate(merged.0,keys:[PhysicalKey(id:1,usage:4,name:"Test",x:0,y:0,width:1,height:1,lightIndex:1,fnDisabled:false)])
            let slots=try MacroMemory.slots(merged.0)
            try check(slots[id] != 0 && merged.1.contains("macros") && merged.0.bindings[0].macroID==id,"draft lost its macro dependency")
        }
        try test("lighting draft survives fresh configuration and explicit discard works") {
            let incoming=try emptySnapshot().decoded(previous:Profile(),keys:[])
            var draft=incoming;draft.brightness=2
            let merged=try ProfileReconciliation.merge(incoming:incoming,draft:draft,pending:["lighting"])
            let discarded=try ProfileReconciliation.merge(incoming:incoming,draft:draft,pending:[])
            try check(merged.0.brightness==2 && discarded.0.brightness==5,"draft merge/discard failed")
        }
        try test("empty assigned macros cannot be written as absent slots") {
            var p=Profile();let macro=LocalMacro();p.macros=[macro];p.bindings=[KeyBinding(keyID:1,fnLayer:false,kind:4,macroID:macro.id)]
            try mustFail{_ = try ProtocolCore.keymap(p,fnLayer:false)}
            try mustFail{_ = try ProtocolCore.macros(p)}
        }
        print("\(passed) connection/transfer tests passed")
    }
}
