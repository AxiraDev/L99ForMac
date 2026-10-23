// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO

struct PhysicalKey: Codable, Identifiable {
    var id, usage: Int
    var name: String
    var x, y, width, height, lightIndex: Int
    var fnDisabled: Bool
}

struct KeyBinding: Codable, Identifiable, Equatable {
    var keyID: Int
    var fnLayer: Bool
    var kind: Int = 0
    var modifiers: Int = 0
    var usage: Int = 0
    var macroID: UUID?=nil
    var rawEntry:Data?=nil
    var id: String { "\(fnLayer)-\(keyID)" }
}

/// Editor state uses macro identity, independent of list order or device slot.
struct AssignmentDraft:Equatable {
    var kind:Int
    var usage:Int
    var modifiers:Int
    var macroID:UUID?
    var repeatCount:Int
    private var original:KeyBinding
    init(_ binding:KeyBinding=KeyBinding(keyID:0,fnLayer:false),profile:Profile=Profile()) {
        original=binding;kind=binding.kind;usage=binding.usage==0 ? 4:binding.usage
        modifiers=binding.kind==2 ? binding.modifiers:0;macroID=binding.macroID
        repeatCount=binding.kind==4 ? max(1,binding.modifiers):1
    }
    mutating func selectKind(_ value:Int,profile:Profile) {
        guard value != kind else{return}
        kind=value
        switch value {
        case 2:usage=4;modifiers=0
        case 3:usage=0xcd;modifiers=0
        case 4:
            if !profile.macros.contains(where:{$0.id==macroID}) {macroID=profile.macros.first?.id}
            repeatCount=profile.macros.first{$0.id==macroID}?.repeatCount ?? 1
        default:break
        }
    }
    func binding(keyID:Int,fnLayer:Bool,profile:Profile)throws->KeyBinding {
        var result=KeyBinding(keyID:keyID,fnLayer:fnLayer,kind:kind)
        switch kind {
        case 0,1:break
        case 2:
            guard (0...255).contains(usage),(0...255).contains(modifiers) else{throw L99Error.message(T("Некорректное сочетание клавиш."))}
            if (224...231).contains(usage),modifiers != 0 {throw L99Error.message(T("Для отдельного модификатора убери дополнительные Ctrl/Shift/Option/Command."))}
            result.usage=usage;result.modifiers=modifiers
        case 3:result.usage=usage
        case 4:
            guard let macro=profile.macros.first(where:{$0.id==macroID}),!macro.steps.isEmpty else{throw L99Error.message(T("Выбери существующий макрос с действиями."))}
            guard (1...255).contains(repeatCount) else{throw L99Error.message(T("Число повторов должно быть от 1 до 255."))}
            result.macroID=macro.id;result.modifiers=repeatCount;result.usage=macro.slot ?? 0
        case 5:
            guard original.kind==5,original.keyID==keyID,original.fnLayer==fnLayer else{throw L99Error.message(T("Не хватает данных текущего действия."))}
            return original
        default:throw L99Error.message(T("Неизвестное назначение."))
        }
        if original.keyID==keyID,original.fnLayer==fnLayer,original.kind==result.kind,
           original.modifiers==result.modifiers,original.usage==result.usage,original.macroID==result.macroID {result.rawEntry=original.rawEntry}
        return result
    }
}

struct MacroStep: Codable, Identifiable, Equatable {
    var id=UUID()
    var action="Key down"
    var usage=4
    var delay=50
}
struct LocalMacro: Codable, Identifiable, Equatable {
    var id=UUID()
    var name=T("Новый макрос")
    var repeatCount=1
    var slot:Int?=nil
    var steps: [MacroStep]=[]
}
struct Profile: Codable, Equatable {
    var formatVersion=1
    var name=T("Мой L99")
    var mode=11
    var colorHex="00BFFF"
    var brightness=5
    var speed=3
    var direction=0
    var colorful=true
    var disableWin=false
    var disableAltF4=false
    var disableAltTab=false
    var fnToggle=false
    var sleepIndex=1
    var responseLevel=3
    var bindings: [KeyBinding]=[]
    var macros: [LocalMacro]=[]
    var keyColors: [String:String]=[:]
    var deviceConfiguration:DeviceConfiguration?=nil
}

extension NSColor {
    convenience init(hex: String) {
        let n=UInt32(hex,radix:16) ?? 0x00bfff
        self.init(srgbRed:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255,alpha:1)
    }
    var hexRGB: String {
        let c=usingColorSpace(.sRGB) ?? self
        return String(format:"%02X%02X%02X",Int((c.redComponent*255).rounded()),Int((c.greenComponent*255).rounded()),Int((c.blueComponent*255).rounded()))
    }
}

enum Section: String, CaseIterable, Identifiable {
    case home="Главная",keys="Назначения",macros="Макросы",light="Подсветка",custom="Свои цвета",screen="IPS-экран",realtime="Real-time Data",music="Музыка",settings="Настройки"
    var id: Self { self }
    var icon: String {
        switch self {
        case .home:return "house";case .keys:return "keyboard";case .macros:return "record.circle";case .light:return "sun.max";case .custom:return "paintpalette";case .screen:return "display";case .realtime:return "gauge.with.dots.needle.50percent";case .music:return "waveform";case .settings:return "gearshape"
        }
    }
}

@MainActor final class AppModel: ObservableObject {
    @Published var section: Section = .home
    @Published var profile=Profile() {didSet{profileChanged(from:oldValue)}}
    @Published var keys: [PhysicalKey]=[]
    @Published var interfaces: [HIDInterface]=[]
    @Published var displayConnected=false
    @Published var selectedKey: Int?=nil
    @Published var selectingKey=false
    private let keySelector=KeySelectionRecorder()
    @Published var fnLayer=false
    @Published var busy=false
    @Published var status=T("Локальный профиль. Настройки с клавиатуры не считывались.")
    @Published var error: String?=nil
    @Published var autosaveStatus=T("Подготавливаю профиль…")
    @Published private(set) var loadingSession=true
    private let sessionQueue=DispatchQueue(label:"l99.local-session")
    @Published var lastConfigurationRead:Date?=nil
    @Published private(set) var pendingSections=Set<String>()
    @Published private(set) var configurationReady=false
    private let sessionStore=SessionStore()
    private var restoringSession=true
    @Published private(set) var sessionAccess=false
    private var changingProfile=false
    private var saveWork:DispatchWorkItem?
    private var profileRevision=0

    @Published var screenImage: NSImage?=nil
    @Published var screenInfo=T("PNG, JPEG или GIF · 320 × 480 · до 200 кадров")
    @Published var screenURL: URL?=nil
    @Published var screenDestination: ScreenDestination = .photo
    @Published var screenFit: ScreenFit = .fit
    @Published var screenRotation=0
    @Published var screenProgress=0.0
    @Published var logs: [String]=[]
    @Published var recording=false
    @Published var musicActive=false
    @Published var musicStarting=false
    @Published var musicStopping=false
    @Published var musicLevels=[UInt8](repeating:0,count:18)
    @Published var musicDecibels = -120.0
    @Published var musicStatus=T("Нажми «Запустить», чтобы включить реакцию на системный звук Mac.")
    @Published var musicOutputName=T("Системный звук Mac")
    @Published var musicFramesSent=0
    @Published var musicForeground=2 {didSet{scheduleSessionSave()}}
    @Published var musicBackground=0 {didSet{scheduleSessionSave()}}
    @Published var musicBackgroundBrightness=15.0 {didSet{scheduleSessionSave()}}
    @Published var musicSensitivity=1.0 {
        didSet {musicSession?.capture.analyzer.setSensitivity(musicSensitivity);scheduleSessionSave()}
    }
    private var musicSession:MusicSession?
    private var musicTimer:Timer?
    private var musicWriteInFlight=false
    private var musicCleanup:DispatchGroup?
    private var pendingMusicResume:USBTarget?
    private var nextMusicDeviceCheck=Date.distantPast
    private let musicControlQueue=DispatchQueue(label:"l99.music.control",qos:.userInitiated)
    private var terminationObserver:NSObjectProtocol?
    private var sleepObserver:NSObjectProtocol?
    @Published var metrics=MacMetrics.empty
    @Published var realtimeStatus=T("Ожидание подключения L99 по USB.")
    @Published var lastRealtimeUpdate:Date?=nil
    @Published var realtimeSending=false
    @Published var syncClockOnConnect=UserDefaults.standard.object(forKey:"syncClockOnConnect") as? Bool ?? true {
        didSet {clockPending=syncClockOnConnect;scheduleSessionSave()}
    }
    @Published var liveMetrics=UserDefaults.standard.object(forKey:"liveMetrics") as? Bool ?? true {
        didSet {if liveMetrics{nextRealtimeSend = .distantPast};scheduleSessionSave()}
    }
    private var clockPending=false
    @Published private(set) var isSleeping=false
    private var keyboardLink=USBConnection()
    private var displayLink=USBConnection()
    private var keyboardLifetime=TransferCancellation()
    private var displayLifetime=TransferCancellation()
    private var activeOperation:USBOperation?
    private var metricsTicket:UUID?
    private var nextRealtimeSend=Date.distantPast
    private var metricsInFlight=false
    private var realtimeFailures=0
    private var realtimeTimer:Timer?
    private var wakeObserver:NSObjectProtocol?
    private let sampler=MacMetricsSampler()
    let recorder=MacroRecorder()
    let transport=HIDTransport()
    let queue=DispatchQueue(label:"aula.l99.hid")
    var connected: Bool { !isSleeping && keyboardLink.target != nil && interfaces.filter(\.isSettings).count == 1 }
    var canWrite: Bool { connected && !busy && configurationReady }
    var canUploadScreen: Bool {!isSleeping && displayConnected && displayLink.target != nil && !busy}
    var uploadingScreen:Bool {activeOperation?.kind == .screen}
    var resourceURL: URL { Bundle.main.resourceURL!.appendingPathComponent("resources") }
    init() {
        do { keys=try JSONDecoder().decode([PhysicalKey].self,from:Data(contentsOf:resourceURL.appendingPathComponent("keys.json"))) }
        catch { self.error=T("Не удалось загрузить схему клавиатуры: \(error.localizedDescription)") }
        DispatchQueue.main.async {self.restoreLocalSession()}
        realtimeTimer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) {[weak self] _ in
            Task {@MainActor in self?.realtimeTick()}
        }
        wakeObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) {[weak self] _ in
            MainActor.assumeIsolated {self?.handleWake()}
        }
        terminationObserver=NotificationCenter.default.addObserver(forName:NSApplication.willTerminateNotification,object:nil,queue:.main){[weak self] _ in
            MainActor.assumeIsolated {
                self?.cancelOperation(.keyboard,reason:T("Приложение закрывается. Правки сохранены."))
                self?.cancelOperation(.screen,reason:T("Приложение закрывается. Загрузка остановлена."))
                self?.saveSessionNow(wait:true);self?.shutdownMusic()
            }
        }
        sleepObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.willSleepNotification,object:nil,queue:.main){[weak self] _ in
            MainActor.assumeIsolated {self?.handleSleep()}
        }
    }
    func scan() {
        guard !restoringSession,!isSleeping else{return}
        interfaces=transport.scan()
        let endpoint=DisplayTransport.endpoint();displayConnected=endpoint != nil
        let settings=interfaces.filter(\.isSettings),id=settings.count==1 ? settings.first?.id:nil
        if keyboardLink.discover(id) {
            logs.append(id==nil ? "USB keyboard disconnected; old tasks invalidated.":"USB keyboard connected; configuration must be read again.")
            let reason=T("USB-подключение L99 изменилось. Незавершённые правки сохранены.")
            keyboardLifetime.cancel(reason);keyboardLifetime=TransferCancellation()
            cancelOperation(.keyboard,reason:reason)
            configurationReady=false;lastConfigurationRead=nil;metricsTicket=nil;metricsInFlight=false;realtimeSending=false
            realtimeFailures=0;nextRealtimeSend = .distantPast;lastRealtimeUpdate=nil
            clockPending=id != nil && syncClockOnConnect
            stopMusic(reason:T("L99 переподключена. После чтения настроек нажми «Запустить»."),restoreLighting:false)
            realtimeStatus=id == nil ? T("Ожидание подключения L99 по USB."):T("Клавиатура подключена. Подготавливаю данные Mac…")
            if id==nil {status=settings.count>1 ? T("Подключи одну L99 для настройки."):T("L99 отключена. Локальные правки сохранены.")}
        }
        if displayLink.discover(endpoint?.registryID) {
            let reason=T("USB-экран отключён или переподключён. Загрузку нужно начать заново.")
            displayLifetime.cancel(reason);displayLifetime=TransferCancellation()
            cancelOperation(.screen,reason:reason)
        }
        if !busy,keyboardLink.shouldRead(now:Date()) {readDeviceConfiguration(automatic:true)}
        if let target=pendingMusicResume,!musicStopping,!busy,canWrite {
            pendingMusicResume=nil
            if keyboardLink.contains(target){startMusic()}
        }
    }
    private func handleSleep() {
        guard !isSleeping else{return}
        logs.append("Mac sleep: device operations cancelled.")
        isSleeping=true;keyboardLink.sleep();displayLink.sleep()
        let reason=T("Mac переходит в сон. Незавершённая передача остановлена; локальные правки сохранены.")
        keyboardLifetime.cancel(reason);displayLifetime.cancel(reason)
        cancelOperation(.keyboard,reason:reason);cancelOperation(.screen,reason:reason)
        configurationReady=false;lastConfigurationRead=nil;metricsTicket=nil;metricsInFlight=false;realtimeSending=false
        stopRecording();stopSelectingKey()
        stopMusic(reason:T("Музыка остановлена перед сном Mac. После пробуждения нажми «Запустить»."),restoreLighting:false)
        status=reason;realtimeStatus=T("Синхронизация приостановлена на время сна Mac.");saveSessionNow()
    }
    private func handleWake() {
        logs.append("Mac wake: cached device state invalidated.")
        let reason=T("Mac проснулся. Повторно проверяю USB-подключение L99.")
        keyboardLifetime.cancel(reason);displayLifetime.cancel(reason)
        cancelOperation(.keyboard,reason:reason);cancelOperation(.screen,reason:reason)
        stopMusic(reason:T("После пробуждения нажми «Запустить», чтобы включить музыку."),restoreLighting:false)
        metricsTicket=nil;metricsInFlight=false;realtimeSending=false
        isSleeping=false;keyboardLink.wake();displayLink.wake()
        keyboardLifetime=TransferCancellation();displayLifetime=TransferCancellation()
        configurationReady=false;clockPending=syncClockOnConnect;nextRealtimeSend = .distantPast
        realtimeFailures=0;lastRealtimeUpdate=nil;scan()
    }
    private func beginOperation(_ kind:USBOperationKind,target:USBTarget)->USBOperation {
        let operation=USBOperation(kind,target:target,parent:kind == .keyboard ? keyboardLifetime:displayLifetime)
        activeOperation=operation;busy=true;return operation
    }
    private func accepts(_ operation:USBOperation)->Bool {
        activeOperation===operation && !operation.cancellation.isCancelled && (operation.kind == .keyboard ? keyboardLink:displayLink).contains(operation.target)
    }
    @discardableResult private func finishOperation(_ operation:USBOperation)->Bool {
        guard accepts(operation) else{return false}
        activeOperation=nil;busy=false;return true
    }
    private func cancelOperation(_ kind:USBOperationKind,reason:String) {
        guard let operation=activeOperation,operation.kind==kind else{return}
        operation.cancellation.cancel(reason);activeOperation=nil;busy=false;status=reason
    }
    func cancelScreenUpload(){cancelOperation(.screen,reason:T("Загрузка остановлена. Для завершения начни её заново."))}
    func startMusic() {
        guard canWrite,!musicActive,!musicStarting,!musicStopping else{return}
        guard let target=keyboardLink.target else{return}
        pendingMusicResume=nil
        let session=MusicSession(target:target,connection:keyboardLifetime)
        musicSession=session;musicStarting=true;musicFramesSent=0
        musicStatus=T("Подготавливаю системное аудио. Разреши захват звука, если macOS спросит.")
        session.capture.analyzer.setSensitivity(musicSensitivity)
        musicControlQueue.async {
            let result=Result {try session.capture.start()}
            DispatchQueue.main.async {
                guard self.musicSession===session,!session.isCancelled,self.keyboardLink.contains(session.target) else{return}
                self.musicStarting=false
                switch result {
                case .success:
                    self.musicActive=true;self.musicOutputName=session.capture.outputName
                    self.musicStatus=T("Захват включён. Включи музыку и открой плеер на экране L99.")
                    self.nextMusicDeviceCheck=Date().addingTimeInterval(2)
                    self.musicTimer=Timer.scheduledTimer(withTimeInterval:0.08,repeats:true){[weak self] _ in
                        Task {@MainActor in self?.musicTick()}
                    }
                case .failure(let error):
                    self.musicSession=nil;self.musicStatus=error.localizedDescription
                }
            }
        }
    }
    func stopMusic(reason:String=T("Музыка остановлена. Подсветка возвращена к настройкам локального профиля."),resume:Bool=false,restoreLighting:Bool=true) {
        if !resume{pendingMusicResume=nil}
        guard let session=musicSession else{return}
        pendingMusicResume=resume ? session.target:nil
        session.cancel();musicSession=nil;musicTimer?.invalidate();musicTimer=nil
        let wasActive=musicActive
        musicActive=false;musicStarting=false;musicStopping=true
        musicLevels=Array(repeating:0,count:18);musicDecibels = -120;musicStatus=T("Останавливаю…")
        let restore=restoreLighting && keyboardLink.contains(session.target) && configurationReady ? try? ProtocolCore.lighting(profile):nil
        let group=DispatchGroup();musicCleanup=group
        group.enter();musicControlQueue.async {session.capture.stop();group.leave()}
        group.enter();queue.async {
            if wasActive,restoreLighting {
                try? session.output.send(Array(repeating:0,count:18),foreground:1,background:0,brightness:0)
            }
            session.output.close()
            var restoreError:String?
            if wasActive,let restore {do{_ = try HIDTransport().send(restore,expectedRegistryID:session.target.registryID,cancellation:session.connection)}catch{restoreError=error.localizedDescription}}
            if let restoreError {DispatchQueue.main.async{self.musicStatus=T("Музыка остановлена. Подсветку не удалось восстановить: \(restoreError). \(reason)")}}
            group.leave()
        }
        group.notify(queue:.main) {
            guard self.musicCleanup===group else{return}
            self.musicStopping=false;self.musicWriteInFlight=false;self.musicCleanup=nil
            if !self.musicStatus.hasPrefix(T("Музыка остановлена. Подсветку не удалось")) {self.musicStatus=reason}
            if resume,self.keyboardLink.contains(session.target),self.canWrite {self.startMusic()}
        }
    }
    private func musicTick() {
        guard musicActive,let session=musicSession,!session.isCancelled else{return}
        let spectrum=session.capture.analyzer.snapshot()
        musicLevels=spectrum.levels;musicDecibels=spectrum.decibels
        if Date()>=nextMusicDeviceCheck {
            nextMusicDeviceCheck=Date().addingTimeInterval(2)
            if SystemAudioCapture.defaultOutput() != session.capture.outputID {
                stopMusic(reason:T("Переключаюсь на новое устройство вывода звука…"),resume:true);return
            }
        }
        guard !busy else{musicStatus=T("Передача музыки приостановлена на время записи настроек или картинки.");return}
        guard !musicWriteInFlight else{return}
        let foreground=musicForeground,background=musicBackground,brightness=Int(musicBackgroundBrightness.rounded())
        musicWriteInFlight=true
        queue.async {
            guard !session.isCancelled else{return}
            let result=Result {try session.output.send(spectrum.levels,foreground:foreground,background:background,brightness:brightness,cancellation:session.cancellation)}
            let frames=session.output.framesSent
            DispatchQueue.main.async {
                guard self.musicSession===session,!session.isCancelled,self.keyboardLink.contains(session.target) else{return}
                self.musicWriteInFlight=false
                switch result {
                case .success:
                    self.musicFramesSent=frames
                    self.musicStatus=spectrum.decibels < -80 ? T("Тишина. Включи музыку на Mac; спектр на L99 появится в плеере."):T("Музыкальные уровни передаются на экран и подсветку L99.")
                case .failure(let error):self.stopMusic(reason:"Музыкальная передача остановлена: \(error.localizedDescription)")
                }
            }
        }
    }
    private func shutdownMusic() {
        guard let session=musicSession else{_ = musicCleanup?.wait(timeout:.now()+2);return}
        session.cancel();musicSession=nil;musicTimer?.invalidate()
        // A pending permission request has not changed the keyboard's lighting.
        guard musicActive else{return}
        let restore=configurationReady && !isSleeping ? try? ProtocolCore.lighting(profile):nil
        musicControlQueue.sync {session.capture.stop()}
        queue.sync {
            if restore != nil {try? session.output.send(Array(repeating:0,count:18),foreground:1,background:0,brightness:0)}
            session.output.close()
            if let restore {_ = try? HIDTransport().send(restore,expectedRegistryID:session.target.registryID,cancellation:session.connection)}
        }
    }
    func syncRealtimeNow() {
        guard connected else{return}
        clockPending=true;nextRealtimeSend = .distantPast;realtimeTick()
    }
    private func realtimeTick() {
        guard !isSleeping,!busy,!metricsInFlight else{return}
        metricsInFlight=true
        let ticket=UUID();metricsTicket=ticket
        let target=keyboardLink.target,lifetime=keyboardLifetime
        let send=configurationReady && target != nil && Date()>=nextRealtimeSend && (clockPending || liveMetrics)
        let metricsSampler=sampler,started=Date()
        if send {realtimeSending=true}
        queue.async { [self] in
            var snapshot=metricsSampler.sample()
            let result:Result<Void,Error>=Result {
                if send,let target {
                    try lifetime.check()
                    snapshot=MacMetrics(date:Date(),cpu:snapshot.cpu,gpu:snapshot.gpu,cpuTemperature:snapshot.cpuTemperature,gpuTemperature:snapshot.gpuTemperature,temperatureSource:snapshot.temperatureSource)
                    _ = try HIDTransport().send(snapshot.packets(),expectedRegistryID:target.registryID,cancellation:lifetime)
                }
            }
            DispatchQueue.main.async {
                guard self.metricsTicket==ticket else{return}
                self.metricsTicket=nil;self.metricsInFlight=false;self.realtimeSending=false;self.metrics=snapshot
                guard send,let target,self.keyboardLink.contains(target),!lifetime.isCancelled else{return}
                switch result {
                case .success:
                    self.clockPending=false;self.realtimeFailures=0;self.lastRealtimeUpdate=Date();self.nextRealtimeSend=started.addingTimeInterval(5)
                    self.realtimeStatus=self.liveMetrics ? T("Данные отправляются на L99 каждые 5 секунд."):T("Время, дата и показатели отправлены на L99.")
                case .failure(let error):
                    self.realtimeFailures+=1
                    self.nextRealtimeSend=Date().addingTimeInterval(self.realtimeFailures<3 ? 10:30)
                    self.realtimeStatus=T("Передача не завершена: \(error.localizedDescription) Повторю после паузы.")
                    self.scan()
                }
            }
        }
    }
    func startSelectingKey() {
        stopRecording();selectingKey=true
        keySelector.start { [weak self] usage in
            guard let self else{return}
            self.selectingKey=false
            if let key=self.keys.first(where:{$0.usage==usage}) {self.selectedKey=key.id}
        } cancelled:{[weak self] in self?.selectingKey=false}
    }
    func stopSelectingKey(){keySelector.stop();selectingKey=false}
    func updateMacro(_ id:UUID,edit:(inout LocalMacro)->Void) {
        guard let i=profile.macros.firstIndex(where:{$0.id==id}) else{return}
        var macro=profile.macros[i];edit(&macro);profile.macros[i]=macro
    }
    func startRecording(_ id: UUID) {
        stopRecording();stopSelectingKey()
        guard !busy,profile.macros.contains(where:{$0.id==id}) else{return}
        recording=true
        recorder.stopped={[weak self] in self?.recording=false}
        recorder.start{[weak self] usage,down,delay,reserved in
            guard let self,let index=self.profile.macros.firstIndex(where:{$0.id==id}) else{return false}
            guard MacroMemory.canAppend(1+reserved,to:id,in:self.profile) else {
                self.error=T("Память макросов заполнена. Запись завершена с отпусканием удерживаемых клавиш.");return false
            }
            var macro=self.profile.macros[index]
            if let last=macro.steps.indices.last {macro.steps[last].delay=delay}
            macro.steps.append(MacroStep(action:down ? "Key down":"Key up",usage:usage,delay:50))
            self.profile.macros[index]=macro;return true
        }
    }
    func stopRecording(){recorder.stop();recording=false}
    func binding(for key: Int) -> KeyBinding {
        profile.bindings.first {$0.keyID == key && $0.fnLayer == fnLayer} ?? KeyBinding(keyID:key,fnLayer:fnLayer)
    }
    func setBinding(_ value: KeyBinding) {
        var copy=profile
        copy.bindings.removeAll {$0.keyID == value.keyID && $0.fnLayer == value.fnLayer}
        copy.bindings.append(value);profile=copy
    }
    func apply(_ kind: Section) {
        guard canWrite else { return }
        stopRecording()
        if kind == .light || kind == .custom {stopMusic(reason:T("Музыка остановлена для применения подсветки."))}
        do {
            try validate(profile)
            let packets: [WirePacket]
            switch kind {
            case .light:packets=try ProtocolCore.lighting(profile)
            case .keys:
                packets=try ProtocolCore.assignmentUpdate(profile,fnLayer:fnLayer)
            case .custom:packets=try ProtocolCore.custom(profile,keys:keys)
            case .macros:packets=try ProtocolCore.macroUpdate(profile)
            case .settings:packets=try ProtocolCore.settings(profile)
            default:return
            }
            guard let target=keyboardLink.target else{return}
            var committed:Set<String>=[kind == .keys ? (fnLayer ? "fn":"main"):kind == .light ? "lighting":kind == .custom ? "custom":kind == .macros ? "macros":"settings"]
            if kind == .keys,profile.bindings.contains(where:{$0.kind==4 && $0.fnLayer==fnLayer}){committed.insert("macros")}
            // Only clear a layer's pending marker when its entire desired table was sent.
            if kind == .macros || kind == .keys {
                let written=try ConfigurationWrite(packets:packets,revision:profileRevision,committed:[])
                for (fn,code) in [(false,UInt8(0x11)),(true,UInt8(0x27))] {
                    if let actual=written.regions[code] {
                        let desired=try ProtocolCore.keymap(profile,fnLayer:fn)[2..<11].flatMap(\.payload)
                        if actual.prefix(574)==Data(desired.prefix(574)) {committed.insert(fn ? "fn":"main")}
                    }
                }
            }
            let verification=try ConfigurationWrite(packets:packets,revision:profileRevision,committed:committed)
            keyboardLink.needsRead();configurationReady=false
            let operation=beginOperation(.keyboard,target:target);status=T("Передаю настройки…");saveSessionNow()
            queue.async {
                let result=Result {try HIDTransport().send(packets,expectedRegistryID:target.registryID,cancellation:operation.cancellation)}
                DispatchQueue.main.async {
                    guard self.finishOperation(operation) else{return}
                    switch result {
                    case .success(let entries):
                        self.logs.append(contentsOf:entries)
                        self.status=T("\(L(kind.rawValue)): пакеты приняты. Проверяю записанные настройки…")
                        self.readDeviceConfiguration(verifying:verification)
                    case .failure(let error):
                        self.error=error.localizedDescription;self.logs.append(error.localizedDescription)
                        self.status=T("Передача остановлена. Правки сохранены; читаю состояние L99.")
                        self.readDeviceConfiguration()
                    }
                }
            }
        } catch { self.error=error.localizedDescription }
    }
    func saveProfile() {
        let panel=NSSavePanel();panel.allowedContentTypes=[.json];panel.nameFieldStringValue="L99-profile.json"
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {try validate(profile);let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];try encoder.encode(profile).write(to:url,options:.atomic);status=T("Профиль сохранён: \(url.lastPathComponent)")}
        catch {self.error=error.localizedDescription}
    }
    func loadProfile() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {var value=try JSONDecoder().decode(Profile.self,from:Data(contentsOf:url));value.deviceConfiguration=profile.deviceConfiguration;try validate(value);stopRecording();stopSelectingKey();profile=value;pendingSections.formUnion(["lighting","settings","main","fn","macros","custom"]);saveSessionNow();status=T("Профиль открыт. Изменения отправляются кнопкой назначения или применения.")}
        catch {self.error=error.localizedDescription}
    }
    func exportPackets(_ section: Section) {
        do {
            try validate(profile)
            let packets: [WirePacket]
            switch section {
            case .light:packets=try ProtocolCore.lighting(profile)
            case .keys:packets=try ProtocolCore.assignmentUpdate(profile,fnLayer:fnLayer)
            case .custom:packets=try ProtocolCore.custom(profile,keys:keys)
            case .macros:packets=try ProtocolCore.macroUpdate(profile)
            case .settings:packets=try ProtocolCore.settings(profile)
            default:return
            }
            let panel=NSSavePanel();panel.allowedContentTypes=[.json];panel.nameFieldStringValue="L99-\(section.id)-packets.json"
            guard panel.runModal() == .OK,let url=panel.url else{return}
            let data=try JSONSerialization.data(withJSONObject:["reportID":0,"payloadBytes":64,"hardwareValidated":false,"packets":packets.map{["payload":$0.payload.map{String(format:"%02x",$0)}.joined(),"acknowledgement":$0.acknowledgement] as [String:Any]}],options:[.prettyPrinted,.sortedKeys])
            try data.write(to:url,options:.atomic);status=T("Пакеты сохранены. В клавиатуру ничего не отправлено.")
        }catch{self.error=error.localizedDescription}
    }
    func exportDiagnostics() {
        let panel=NSSavePanel();panel.allowedContentTypes=[.json];panel.nameFieldStringValue="L99-diagnostics.json"
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {try transport.diagnosticJSON().write(to:url,options:.atomic)}catch{self.error=error.localizedDescription}
    }
    func importScreen() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.png,.jpeg,.gif];panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any] else {error=T("Не удалось прочитать изображение.");return}
        let frames=CGImageSourceGetCount(source)
        let width=properties[kCGImagePropertyPixelWidth] as? Int ?? 0,height=properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        screenImage=NSImage(contentsOf:url);screenURL=url
        if frames>1 {screenDestination = .animation}
        screenInfo=T("\(url.lastPathComponent) · \(width) × \(height) · \(frames) кадров") + ((width != 320 || height != 480 || frames>200) ? T(" · требуется подгонка") : "")
        refreshScreenPreview()
    }
    func refreshScreenPreview() {
        guard let url=screenURL,let src=CGImageSourceCreateWithURL(url as CFURL,nil),let image=CGImageSourceCreateThumbnailAtIndex(src,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:1024] as CFDictionary) else{return}
        do {let (_,preview)=try ScreenEncoder.render(image,fit:screenFit,rotation:screenRotation);screenImage=NSImage(cgImage:preview,size:NSSize(width:320,height:480))}catch{self.error=error.localizedDescription}
    }
    func uploadScreen() {
        guard canUploadScreen,let url=screenURL,let target=displayLink.target else{return}
        let fit=screenFit,rotation=screenRotation,destination=screenDestination
        let operation=beginOperation(.screen,target:target)
        screenProgress=0;status=T("Подготавливаю изображение…")
        queue.async {
            let result=Result { () -> (EncodedScreen,[String]) in
                let encoded=try ScreenEncoder.encode(url:url,fit:fit,rotation:rotation,animation:destination == .animation,cancellation:operation.cancellation){value in
                    DispatchQueue.main.async{if self.accepts(operation){self.screenProgress=value*0.15}}
                }
                try operation.cancellation.check()
                DispatchQueue.main.async{if self.accepts(operation){self.status=T("Загружаю на экран клавиатуры…")}}
                let log=try DisplayTransport(expectedRegistryID:target.registryID,cancellation:operation.cancellation).upload(encoded.data,to:destination){value in
                    DispatchQueue.main.async{if self.accepts(operation){self.screenProgress=0.15+value*0.85}}
                }
                return (encoded,log)
            }
            DispatchQueue.main.async {
                guard self.finishOperation(operation) else{return}
                switch result {
                case .success(let (_,log)):
                    self.logs += log;self.screenProgress=1
                    self.status=T("Картинка записана и проверена. Открой \(L(destination.rawValue)) на экране L99.")
                case .failure(let error):self.error=error.localizedDescription;self.status="Загрузка не завершена. Начни её заново после подключения USB.";self.scan()
                }
            }
        }
    }
    private func profileChanged(from old:Profile) {
        guard !restoringSession,!changingProfile else{return}
        changingProfile=true
        MacroAssignments.updateRepeats(from:old,in:&profile)
        changingProfile=false;profileRevision+=1
        if old.mode != profile.mode || old.colorHex != profile.colorHex || old.brightness != profile.brightness || old.speed != profile.speed || old.direction != profile.direction || old.colorful != profile.colorful {pendingSections.insert("lighting")}
        if old.disableWin != profile.disableWin || old.disableAltF4 != profile.disableAltF4 || old.disableAltTab != profile.disableAltTab || old.fnToggle != profile.fnToggle || old.sleepIndex != profile.sleepIndex || old.responseLevel != profile.responseLevel {pendingSections.insert("settings")}
        if old.keyColors != profile.keyColors {pendingSections.insert("custom")}
        for fn in [false,true] where old.bindings.filter({$0.fnLayer==fn}) != profile.bindings.filter({$0.fnLayer==fn}) {pendingSections.insert(fn ? "fn":"main")}
        if old.macros != profile.macros {pendingSections.insert("macros")}
        if !busy,!pendingSections.isEmpty {status=T("Локальные правки ожидают применения к L99.")}
        scheduleSessionSave()
    }
    private func savedSession()->SavedSession {
        SavedSession(profile:profile,music:MusicPreferences(foreground:musicForeground,background:musicBackground,brightness:musicBackgroundBrightness,sensitivity:musicSensitivity),pending:pendingSections.sorted(),syncClock:syncClockOnConnect,liveMetrics:liveMetrics,savedAt:Date())
    }
    func enableAutosave() {
        do {sessionAccess=try sessionStore.authorizeProjectFolder();if sessionAccess{saveSessionNow()}}
        catch{autosaveStatus=error.localizedDescription}
    }
    private func restoreLocalSession() {
        do {sessionAccess=try sessionStore.authorizeProjectFolder()}
        catch{autosaveStatus=error.localizedDescription}
        guard sessionAccess else{
            restoringSession=false;loadingSession=false
            autosaveStatus=T("Выбери папку проекта для автосохранения.");scan();return
        }
        let store=sessionStore,layout=keys
        sessionQueue.async {
            let result=Result {try store.restore(validate:{try ProfileValidation.validate($0.profile,keys:layout)})}
            DispatchQueue.main.async {
                switch result {
                case .success(let restored):
                    if let (value,recovered)=restored {
                        self.profile=value.profile;self.musicForeground=value.music.foreground;self.musicBackground=value.music.background
                        self.musicBackgroundBrightness=value.music.brightness;self.musicSensitivity=value.music.sensitivity
                        self.syncClockOnConnect=value.syncClock;self.liveMetrics=value.liveMetrics;self.pendingSections=Set(value.pending)
                        self.autosaveStatus=recovered ? T("Профиль восстановлен из резервной копии."):T("Последний профиль восстановлен.")
                    }else{self.autosaveStatus=T("Автосохранение включено.")}
                case .failure(let error):self.autosaveStatus="Не удалось восстановить профиль: \(error.localizedDescription)"
                }
                self.restoringSession=false;self.loadingSession=false;self.scan()
            }
        }
    }
    private func scheduleSessionSave() {
        guard !restoringSession,!changingProfile else{return}
        saveWork?.cancel()
        let work=DispatchWorkItem{[weak self] in self?.saveSessionNow()};saveWork=work
        DispatchQueue.main.asyncAfter(deadline:.now()+0.4,execute:work)
    }
    private func saveSessionNow(wait:Bool=false) {
        guard !restoringSession,sessionAccess else{return}
        saveWork?.cancel();saveWork=nil
        do {
            try validate(profile)
            let value=savedSession(),store=sessionStore,layout=keys
            let operation:@Sendable ()->Void={
                let result=Result {try store.save(value,validate:{try ProfileValidation.validate($0.profile,keys:layout)})}
                DispatchQueue.main.async {
                    switch result {
                    case .success:self.autosaveStatus="Профиль сохранён автоматически."
                    case .failure(let error):self.autosaveStatus="Автосохранение не завершено: \(error.localizedDescription)"
                    }
                }
            }
            if wait {sessionQueue.sync(execute:operation)}else{sessionQueue.async(execute:operation)}
        }catch{autosaveStatus=T("Автосохранение не завершено: \(error.localizedDescription)")}
    }
    func readDeviceConfiguration(replaceDraft:Bool=false,automatic:Bool=false,verifying:ConfigurationWrite?=nil) {
        guard connected,!busy,let target=keyboardLink.beginRead(now:Date(),manual:!automatic) else{return}
        if replaceDraft {saveSessionNow()}
        let revision=profileRevision,operation=beginOperation(.keyboard,target:target)
        configurationReady=false;stopRecording();stopSelectingKey();status=T("Читаю настройки L99…")
        queue.async {
            let result=Result {try DeviceConfiguration.read(channel:SettingsFeatureChannel(expectedRegistryID:target.registryID,cancellation:operation.cancellation)){part in
                DispatchQueue.main.async{if self.accepts(operation){self.status=T("Читаю L99: \(part)…")}}
            }}
            DispatchQueue.main.async {
                guard self.finishOperation(operation) else{return}
                switch result {
                case .success(let raw):
                    do {
                        let incoming=try raw.decoded(previous:self.profile,keys:self.keys)
                        try self.validate(incoming)
                        let matched=try verifying?.matches(raw) ?? true
                        var pending=self.pendingSections
                        if let verifying,matched,self.profileRevision==verifying.revision {pending.subtract(verifying.committed)}
                        let discard=replaceDraft && self.profileRevision==revision
                        let reconciled=try ProfileReconciliation.merge(incoming:incoming,draft:self.profile,pending:discard ? []:pending)
                        try self.validate(reconciled.0)
                        self.restoringSession=true;self.profile=reconciled.0;self.restoringSession=false
                        self.pendingSections=reconciled.1
                        guard self.keyboardLink.readSucceeded(target) else{return}
                        self.configurationReady=true;self.lastConfigurationRead=raw.readAt
                        self.logs.append(verifying==nil ? "Configuration read and checksums verified.":matched ? "Configuration write verified by readback.":"Configuration readback differs; local draft retained.")
                        if !matched {
                            self.status=T("Проверка записи не совпала с L99. Локальные правки сохранены и ждут повторного применения.")
                            self.error=T("L99 приняла команды, но прочитанные настройки отличаются. Автоматически повторять запись не буду; твои правки сохранены.")
                        }else{
                            self.status=self.pendingSections.isEmpty ? (verifying==nil ? T("Настройки L99 прочитаны. Все контрольные суммы совпали."):T("Настройки записаны и проверены чтением с L99.")):T("Настройки L99 прочитаны. Локальные правки сохранены и ожидают применения.")
                        }
                        self.saveSessionNow()
                    }catch{
                        self.keyboardLink.readFailed(target,now:Date(),retry:false)
                        self.status=T("Не удалось разобрать настройки L99: \(error.localizedDescription) Нажми «Загрузить с L99» для повторного чтения.")
                    }
                case .failure(let error):
                    self.keyboardLink.readFailed(target,now:Date())
                    self.status=T("Чтение L99 не завершено: \(error.localizedDescription) Повторю через \(Int(max(1,self.keyboardLink.nextRead.timeIntervalSinceNow.rounded(.up)))) с.")
                    self.scan()
                }
            }
        }
    }
    func validate(_ p:Profile)throws{try ProfileValidation.validate(p,keys:keys)}
}

enum ProfileValidation {
    static func validate(_ p:Profile,keys:[PhysicalKey])throws {
        let keyIDs=Set(keys.map(\.id))
        guard p.formatVersion==1,(0...128).contains(p.mode),(0...5).contains(p.brightness),(0...5).contains(p.speed),(0...3).contains(p.direction),(0...3).contains(p.sleepIndex),(1...5).contains(p.responseLevel),p.colorHex.count==6,UInt32(p.colorHex,radix:16) != nil,p.bindings.count<=242,p.macros.count<=100,p.macros.reduce(0,{$0+$1.steps.count})<=337 else {throw L99Error.message(T("Формат профиля не поддерживается или превышен предел числа действий."))}
        var used=Set<String>()
        for b in p.bindings {
            guard keyIDs.contains(b.keyID),(0...5).contains(b.kind),(0...255).contains(b.modifiers),(0...65535).contains(b.usage),b.kind != 2 || b.usage<=255,used.insert(b.id).inserted else {throw L99Error.message(T("Некорректное или повторное назначение клавиши."))}
            if let raw=b.rawEntry,raw.count != 4 {throw L99Error.message(T("Неверный исходный код назначения."))}
            if b.kind==5 && b.rawEntry==nil {throw L99Error.message(T("Не хватает данных исходного назначения."))}
            if b.kind==4 && (b.macroID==nil || !p.macros.contains(where:{$0.id==b.macroID})) {throw L99Error.message(T("Макрос, назначенный клавише, отсутствует в профиле."))}
        }
        try p.deviceConfiguration?.validate()
        guard Set(p.macros.map(\.id)).count==p.macros.count else{throw L99Error.message(T("Повторные идентификаторы макросов."))}
        _ = try MacroMemory.slots(p)
        guard p.keyColors.allSatisfy({Int($0.key).map(keyIDs.contains) == true && $0.value.count==6 && UInt32($0.value,radix:16) != nil}),p.macros.allSatisfy({(1...255).contains($0.repeatCount) && $0.steps.count<=1000 && $0.steps.allSatisfy({(0...255).contains($0.usage) && (0...60000).contains($0.delay) && ["Key down","Key up","Mouse down","Mouse up"].contains($0.action) && (!$0.action.hasPrefix("Mouse") || [1,2,4].contains($0.usage))})}) else {throw L99Error.message(T("Некорректные цвета или макросы в профиле."))}
    }
}
