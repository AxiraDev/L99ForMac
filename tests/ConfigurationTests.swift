// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation

private func expect(_ condition:Bool,_ message:String)throws {
    if !condition {throw L99Error.message("TEST FAILED: "+message)}
}
private func rejects(_ operation:()throws->Void)throws {
    do {try operation()}catch{return}
    throw L99Error.message("TEST FAILED: expected rejection")
}
private func ack(_ opcode:UInt8,_ sum:UInt32=0)->[UInt8] {
    var b=DeviceConfiguration.command(opcode);b[3]=1
    for i in 0..<4{b[4+i]=UInt8((sum>>(8*i))&255)};return b
}
private final class FakeChannel:FeatureChannel {
    var replies:[[UInt8]],writes:[[UInt8]]=[]
    init(_ replies:[[UInt8]]){self.replies=replies}
    func write(_ report:[UInt8])throws{writes.append(report)}
    func read()throws->[UInt8] {
        guard !replies.isEmpty else{throw L99Error.message("No more fake reports")}
        return replies.removeFirst()
    }
}
private func readReplies(corrupt:Bool=false)->[[UInt8]] {
    var result=[[UInt8]]()
    for (section,(_,opcode,count)) in DeviceConfiguration.sections.enumerated() {
        result.append(ack(0x18))
        if section%2==0 {result.append(ack(opcode))}
        let blocks=(0...count).map{i in [UInt8](repeating:UInt8(i+section+10),count:64)}
        result += blocks
        let sum=blocks.flatMap{$0}.reduce(UInt32(0)){$0+UInt32($1)}
        result.append(ack(2,sum+(corrupt && section==0 ? 1:0)))
    };return result
}
private func packedBodies(_ bodies:[Int:Data])->Data {
    var bytes=[UInt8](repeating:255,count:3072),offset=400
    for slot in bodies.keys.sorted() {
        bytes[slot*4]=UInt8(offset&255);bytes[slot*4+1]=UInt8(offset>>8);bytes[slot*4+2]=0;bytes[slot*4+3]=0
        let body=[UInt8](bodies[slot]!);bytes.replaceSubrange(offset..<offset+body.count,with:body);offset+=body.count
    };return Data(bytes)
}
private func synthetic()->DeviceConfiguration {
    var light=[UInt8](repeating:0,count:64);light[0]=15;light[8]=0xa1;light[9]=5;light[10]=3;light[12]=0x8c
    var settings=[UInt8](repeating:0,count:64);settings[2]=0xa0;settings[6]=2;settings[8]=5;settings[20]=0x71
    var main=[UInt8](repeating:0,count:576);main.replaceSubrange(4..<8,with:[0x91,0xab,0xcd,0xef]);main.replaceSubrange(8..<12,with:[6,20,1,3])
    var custom=[UInt8](repeating:0,count:576);custom.replaceSubrange(8..<12,with:[2,4,5,6])
    let opaque=Data([1,0,0,0,0,0,0,0,1,2,3,0x77])
    let editable=Data([2,0,0,0,0,0,0,0,0,0,4,0xb0,50,0,0,0x50])
    return DeviceConfiguration(lighting:Data(light),main:Data(main),fn:Data(repeating:0,count:576),settings:Data(settings),custom:Data(custom),macros:packedBodies([7:opaque,20:editable]),readAt:Date())
}
private func table(_ packets:[WirePacket])->[UInt8] {packets[2..<11].flatMap(\.payload)}

@main struct ConfigurationTests {
    static func main()throws {
        var passed=0
        func run(_ name:String,_ operation:()throws->Void)throws {try operation();passed+=1;print("PASS "+name)}
        let keys=(0...3).map{PhysicalKey(id:$0,usage:4+$0,name:"Test \($0)",x:0,y:0,width:1,height:1,lightIndex:$0+1,fnDisabled:false)}
        try run("read ACK/direct first blocks, extra block checksum, command allowlist") {
            let channel=FakeChannel(readReplies());let raw=try DeviceConfiguration.read(channel:channel)
            try raw.validate();try expect(raw.main.first==11 && raw.main.count==576,"direct block excluded accidentally")
            try expect(raw.lighting.allSatisfy{$0==10},"extra block leaked into requested region")
            let allowed:Set<UInt8>=[0x18,0x12,0x10,0x26,0x16,0x22,0x14,2]
            try expect(channel.writes.count==18 && channel.writes.allSatisfy{$0[0]==4 && allowed.contains($0[1])},"unexpected command")
        }
        try run("checksum mismatch aborts before the next section") {
            let channel=FakeChannel(readReplies(corrupt:true))
            try rejects{_ = try DeviceConfiguration.read(channel:channel)}
            try expect(!channel.writes.contains{$0[1]==0x10},"continued after checksum failure")
        }
        try run("truncated report is rejected") {
            var replies=readReplies();replies[2]=[1,2]
            try rejects{_ = try DeviceConfiguration.read(channel:FakeChannel(replies))}
        }
        let snapshot=synthetic()
        var profile=try snapshot.decoded(previous:Profile(),keys:keys)
        try run("decode unknown assignment and sparse macro slots") {
            try expect(profile.bindings.first{$0.keyID==1}?.kind==5,"unknown action discarded")
            try expect(profile.macros.count==1 && profile.macros[0].slot==20,"macro slot compacted")
            try expect(profile.macros[0].repeatCount==3,"repeat count lost")
        }
        try run("one-key assignment preserves opaque and macro assignments") {
            var p=profile;p.bindings.append(KeyBinding(keyID:3,fnLayer:false,kind:2,usage:5))
            let data=table(try ProtocolCore.keymap(p,fnLayer:false))
            try expect(Array(data[4..<12])==Array(snapshot.main[4..<12]),"other actions changed")
            try expect(Array(data[12..<16])==[2,0,5,0],"new assignment absent")
        }
        try run("explicit standard clears only its own entry") {
            var p=profile;p.bindings.removeAll{$0.keyID==1};p.bindings.append(KeyBinding(keyID:1,fnLayer:false))
            let data=table(try ProtocolCore.keymap(p,fnLayer:false))
            try expect(data[4..<8].allSatisfy{$0==0} && Array(data[8..<12])==Array(snapshot.main[8..<12]),"default clear damaged another entry")
        }
        try run("macro edits preserve unsupported bodies and original slot") {
            profile.macros[0].steps[0].usage=6
            let packets=try ProtocolCore.macros(profile),data=Data(packets.dropFirst(2).dropLast().flatMap(\.payload))
            let bodies=try MacroMemory.bodies(data),old=try MacroMemory.bodies(snapshot.macros)
            try expect(bodies[7]==old[7] && MacroMemory.steps(bodies[20]!)?.first?.usage==6,"opaque macro lost or parsed macro retargeted")
            let slots=try MacroMemory.slots(profile);try expect(slots[profile.macros[0].id]==20,"stable slot lost")
        }
        try run("deleted macro references clear before reuse and retain other actions") {
            var p=profile;p.macros=[];p.bindings=[]
            let cleanup=try ProtocolCore.detachedMacroKeymaps(p),bytes=table(cleanup)
            try expect(bytes[8..<12].allSatisfy{$0==0} && Array(bytes[4..<8])==Array(snapshot.main[4..<8]),"cleanup changed an unrelated action")
            var new=LocalMacro();new.steps=[MacroStep()];p.macros=[new]
            let slot=try MacroMemory.slots(p)[new.id]!
            try expect(slot != 7 && slot != 20,"deleted occupied slot was reused before readback")
        }
        try run("new macro names survive sparse slot decode") {
            var p=profile;var m=LocalMacro();m.name="Local name";m.steps=[MacroStep()];p.macros.append(m)
            let packets=try ProtocolCore.macros(p)
            var fresh=snapshot;var bytes=packets.dropFirst(2).dropLast().flatMap(\.payload);bytes += Array(repeating:0,count:3072-bytes.count);fresh.macros=Data(bytes)
            let decoded=try fresh.decoded(previous:p,keys:keys)
            try expect(decoded.macros.contains{$0.id==m.id && $0.name=="Local name" && $0.slot==0},"new macro identity lost")
        }
        try run("lighting and settings retain unknown bytes and bits") {
            var p=profile;p.colorful=false;p.disableWin=true
            let light=try ProtocolCore.lighting(p)[2].payload,settings=try ProtocolCore.settings(p)[2].payload
            try expect(light[12]==0x8c && light[8]==0xa0,"lighting opaque bytes lost")
            try expect(settings[2]==0xa1 && settings[20]==0x71,"settings opaque bits lost")
        }
        try run("custom colors preserve unedited records") {
            var p=profile;p.keyColors=["0":"112233"]
            let packets=try ProtocolCore.custom(p,keys:keys),header=packets.firstIndex{$0.payload[0]==4 && $0.payload[1]==0x23}!
            let bytes=packets[(header+1)..<(header+10)].flatMap(\.payload)
            try expect(Array(bytes[4..<8])==[1,0x11,0x22,0x33] && Array(bytes[8..<12])==[2,4,5,6],"custom record was overwritten")
        }
        try run("legacy profiles decode without new optional fields") {
            var obj=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Profile())) as! [String:Any]
            obj.removeValue(forKey:"deviceConfiguration")
            let decoded=try JSONDecoder().decode(Profile.self,from:JSONSerialization.data(withJSONObject:obj))
            try expect(decoded.deviceConfiguration==nil,"legacy profile needs a snapshot")
        }
        try run("atomic session restore, damaged primary and validated backup") {
            let directory=FileManager.default.temporaryDirectory.appendingPathComponent("l99-state-test-"+UUID().uuidString)
            defer{try? FileManager.default.removeItem(at:directory)}
            let store=SessionStore(directory:directory)
            func validate(_ session:SavedSession)throws {if session.profile.name=="Invalid"{throw L99Error.message("Invalid test profile")}}
            var value=SavedSession(profile:profile,music:MusicPreferences(foreground:5,background:3,brightness:20,sensitivity:2),pending:["main"],syncClock:true,liveMetrics:false,savedAt:Date())
            value.profile.name="First";try store.save(value,validate:validate)
            value.profile.name="Second";try store.save(value,validate:validate)
            let restored=try store.restore(validate:validate)!
            try expect(!restored.1 && restored.0.profile.name=="Second" && restored.0.music.sensitivity==2,"round trip failed")
            value.profile.name="Invalid";try JSONEncoder().encode(value).write(to:directory.appendingPathComponent("session.json"))
            try expect(try store.restore(validate:validate)!.0.profile.name=="First","invalid primary not rejected")
            value.profile.name="Third";try store.save(value,validate:validate)
            try Data("broken".utf8).write(to:directory.appendingPathComponent("session.json"))
            let recovered=try store.restore(validate:validate)!
            try expect(recovered.1 && recovered.0.profile.name=="First","bad primary replaced good backup")
            value.music.sensitivity = .nan;try rejects{try store.save(value,validate:validate)}
        }
        try run("standalone macro application commits after bodies and reference updates") {
            var p=profile;p.bindings[1].modifiers=4
            let packets=try ProtocolCore.macroUpdate(p)
            try expect(packets.last?.payload[0]==4 && packets.last?.payload[1]==0xf0 && packets.last?.acknowledgement==true,"missing final commit")
            try expect(packets[packets.count-2].payload[1]==2,"commit preceded the macro end")
            let write=try ConfigurationWrite(packets:packets,revision:0,committed:[])
            try expect(write.regions[0x11] != nil && write.regions[0x15] != nil,"reference or macro memory omitted")
        }
        try run("distinct per-key repeat counts survive decoding and writing") {
            var raw=snapshot;var bytes=[UInt8](raw.main)
            bytes.replaceSubrange(12..<16,with:[6,20,0,7]);raw.main=Data(bytes)
            let p=try raw.decoded(previous:Profile(),keys:keys)
            let written=table(try ProtocolCore.keymap(p,fnLayer:false))
            try expect(Array(written[8..<16])==Array(bytes[8..<16]),"one key's count overwrote another or changed playback mode")
        }
        try run("macro repeat edit updates both layers without unrelated key drafts") {
            var raw=snapshot;var bytes=[UInt8](raw.fn);bytes.replaceSubrange(12..<16,with:[6,20,0,1]);raw.fn=Data(bytes)
            let old=try raw.decoded(previous:Profile(),keys:keys)
            var p=old;p.macros[0].repeatCount=5;MacroAssignments.updateRepeats(from:old,in:&p)
            p.bindings.append(KeyBinding(keyID:0,fnLayer:false,kind:2,usage:6))
            let packets=try ProtocolCore.detachedMacroKeymaps(p)
            let write=try ConfigurationWrite(packets:packets,revision:0,committed:[])
            try expect(Array(write.regions[0x11]![8..<12])==[6,20,1,5],"main repeat not sent")
            try expect(Array(write.regions[0x27]![12..<16])==[6,20,1,5],"Fn repeat not sent")
            try expect(write.regions[0x11]!.prefix(4)==raw.main.prefix(4),"unrelated draft applied")
            try expect(p.bindings.filter{$0.kind==4}.allSatisfy{$0.modifiers==5},"profile count is stale")
        }
        try run("explicit single repeat changes playback mode while preserving other keys") {
            var p=profile;let index=p.bindings.firstIndex{$0.kind==4}!
            p.bindings[index].modifiers=1
            let bytes=table(try ProtocolCore.keymap(p,fnLayer:false))
            try expect(Array(bytes[8..<12])==[6,20,0,1],"repeat mode did not return to once")
            try expect(Array(bytes[4..<8])==Array(snapshot.main[4..<8]),"opaque key changed")
        }
        try run("exact macro budget includes index, padding and occupied opaque bodies") {
            var p=Profile();var m=LocalMacro();m.steps=Array(repeating:MacroStep(),count:325);p.macros=[m]
            try expect(try MacroMemory.usedBytes(p)==3072,"325-action boundary")
            let data=try ProtocolCore.macros(p).dropFirst(2).dropLast().flatMap(\.payload)
            try expect(data.count==3072 && !MacroMemory.canAppend(1,to:m.id,in:p),"reported budget differs from serialized data")
            p.macros[0].steps.append(MacroStep());try rejects{_ = try ProtocolCore.macros(p)}
            p.deviceConfiguration=snapshot;p.macros[0].steps=Array(repeating:MacroStep(),count:324)
            try expect(!MacroMemory.canAppend(1,to:m.id,in:p),"opaque body was not reserved")
        }
        try run("empty macro header is reserved before the first action") {
            var p=Profile();var m=LocalMacro();m.steps=Array(repeating:MacroStep(),count:324);let empty=LocalMacro();p.macros=[m,empty]
            try expect(!MacroMemory.canAppend(1,to:empty.id,in:p),"new body header did not consume memory")
            try expect(MacroMemory.canAppend(1,to:m.id,in:p),"existing header counted twice")
        }
        try run("edited short delays are rejected, unchanged device delays stay exact") {
            var p=Profile();var m=LocalMacro();m.steps=[MacroStep(delay:0)];p.macros=[m]
            try rejects{_ = try ProtocolCore.macros(p)}
            var raw=snapshot;var bodies=try MacroMemory.bodies(raw.macros);bodies[20]![12]=0;raw.macros=packedBodies(bodies)
            p=try raw.decoded(previous:Profile(),keys:keys)
            let data=Data(try ProtocolCore.macros(p).dropFirst(2).dropLast().flatMap(\.payload))
            try expect(try MacroMemory.bodies(data)[20]==bodies[20],"unchanged zero delay normalized")
            p.macros[0].steps[0].usage=8;try rejects{_ = try ProtocolCore.macros(p)}
        }
        try run("recorded chords release in reverse order, duplicates are ignored") {
            var capture=MacroCapture(),events=[Int]()
            for usage in [227,225,4] {try expect(capture.accept(usage:usage,down:true){_ in events.append(usage);return true},"press rejected")}
            _ = capture.accept(usage:4,down:true){_ in events.append(99);return true}
            _ = capture.accept(usage:5,down:false){_ in events.append(99);return true}
            try expect(events==[227,225,4] && capture.finish()==[4,225,227],"chord not balanced")
            try expect(capture.finish().isEmpty,"stop emitted releases twice")
        }
        try run("memory exhaustion leaves room to release the captured key") {
            var p=Profile();var m=LocalMacro();m.steps=Array(repeating:MacroStep(),count:323);p.macros=[m]
            var capture=MacroCapture()
            func commit(_ usage:Int,_ down:Bool,_ reserved:Int)->Bool {
                guard MacroMemory.canAppend(1+reserved,to:m.id,in:p) else{return false}
                p.macros[0].steps.append(MacroStep(action:down ? "Key down":"Key up",usage:usage));return true
            }
            try expect(capture.accept(usage:227,down:true){commit(227,true,$0)},"first key should fit with release")
            try expect(!capture.accept(usage:4,down:true){commit(4,true,$0)},"second key exceeded reserved capacity")
            for usage in capture.finish() {try expect(commit(usage,false,0),"reserved release no longer fits")}
            try expect(p.macros[0].steps.count==325 && p.macros[0].steps.last?.action=="Key up","last action left key held")
        }
        try run("manual repair separates mouse and keyboard releases") {
            let steps=[MacroStep(usage:4),MacroStep(action:"Mouse down",usage:1),MacroStep(action:"Key up",usage:4),MacroStep(usage:225)]
            let release=MacroSequence.releases(for:steps)
            try expect(release.map(\.action)==["Key up","Mouse up"] && release.map(\.usage)==[225,1],"missing or wrong release")
            try expect(MacroSequence.releases(for:steps+release).isEmpty,"repair did not balance sequence")
        }
        try run("assignment editor follows macro identity across list reordering") {
            var p=Profile();var a=LocalMacro();a.slot=12;a.steps=[MacroStep(),MacroStep(action:"Key up")]
            var b=LocalMacro();b.steps=a.steps;p.macros=[a,b]
            let binding=KeyBinding(keyID:2,fnLayer:true,kind:4,modifiers:3,usage:12,macroID:a.id,rawEntry:Data([6,12,1,3]))
            let draft=AssignmentDraft(binding,profile:p);p.macros.reverse()
            try expect(try draft.binding(keyID:2,fnLayer:true,profile:p)==binding,"reordering retargeted the macro or lost its exact entry")
            p.macros.removeAll{$0.id==a.id};try rejects{_ = try draft.binding(keyID:2,fnLayer:true,profile:p)}
        }
        try run("action families do not inherit macro repeat bits as key modifiers") {
            var p=Profile();var m=LocalMacro();m.steps=[MacroStep()];p.macros=[m]
            var draft=AssignmentDraft(KeyBinding(keyID:2,fnLayer:true,kind:4,modifiers:17,macroID:m.id),profile:p)
            draft.selectKind(2,profile:p)
            let key=try draft.binding(keyID:2,fnLayer:true,profile:p)
            try expect(key.kind==2 && key.usage==4 && key.modifiers==0,"repeat bits leaked into a shortcut")
            draft.selectKind(3,profile:p);try expect(draft.usage==0xcd,"invalid media default")
            draft.selectKind(2,profile:p);try expect(draft.usage==4 && draft.modifiers==0,"returning to keyboard retained a media code")
        }
        try run("editor preserves opaque assignments only for their original key and layer") {
            let binding=KeyBinding(keyID:1,fnLayer:true,kind:5,rawEntry:Data([0x91,1,2,3]))
            let draft=AssignmentDraft(binding)
            try expect(try draft.binding(keyID:1,fnLayer:true,profile:Profile())==binding,"opaque action changed")
            try rejects{_ = try draft.binding(keyID:1,fnLayer:false,profile:Profile())}
        }
        try run("empty or missing macros cannot be assigned from the editor") {
            var p=Profile();let m=LocalMacro();p.macros=[m]
            var draft=AssignmentDraft();draft.selectKind(4,profile:p)
            try rejects{_ = try draft.binding(keyID:1,fnLayer:false,profile:p)}
            p.macros[0].steps=[MacroStep(),MacroStep(action:"Key up")]
            try expect(try draft.binding(keyID:1,fnLayer:false,profile:p).macroID==m.id,"existing macro was not resolved")
        }
        try run("Fn keymap sends only its table and preserves the main assignment") {
            var p=profile;let before=p.deviceConfiguration!.main
            p.bindings.append(KeyBinding(keyID:3,fnLayer:true,kind:2,modifiers:2,usage:4))
            let packets=try ProtocolCore.keymap(p,fnLayer:true),write=try ConfigurationWrite(packets:packets,revision:0,committed:["fn"])
            try expect(packets[1].payload[1]==0x27 && write.regions[0x11]==nil,"Fn write addressed the main table")
            try expect(Array(write.regions[0x27]![12..<16])==[2,2,4,0] && p.deviceConfiguration!.main==before,"shortcut or main table changed")
        }
        try run("composed chords release modifiers after the primary key") {
            let steps=try MacroChord.steps(usage:4,modifiers:0x8a,delay:75)
            try expect(steps.map(\.usage)==[225,227,231,4,4,231,227,225],"modifier mask or release order differs")
            try expect(steps.prefix(4).allSatisfy{$0.action=="Key down"} && steps.suffix(4).allSatisfy{$0.action=="Key up"},"chord ordering is unbalanced")
            try expect(steps.allSatisfy{$0.delay==75} && MacroSequence.releases(for:steps).isEmpty,"chord delay or release omitted")
            try expect(Set(steps.map(\.id)).count==steps.count,"editor row identities are not unique")
            try rejects{_ = try MacroChord.steps(usage:225,modifiers:2)}
            try rejects{_ = try MacroChord.steps(usage:4,modifiers:256)}
            try rejects{_ = try MacroChord.steps(usage:4,modifiers:0,delay:9)}
        }
        try run("composed keyboard and mouse actions retain all event and delay bytes") {
            var p=Profile();var m=LocalMacro()
            m.steps=try MacroChord.steps(usage:4,modifiers:2)
            m.steps[m.steps.count-1].delay=500
            m.steps += [MacroStep(action:"Mouse down",usage:2,delay:100),MacroStep(action:"Mouse up",usage:2,delay:100)]
            p.macros=[m]
            let data=Data(try ProtocolCore.macros(p).dropFirst(2).dropLast().flatMap(\.payload)),bodies=try MacroMemory.bodies(data)
            let decoded=MacroMemory.steps(bodies[0]!)!
            try expect(decoded.map({"\($0.action):\($0.usage):\($0.delay)"})==m.steps.map({"\($0.action):\($0.usage):\($0.delay)"}),"chord or mouse encoding changed")
        }
        try run("complete Fn assignment includes its macro before committing the layer") {
            var p=profile
            p.bindings.append(KeyBinding(keyID:3,fnLayer:true,kind:4,modifiers:1,macroID:p.macros[0].id))
            let packets=try ProtocolCore.assignmentUpdate(p,fnLayer:true)
            let write=try ConfigurationWrite(packets:packets,revision:0,committed:[])
            try expect(write.regions[0x15] != nil && write.regions[0x27] != nil && write.regions[0x11]==nil,"assignment stream omitted dependency or wrote the wrong layer")
            let macroHeader=packets.firstIndex{$0.payload[0]==4 && $0.payload[1]==0x15}!
            let fnHeader=packets.firstIndex{$0.payload[0]==4 && $0.payload[1]==0x27}!
            try expect(macroHeader<fnHeader && packets.last!.payload[1]==0xf0,"layer committed before macro contents")
        }
        try run("input checking consumes events only in its active focused window") {
            for active in [false,true] {for key in [false,true] {for focused in [false,true] {
                try expect(InputCheckLog.accepts(active:active,keyWindow:key,focused:focused)==(active && key && focused),"input scope escaped the test pad")
            }}}
        }
        try run("input checking retains actual press and release timing") {
            var log=InputCheckLog()
            log.append(mouse:false,usage:224,down:true,at:10)
            log.append(mouse:false,usage:224,down:false,at:10.25)
            log.append(mouse:true,usage:2,down:true,at:10.75)
            try expect(log.heldKeys.isEmpty && log.heldMouse==[2],"device domains mixed or releases synthesized")
            try expect(log.events.map(\.seconds)==[0,0.25,0.75],"relative event times were lost")
            log.append(mouse:true,usage:2,down:false,at:11)
            try expect(log.heldMouse.isEmpty,"mouse release not observed")
        }
        try run("bounded event history retains held state independently of old rows") {
            var log=InputCheckLog();log.append(mouse:false,usage:227,down:true,at:1)
            for i in 0..<150 {log.append(mouse:false,usage:4,down:i%2==0,at:Double(i+2))}
            try expect(log.events.count==100 && log.count==151 && log.heldKeys==[227],"history eviction corrupted observed held keys")
            log.append(mouse:false,usage:227,down:false,at:200)
            try expect(log.heldKeys.isEmpty && log.events.last!.id==152,"evicted key cannot be released")
        }
        passed += try runLocalizationTests()
        print("\(passed) configuration/session/localization tests passed")
        try ConnectionTests.run()
    }
}
