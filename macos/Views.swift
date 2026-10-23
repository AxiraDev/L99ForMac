// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import SwiftUI
import AppKit

private let accent=Color(red:0.0,green:0.72,blue:0.96)

struct SupportSheet:View {
    @EnvironmentObject private var language:LanguageSettings
    @Environment(\.dismiss) private var dismiss
    private let configuration=SupportConfiguration.load()
    var body:some View {
        let _=language.selection
        VStack(alignment:.leading,spacing:20) {
            Label(T("Поддержать разработчика"),systemImage:"heart.fill").font(.title2).foregroundStyle(accent)
            Text(T("Если L99 for Mac тебе полезно, ты можешь поддержать его разработку добровольным донатом."))
            Text(T("Все функции доступны бесплатно. Поддержка не открывает дополнительных возможностей.")).font(.callout).foregroundStyle(.secondary)
            if let url=configuration.url {
                Text(T("Страница оплаты откроется в браузере. Приложение не получает данные твоей карты.")).font(.caption).foregroundStyle(.secondary)
                Text(url.host ?? "").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(T("Позже")){dismiss()}
                    Spacer()
                    Button(T("Перейти на страницу поддержки")){NSWorkspace.shared.open(url)}.buttonStyle(.borderedProminent)
                }
            }else{
                Text(T("Автор пока не добавил страницу поддержки. Она появится в следующем обновлении.")).font(.callout).foregroundStyle(.secondary)
                HStack {Spacer();Button(T("Закрыть")){dismiss()}.keyboardShortcut(.defaultAction)}
            }
        }.padding(28).frame(width:470).fixedSize(horizontal:false,vertical:true)
    }
}

struct Panel<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Text(title).font(.headline)
            content
        }.padding(20).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color.black.opacity(0.55),in:RoundedRectangle(cornerRadius:12))
            .overlay(RoundedRectangle(cornerRadius:12).stroke(.white.opacity(0.12)))
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var language:LanguageSettings
    @State private var showingSupport=false
    var body: some View {
        ZStack {
            LinearGradient(colors:[Color(red:0.05,green:0.07,blue:0.11),Color(red:0.02,green:0.035,blue:0.055)],startPoint:.topLeading,endPoint:.bottomTrailing)
            HStack(spacing:0) {
                sidebar
                VStack(alignment:.leading,spacing:20) {
                    header
                    ScrollView {
                        content.padding(.bottom,12).disabled(model.loadingSession)
                    }.scrollIndicators(.hidden)
                    footer
                }.padding(.horizontal,28).padding(.top,28).padding(.bottom,18)
            }
        }.clipped().tint(accent)
            .sheet(isPresented:$showingSupport){SupportSheet()}
            .alert("AULA L99",isPresented:Binding(get:{model.error != nil},set:{if !$0 {model.error=nil}})) {
                Button(T("OK")){model.error=nil}
            } message: {Text(L(model.error ?? ""))}
            .onReceive(Timer.publish(every:3,on:.main,in:.common).autoconnect()) {_ in model.scan() }
    }
    private var sidebar: some View {
        VStack(alignment:.leading,spacing:8) {
            if let shark=NSImage(contentsOf:model.resourceURL.appendingPathComponent("branding/shark.png")) {
                Image(nsImage:shark).resizable().scaledToFit().frame(width:85,height:60).padding(.bottom,2)
            }
            Text("L99").font(.system(size:32,weight:.semibold,design:.rounded)).tracking(2)
            Text("FOR MAC").font(.caption).tracking(3).foregroundStyle(.secondary).padding(.bottom,14)
            ForEach(Section.allCases) { section in
                Button {model.section=section} label: {
                    Label(L(section.rawValue),systemImage:section.icon)
                        .font(.system(size:13,weight:model.section==section ? .semibold:.regular))
                        .frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,9).padding(.horizontal,12)
                        .background(model.section==section ? accent.opacity(0.2):.clear,in:RoundedRectangle(cornerRadius:8))
                        .foregroundStyle(model.section==section ? .white:.white.opacity(0.65))
                }.buttonStyle(.plain)
            }
            Spacer(minLength:16)
            Picker(T("Язык"),selection:$language.selection) {
                Text(T("Как в macOS")).tag(AppLanguage.system)
                Text("Русский").tag(AppLanguage.ru)
                Text("English").tag(AppLanguage.en)
                Text("简体中文").tag(AppLanguage.zhHans)
            }.labelsHidden().pickerStyle(.menu).help(T("Язык приложения"))
            Button {showingSupport=true} label:{Label(T("Поддержать"),systemImage:"heart")}
                .buttonStyle(.bordered).frame(maxWidth:.infinity,alignment:.leading)
                .help(T("Поддержать разработчика"))
            Text(T("Версия \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "dev")")).font(.system(size:10,weight:.bold)).tracking(2).foregroundStyle(accent)
            Text(T("Независимое приложение · USB")).font(.system(size:10)).foregroundStyle(.secondary)
        }.padding(.horizontal,18).padding(.top,36).padding(.bottom,24).frame(width:200)
            .background(.black.opacity(0.65))
    }
    private var header: some View {
        HStack(alignment:.top) {
            VStack(alignment:.leading,spacing:6) {
                Text(L(model.section.rawValue)).font(.system(size:28,weight:.semibold))
                Text(T("AULA L99 · проводное подключение")).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing:8) {
                let attached=model.section == .screen ? model.displayConnected:model.connected
                Circle().fill(attached ? Color.green:Color.orange).frame(width:7,height:7)
                Text(attached ? (model.section == .screen ? T("Экран подключён по USB"):T("USB подключён")):T("Ожидание USB")).font(.caption)
            }.padding(.horizontal,12).padding(.vertical,9).background(.white.opacity(0.06),in:Capsule())
        }
    }
    @ViewBuilder private var content: some View {
        switch model.section {
        case .home:HomePane()
        case .keys:KeysPane()
        case .light:LightingPane()
        case .settings:SettingsPane()
        case .macros:MacroPane()
        case .custom:CustomColorsPane()
        case .screen:ScreenPane()
        case .realtime:RealtimePane()
        case .music:MusicPane()
        }
    }
    private var footer: some View {
        HStack(spacing:14) {
            if model.busy {ProgressView().controlSize(.small)}
            VStack(alignment:.leading,spacing:3) {
                Text(L(model.status)).lineLimit(2)
                Text(L(model.autosaveStatus)).lineLimit(1)
            }.font(.caption).foregroundStyle(.secondary)
            Spacer(minLength:8)
            Button(T("Загрузить с L99")){model.readDeviceConfiguration(replaceDraft:true)}
                .disabled(!model.connected).help(T("Заменить локальные правки настройками клавиатуры. Предыдущий профиль останется в резервной копии."))
            Button(T("Открыть профиль"),action:model.loadProfile)
            Button(T("Сохранить профиль"),action:model.saveProfile)
        }.font(.caption).disabled(model.busy || model.loadingSession)
    }
}

struct KeyboardCanvas: View {
    @EnvironmentObject private var language:LanguageSettings
    @EnvironmentObject var model: AppModel
    var showColors=false
    var body: some View {
        let _=language.selection
        GeometryReader { geo in
            let scale=geo.size.width/800
            ZStack(alignment:.topLeading) {
                RoundedRectangle(cornerRadius:14*scale).fill(Color(red:0.09,green:0.11,blue:0.14))
                    .overlay(RoundedRectangle(cornerRadius:14*scale).stroke(.white.opacity(0.15)))
                    .frame(width:geo.size.width,height:300*scale).allowsHitTesting(false)
                RoundedRectangle(cornerRadius:8*scale).fill(.black.opacity(0.8)).overlay(RoundedRectangle(cornerRadius:8*scale).stroke(accent.opacity(0.22)))
                    .frame(width:120*scale,height:195*scale).position(x:720*scale,y:177*scale).allowsHitTesting(false)
                VStack(spacing:6) {Image(systemName:"display");Text("IPS").font(.system(size:10))}.foregroundStyle(.white.opacity(0.25))
                    .position(x:720*scale,y:177*scale).allowsHitTesting(false)
                ForEach(model.keys) { key in
                    let modified=model.profile.bindings.contains {$0.keyID==key.id && $0.fnLayer==model.fnLayer}
                    Button {model.selectedKey=key.id} label: {
                        KeycapView(key:key,scale:scale,selected:model.selectedKey==key.id,fill:keyFill(key,modified:modified))
                    }.buttonStyle(.plain)
                        .frame(width:CGFloat(key.width)*scale,height:CGFloat(key.height)*scale)
                        .contentShape(RoundedRectangle(cornerRadius:5*scale))
                        .position(x:Double(key.x+key.width/2)*scale,y:Double(key.y+key.height/2)*scale)
                        .help(key.name + (modified ? T(" · изменена"):""))
                        .accessibilityLabel(Text(T("Клавиша \(key.name)")))
                }
            }
        }.aspectRatio(8/3,contentMode:.fit)
    }
    private func keyFill(_ key: PhysicalKey, modified: Bool) -> Color {
        if showColors,let hex=model.profile.keyColors[String(key.id)] {return Color(nsColor:NSColor(hex:hex)).opacity(0.65)}
        if model.selectedKey==key.id {return accent.opacity(0.28)}
        return modified ? accent.opacity(0.3):Color(red:0.16,green:0.18,blue:0.22)
    }
}

private struct KeycapView: View {
    var key: PhysicalKey
    var scale: CGFloat
    var selected: Bool
    var fill: Color
    var body: some View {
        let size=CGFloat(key.name.count>5 ? 8:10)*scale
        let stroke: Color=selected ? accent:Color.white.opacity(0.16)
        ZStack {
            RoundedRectangle(cornerRadius:5*scale).fill(fill)
            RoundedRectangle(cornerRadius:5*scale).stroke(stroke,lineWidth:selected ? 2:0.7)
            Text(key.name).font(.system(size:size,weight:.medium))
                .foregroundStyle(.white.opacity(0.82)).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal,2)
        }.frame(width:CGFloat(key.width)*scale,height:CGFloat(key.height)*scale)
    }
}

struct HomePane: View {
    @EnvironmentObject private var language:LanguageSettings
    @EnvironmentObject var model: AppModel
    var body: some View {
        let _=language.selection
        VStack(spacing:20) {
            Panel(title:T("Твоя клавиатура")) {
                KeyboardCanvas()
                HStack {
                    VStack(alignment:.leading,spacing:6) {
                        Text("AULA L99").font(.title2).bold()
                        Text(T("Основной и Fn-слой · RGB · IPS 320 × 480")).foregroundStyle(.secondary).font(.caption)
                    }
                    Spacer()
                    Button(T("Настроить клавиши")){model.section = .keys}.buttonStyle(.borderedProminent)
                }
            }
            HStack(alignment:.top,spacing:18) {
                Panel(title:T("Локальный профиль")) {
                    TextField(T("Название"),text:$model.profile.name)
                    if !model.sessionAccess {Button(T("Выбрать папку профиля"),action:model.enableAutosave)}
                    Text(T("Профиль и настройки музыки сохраняются автоматически. Локальные правки ждут нажатия «Применить». Файл профиля можно сохранить отдельно."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Panel(title:T("Настройка по USB")) {
                    Text(model.configurationReady ? T("Текущие назначения, макросы, подсветка и настройки прочитаны с L99."):T("При подключении приложение сначала читает текущие настройки L99."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(T("Настройки записываются по кнопке. Время и показатели Mac могут обновляться автоматически в Real-time Data."))
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }
}

struct ApplyBar: View {
    @EnvironmentObject private var language:LanguageSettings
    @EnvironmentObject var model: AppModel
    var section: Section
    var prepare:(()->Bool)?=nil
    var enabled=true
    var body: some View {
        let _=language.selection
        HStack {
            Text(T("Изменения отправляются по кнопке «Применить»"))
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(T("Экспорт пакетов")){if prepare?() ?? true {model.exportPackets(section)}}.disabled(model.busy || !enabled)
            Button(T("Применить к клавиатуре")){if prepare?() ?? true {model.apply(section)}}.buttonStyle(.borderedProminent).disabled(!model.canWrite || !enabled)
        }
    }
}

struct KeysPane:View {
    @EnvironmentObject private var language:LanguageSettings
    @EnvironmentObject var model:AppModel
    @State private var draft=AssignmentDraft()
    @State private var testInput=""
    @StateObject private var inputCheck=InputCheckModel()
    private var media:[(Int,String)]=[(0xcd,T("Воспроизведение / пауза")),(0xb7,T("Стоп")),(0xb6,T("Предыдущий трек")),(0xb5,T("Следующий трек")),(0xe9,T("Громче")),(0xea,T("Тише")),(0xe2,T("Выключить звук"))]
    private var selectedBinding:KeyBinding? {model.selectedKey.map{model.binding(for:$0)}}
    private var selectedIsFn:Bool {model.keys.first{$0.id==model.selectedKey}?.name=="Fn"}
    private var validEditor:Bool {
        guard let key=model.selectedKey,!selectedIsFn else{return true}
        return (try? draft.binding(keyID:key,fnLayer:model.fnLayer,profile:model.profile)) != nil
    }
    private var editorError:String? {
        guard let key=model.selectedKey,!selectedIsFn else{return nil}
        do{_ = try draft.binding(keyID:key,fnLayer:model.fnLayer,profile:model.profile);return nil}catch{return error.localizedDescription}
    }
    private var changed:Bool {
        guard let current=selectedBinding else{return false}
        return (try? draft.binding(keyID:current.keyID,fnLayer:current.fnLayer,profile:model.profile)) != current
    }
    var body:some View {
        let _=language.selection
        VStack(spacing:18) {
            Panel(title:T("Выбери клавишу")) {
                HStack(spacing:20) {
                    Picker(T("Слой"),selection:$model.fnLayer){Text(T("Основной")).tag(false);Text(T("Fn-слой")).tag(true)}.pickerStyle(.segmented).frame(width:280)
                    Picker(T("Клавиша"),selection:$model.selectedKey) {
                        Text(T("Выбери…")).tag(nil as Int?)
                        ForEach(model.keys.sorted{($0.y,$0.x)<($1.y,$1.x)}){Text($0.name).tag(Optional($0.id))}
                    }.frame(width:230)
                    Button(model.selectingKey ? T("Отменить выбор"):T("Выбрать нажатием…")) {
                        if model.selectingKey {model.stopSelectingKey()}else{model.startSelectingKey()}
                    }
                    Spacer(minLength:0)
                }
                Text(model.selectingKey ? T("Нажми нужную клавишу, пока это окно активно. Esc — отменить."):T("Выбери клавишу в списке, на схеме ниже или кнопкой «Выбрать нажатием…».")).font(.caption).foregroundStyle(.secondary)
                if model.fnLayer {Text(T("Fn-слой срабатывает с физической Fn на L99. При обычном режиме удерживай Fn вместе с назначенной клавишей.")).font(.caption).foregroundStyle(.secondary)}
            }
            Panel(title:model.selectedKey.flatMap{id in model.keys.first{$0.id==id}?.name}.map{T("Назначение: ")+$0} ?? T("Нажми клавишу на схеме")) {
                if let keyID=model.selectedKey {
                    if selectedIsFn {Text(T("Переназначение самой клавиши Fn требует дополнительной проверки.")).font(.caption).foregroundStyle(.secondary)}
                    else{
                        HStack(alignment:.top,spacing:24) {
                            Picker(T("Действие"),selection:Binding(get:{draft.kind},set:{draft.selectKind($0,profile:model.profile)})) {
                                Text(T("Стандартное")).tag(0);Text(T("Отключить")).tag(1);Text(T("Другая клавиша")).tag(2);Text(T("Мультимедиа")).tag(3);Text(T("Макрос")).tag(4)
                                if draft.kind==5 {Text(T("Текущее действие")).tag(5)}
                            }.frame(width:220)
                            if draft.kind==2 {
                                VStack(alignment:.leading,spacing:12) {
                                    Picker(T("Клавиша"),selection:$draft.usage) {
                                        ForEach(model.keys.filter{$0.name != "Fn"}.sorted{$0.name<$1.name}){Text($0.name).tag($0.usage)}
                                        if !model.keys.contains(where:{$0.usage==draft.usage}) {Text("HID \(draft.usage)").tag(draft.usage)}
                                    }.frame(width:220)
                                    HStack{modifier("Ctrl",bit:1);modifier("Shift",bit:2);modifier("⌥",bit:4);modifier("⌘",bit:8)}
                                }
                            }else if draft.kind==3 {
                                Picker(T("Команда"),selection:$draft.usage) {
                                    ForEach(media,id:\.0){Text(L($0.1)).tag($0.0)}
                                    if !media.contains(where:{$0.0==draft.usage}) {Text("HID \(draft.usage)").tag(draft.usage)}
                                }.frame(width:250)
                            }else if draft.kind==4 {
                                VStack(alignment:.leading,spacing:12) {
                                    if model.profile.macros.isEmpty {Button(T("Создать макрос")){model.section = .macros}}
                                    else{
                                        Picker(T("Макрос"),selection:$draft.macroID) {
                                            Text(T("Выбери макрос")).tag(nil as UUID?)
                                            ForEach(model.profile.macros){Text($0.name).tag(Optional($0.id))}
                                            if let id=draft.macroID,!model.profile.macros.contains(where:{$0.id==id}) {Text(T("Макрос удалён")).tag(Optional(id))}
                                        }.frame(width:230)
                                    }
                                    Stepper(T("Повторов на этой клавише: \(draft.repeatCount)"),value:$draft.repeatCount,in:1...255)
                                    if !validEditor {Text(T("Выбери макрос с действиями.")).font(.caption).foregroundStyle(.orange)}
                                }
                            }
                            if draft.kind==5 {Text(T("Это действие сохранено без изменений. Для замены выбери другое в списке.")).font(.caption).foregroundStyle(.secondary).frame(maxWidth:240)}
                            Spacer(minLength:0)
                            VStack(alignment:.trailing,spacing:10) {
                                Button(T("Назначить на \(model.keys.first{$0.id==keyID}?.name ?? T("клавишу"))")){if saveDraft(){model.apply(.keys)}}
                                    .buttonStyle(.borderedProminent).disabled(!model.canWrite || !validEditor)
                                Button(T("Сохранить назначение")){_ = saveDraft()}.disabled(!validEditor)
                            }
                        }
                        if draft.kind != 4,let message=editorError {Text(message).font(.caption).foregroundStyle(.orange)}
                        if changed {Text(T("Есть изменения в редакторе. «Применить» сохранит и отправит видимое назначение.")).font(.caption).foregroundStyle(.orange)}
                    }
                }
                Text(T("«Назначить» и «Применить» отправляют назначения выбранного слоя. «Сохранить назначение» оставляет правку в локальном профиле.")).font(.caption).foregroundStyle(.secondary)
                Text(T("Остальные назначения сохраняются по снимку, прочитанному с клавиатуры.")).font(.caption).foregroundStyle(.secondary)
            }
            Panel(title:T("Схема клавиатуры")){KeyboardCanvas()}
            ApplyBar(section:.keys,prepare:saveDraft,enabled:validEditor)
            Panel(title:T("Проверка ввода")) {
                Text(T("Нажми назначенную клавишу в поле ниже. Для Fn-слоя удерживай Fn на самой L99. Текст остаётся в этом окне и не сохраняется в профиль.")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    TextField(T("Поле для проверки клавиатуры"),text:$testInput).textFieldStyle(.roundedBorder)
                    Button(T("Очистить")){testInput=""}.disabled(testInput.isEmpty)
                }
                HStack {
                    Button(T("Начать проверку событий")) {
                        model.stopSelectingKey();model.stopRecording();inputCheck.start()
                    }.disabled(inputCheck.active)
                    Button(T("Остановить проверку")){inputCheck.stop()}.disabled(!inputCheck.active)
                    Button(T("Очистить события")){inputCheck.clear()}.disabled(inputCheck.log.events.isEmpty)
                    Text(T("Событий: \(inputCheck.log.count) · Без отпускания: \(inputCheck.log.heldKeys.count+inputCheck.log.heldMouse.count)")).font(.caption).foregroundStyle(.secondary)
                }
                InputCheckPad(model:inputCheck).frame(height:100)
                Text(T("Проверка событий перехватывает клавиши только в активной области. Для мыши держи курсор внутри неё. Потеря фокуса окна или Esc останавливает проверку. Журнал не сохраняется.")).font(.caption).foregroundStyle(.secondary)
                ForEach(inputCheck.log.events.suffix(16)){event in Text(inputCheck.label(event,keys:model.keys)).font(.system(.caption,design:.monospaced)).textSelection(.enabled)}
            }
        }.onChange(of:selectedBinding){_,binding in if let binding{draft=AssignmentDraft(binding,profile:model.profile)}}
            .onAppear{if let binding=selectedBinding{draft=AssignmentDraft(binding,profile:model.profile)}}
            .onDisappear{model.stopSelectingKey();testInput="";inputCheck.clear()}
    }
    private func saveDraft()->Bool {
        guard let key=model.selectedKey,!selectedIsFn else{return true}
        do{
            let value=try draft.binding(keyID:key,fnLayer:model.fnLayer,profile:model.profile)
            if value != model.binding(for:key){model.setBinding(value);model.status=T("Назначение добавлено в локальный профиль.")}
            return true
        }catch{model.error=error.localizedDescription;return false}
    }
    private func modifier(_ name:String,bit:Int)->some View {
        Toggle(name,isOn:Binding(get:{draft.modifiers & bit != 0},set:{if $0{draft.modifiers |= bit}else{draft.modifiers &= ~bit}})).toggleStyle(.button)
    }
}

struct LightingPane: View {
    @EnvironmentObject private var language:LanguageSettings
    @EnvironmentObject var model: AppModel
    var body: some View {
        let _=language.selection
        VStack(spacing:18) {
            Panel(title:T("Режим подсветки")) {
                KeyboardCanvas()
                HStack(alignment:.top,spacing:36) {
                    VStack(alignment:.leading,spacing:18) {
                        Picker(T("Эффект"),selection:$model.profile.mode) {
                            Text(T("Выключить")).tag(0)
                            ForEach(1...18,id:\.self) {i in Text(i==11 ? T("Эффект 11 · по умолчанию"):T("Эффект \(i)")).tag(i)}
                            if model.profile.mode>18 {Text(T("Режим \(model.profile.mode) · с клавиатуры")).tag(model.profile.mode)}
                        }.frame(width:280)
                        ColorPicker(T("Цвет"),selection:Binding(get:{Color(nsColor:NSColor(hex:model.profile.colorHex))},set:{model.profile.colorHex=NSColor($0).hexRGB}),supportsOpacity:false).frame(width:280)
                        Toggle(T("Разноцветный режим"),isOn:$model.profile.colorful)
                    }
                    VStack(alignment:.leading,spacing:18) {
                        integerSlider(T("Яркость"),value:$model.profile.brightness,range:0...5)
                        integerSlider(T("Скорость"),value:$model.profile.speed,range:0...5)
                        Picker(T("Направление"),selection:$model.profile.direction) {ForEach(0...3,id:\.self){Text("\($0+1)").tag($0)}}
                    }.frame(maxWidth:.infinity)
                }
                Text(T("Идентификаторы эффектов передаются как в оригинале. Названия и доступность каждого эффекта ещё сверяются.")).font(.caption).foregroundStyle(.secondary)
            }
            ApplyBar(section:.light)
        }
    }
}

private func integerSlider(_ label: String,value: Binding<Int>,range: ClosedRange<Int>) -> some View {
    VStack(alignment:.leading,spacing:6) {
        HStack {Text(label);Spacer();Text("\(value.wrappedValue)").monospacedDigit().foregroundStyle(.secondary)}
        Slider(value:Binding(get:{Double(value.wrappedValue)},set:{value.wrappedValue=Int($0)}),in:Double(range.lowerBound)...Double(range.upperBound),step:1)
    }
}

struct SettingsPane: View {
    @EnvironmentObject private var language:LanguageSettings
    @EnvironmentObject var model: AppModel
    var body: some View {
        let _=language.selection
        VStack(spacing:18) {
            Panel(title:T("Параметры клавиатуры")) {
                HStack(alignment:.top,spacing:60) {
                    VStack(alignment:.leading,spacing:18) {
                        Picker(T("Время до сна"),selection:$model.profile.sleepIndex) {
                            Text(T("Без сна")).tag(0);Text(T("1 минута")).tag(1);Text(T("5 минут")).tag(2);Text(T("30 минут")).tag(3)
                        }
                        integerSlider(T("Уровень времени отклика"),value:$model.profile.responseLevel,range:1...5)
                        Toggle(T("Переключать Fn-слой нажатием"),isOn:$model.profile.fnToggle)
                    }.frame(maxWidth:.infinity)
                    VStack(alignment:.leading,spacing:18) {
                        Toggle(T("Отключить Win / ⌘"),isOn:$model.profile.disableWin)
                        Toggle(T("Отключить Alt + F4"),isOn:$model.profile.disableAltF4)
                        Toggle(T("Отключить Alt + Tab"),isOn:$model.profile.disableAltTab)
                    }.frame(maxWidth:.infinity)
                }
                ApplyBar(section:.settings)
            }
            Panel(title:T("Подключение и проверка")) {
                Text(T("Настройки записываются только по нажатию «Применить». Загрузка изображений доступна в разделе IPS-экран."))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(model.interfaces){item in
                    HStack {Text(item.isSettings ? T("Настройки"):T("HID-интерфейс")).frame(width:110,alignment:.leading);Text(item.summary).font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary)}
                }
                HStack {Button(T("Обновить"),action:model.scan);Button(T("Сохранить диагностику"),action:model.exportDiagnostics)}
            }
            Panel(title:T("Состояние переноса")) {
                Text(T("Обновление прошивки и настройка по радиоприёмнику 2.4 ГГц недоступны. Bluetooth-настройку оригинальная программа также не поддерживает."))
                    .font(.caption).foregroundStyle(.secondary)
                if !model.logs.isEmpty {
                    Text(model.logs.suffix(4).map(L).joined(separator:"\n")).font(.system(size:10,design:.monospaced)).textSelection(.enabled)
                }
            }
        }
    }
}

struct MacroPane: View {
    @EnvironmentObject private var language:LanguageSettings
    @EnvironmentObject var model:AppModel
    @State private var selected:UUID?=nil
    @State private var chordUsage=4
    @State private var chordModifiers=0
    var body:some View {
        let _=language.selection
        Panel(title:T("Редактор макросов")) {
            Text(T("Создай последовательность, загрузи её в память клавиатуры и назначь на клавишу в разделе «Назначения». Объём зависит от числа макросов и уже занятых слотов."))
                .font(.caption).foregroundStyle(.secondary)
            let used=(try? MacroMemory.usedBytes(model.profile)) ?? MacroMemory.capacity+1
            Text(T("Память: \(used) / \(MacroMemory.capacity) байт")).font(.caption).foregroundStyle(used>MacroMemory.capacity ? .orange:.secondary)
            HStack {
                Picker(T("Макрос"),selection:$selected) {
                    Text(T("Выбери макрос")).tag(nil as UUID?)
                    ForEach(model.profile.macros){Text($0.name).tag($0.id as UUID?)}
                }.frame(width:320)
                Button(T("Новый")) {let m=LocalMacro();model.profile.macros.append(m);selected=m.id}
                Button(T("Удалить")) {
                    let id=selected;selected=nil
                    var profile=model.profile;profile.macros.removeAll{$0.id==id}
                    for i in profile.bindings.indices where profile.bindings[i].macroID==id {
                        let old=profile.bindings[i];profile.bindings[i]=KeyBinding(keyID:old.keyID,fnLayer:old.fnLayer)
                    }
                    model.profile=profile
                }.disabled(selected==nil)
            }.disabled(model.recording)
            if let macro=model.profile.macros.first(where:{$0.id==selected}) {editor(macro)}
            ApplyBar(section:.macros)
        }.onChange(of:selected){_,_ in model.stopRecording()}.onDisappear{model.stopRecording()}
    }
    private func macroValue<T>(_ macro:LocalMacro,_ path:WritableKeyPath<LocalMacro,T>)->Binding<T> {
        Binding(get:{model.profile.macros.first{$0.id==macro.id}?[keyPath:path] ?? macro[keyPath:path]},set:{value in
            model.updateMacro(macro.id){$0[keyPath:path]=value}
        })
    }
    private func stepValue<T>(_ macro:LocalMacro,_ step:MacroStep,_ path:WritableKeyPath<MacroStep,T>)->Binding<T> {
        Binding(get:{model.profile.macros.first{$0.id==macro.id}?.steps.first{$0.id==step.id}?[keyPath:path] ?? step[keyPath:path]},set:{value in
            model.updateMacro(macro.id){m in if let i=m.steps.firstIndex(where:{$0.id==step.id}){m.steps[i][keyPath:path]=value}}
        })
    }
    private func chordModifier(_ name:String,bit:Int)->some View {
        Toggle(name,isOn:Binding(get:{chordModifiers & bit != 0},set:{if $0{chordModifiers |= bit}else{chordModifiers &= ~bit}})).toggleStyle(.button)
    }
    @ViewBuilder private func editor(_ macro:LocalMacro)->some View {
        HStack {
            Button(model.recording ? T("Остановить запись (Esc)"):T("Записать клавиши")) {if model.recording {model.stopRecording()}else{model.startRecording(macro.id)}}.disabled(model.busy)
            Text(model.recording ? T("Ввод записывается внутри окна. Esc — завершить."):T("Запись клавиатуры в этом окне; действия мыши можно добавить ниже.")).font(.caption).foregroundStyle(.secondary)
        }
        VStack(alignment:.leading,spacing:12) {
            TextField(T("Название"),text:macroValue(macro,\.name)).frame(width:320)
            Stepper(T("Повторов: \(macro.repeatCount)"),value:macroValue(macro,\.repeatCount),in:1...255)
            Text(T("Изменение общего счётчика обновляет все назначения этого макроса. Отдельный счётчик есть в разделе «Назначения».")).font(.caption).foregroundStyle(.secondary)
            Text(T("Доступно дополнительных действий: \(MacroMemory.remainingActions(for:macro.id,in:model.profile)). Новые задержки: 10–60000 мс.")).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(macro.steps.enumerated()),id:\.element.id) {number,step in
                HStack {
                    Text("\(number+1)").foregroundStyle(.secondary).frame(width:28)
                    Picker(T("Действие"),selection:stepValue(macro,step,\.action)) {
                        Text(T("Нажать")).tag("Key down");Text(T("Отпустить")).tag("Key up");Text(T("Мышь: нажать")).tag("Mouse down");Text(T("Мышь: отпустить")).tag("Mouse up")
                    }.frame(width:200)
                    if step.action.hasPrefix("Mouse") {
                        Picker(T("Кнопка"),selection:stepValue(macro,step,\.usage)){Text(T("Левая")).tag(1);Text(T("Правая")).tag(2);Text(T("Средняя")).tag(4)}.frame(width:190)
                    }else{
                        Picker(T("Клавиша"),selection:stepValue(macro,step,\.usage)){ForEach(model.keys.filter{$0.name != "Fn"}){Text($0.name).tag($0.usage)}}.frame(width:190)
                    }
                    let delay=stepValue(macro,step,\.delay)
                    TextField(T("мс"),value:Binding(get:{delay.wrappedValue},set:{delay.wrappedValue=min(60000,max(10,$0))}),format:.number).frame(width:65)
                    Text(T("мс")).foregroundStyle(.secondary)
                    Button {model.updateMacro(macro.id){$0.steps.removeAll{$0.id==step.id}}} label:{Image(systemName:"minus.circle")}
                }
            }
            HStack {
                Picker(T("Сочетание"),selection:$chordUsage){ForEach(model.keys.filter{(4...223).contains($0.usage) && $0.name != "Fn"}){Text($0.name).tag($0.usage)}}.frame(width:200)
                chordModifier("Ctrl",bit:1);chordModifier("Shift",bit:2);chordModifier("⌥",bit:4);chordModifier("⌘",bit:8)
                let chord=(try? MacroChord.steps(usage:chordUsage,modifiers:chordModifiers)) ?? []
                Button(T("Добавить сочетание")){model.updateMacro(macro.id){$0.steps += chord}}
                    .disabled(chord.isEmpty || !MacroMemory.canAppend(chord.count,to:macro.id,in:model.profile))
            }
            Text(T("Сочетание включает нажатия и отпускания всех выбранных клавиш.")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(T("Добавить действие")){model.updateMacro(macro.id){$0.steps.append(MacroStep())}}
                    .disabled(!MacroMemory.canAppend(1,to:macro.id,in:model.profile))
                let releases=MacroSequence.releases(for:macro.steps)
                if !releases.isEmpty {
                    Button(T("Добавить отпускания (\(releases.count))")){model.updateMacro(macro.id){$0.steps += releases}}
                        .disabled(!MacroMemory.canAppend(releases.count,to:macro.id,in:model.profile))
                }
            }
        }.disabled(model.recording)
    }
}

struct CustomColorsPane: View {
    @EnvironmentObject private var language:LanguageSettings
    @EnvironmentObject var model: AppModel
    @State private var color=Color.cyan
    var body: some View {
        let _=language.selection
        Panel(title:T("Цвет отдельных клавиш")) {
            KeyboardCanvas(showColors:true)
            HStack {
                ColorPicker(T("Цвет"),selection:$color,supportsOpacity:false).frame(width:200)
                Button(T("Задать выбранной клавише")) {if let key=model.selectedKey {model.profile.keyColors[String(key)]=NSColor(color).hexRGB}}.disabled(model.selectedKey==nil)
                Button(T("Все клавиши")) {for key in model.keys {model.profile.keyColors[String(key.id)]=NSColor(color).hexRGB}}
                Button(T("Очистить")) {model.profile.keyColors.removeAll()}
            }
            integerSlider(T("Яркость"),value:$model.profile.brightness,range:0...5).frame(width:300)
            Text(T("Клавиши без выбранного цвета будут выключены.")).font(.caption).foregroundStyle(.secondary)
            ApplyBar(section:.custom)
        }
    }
}

struct AnimatedImage: NSViewRepresentable {
    var image: NSImage?
    func makeNSView(context: Context) -> NSImageView {let view=NSImageView();view.imageScaling = .scaleProportionallyUpOrDown;view.animates=true;return view}
    func updateNSView(_ view: NSImageView,context: Context) {view.image=image}
}
struct ScreenPane: View {
    @EnvironmentObject private var language:LanguageSettings
    @EnvironmentObject var model: AppModel
    var body: some View {
        let _=language.selection
        Panel(title:T("IPS-экран")) {
            HStack(alignment:.center,spacing:36) {
                ZStack {
                    RoundedRectangle(cornerRadius:16).fill(.black).overlay(RoundedRectangle(cornerRadius:16).stroke(.white.opacity(0.2)))
                    if model.screenImage != nil {AnimatedImage(image:model.screenImage).padding(12)}
                    else {VStack(spacing:12){Image(systemName:"photo.on.rectangle.angled").font(.largeTitle);Text("320 × 480").font(.title2);Text(T("Предпросмотр")).foregroundStyle(.secondary)}}
                }.frame(width:240,height:360)
                VStack(alignment:.leading,spacing:20) {
                    Text(T("Изображения и анимации")).font(.title3).bold()
                    Text(L(model.screenInfo)).font(.caption).foregroundStyle(.secondary)
                    Button(T("Импортировать файл"),action:model.importScreen).disabled(model.busy)
                    Picker(T("Назначение"),selection:$model.screenDestination){ForEach(ScreenDestination.allCases){Text(L($0.rawValue)).tag($0)}}.disabled(model.busy)
                    Picker(T("Масштаб"),selection:$model.screenFit) {ForEach(ScreenFit.allCases){Text(L($0.rawValue)).tag($0)}}
                        .onChange(of:model.screenFit){_,_ in model.refreshScreenPreview()}.disabled(model.busy)
                    Picker(T("Поворот"),selection:$model.screenRotation) {ForEach([0,90,180,270],id:\.self){Text("\($0)°").tag($0)}}
                        .onChange(of:model.screenRotation){_,_ in model.refreshScreenPreview()}.disabled(model.busy)
                    Text(T("После загрузки заново открой выбранный раздел на экране клавиатуры. Во время записи не отключай USB.")).font(.caption).foregroundStyle(.secondary)
                    Text(T("Изображение автоматически подгоняется к экрану 320 × 480. GIF — до 200 кадров.")).font(.caption).foregroundStyle(.secondary)
                    if model.uploadingScreen || model.screenProgress>0 {ProgressView(value:model.screenProgress).frame(width:280)}
                    HStack {
                        Button(model.uploadingScreen ? T("Загрузка…"):T("Загрузить на клавиатуру"),action:model.uploadScreen)
                            .buttonStyle(.borderedProminent).disabled(!model.canUploadScreen || model.screenURL==nil)
                        if model.uploadingScreen {Button(T("Остановить"),action:model.cancelScreenUpload)}
                    }
                }
            }
        }
    }
}

struct MusicPane: View {
    @EnvironmentObject private var language:LanguageSettings
    @EnvironmentObject var model:AppModel
    var body:some View {
        let _=language.selection
        VStack(alignment:.leading,spacing:18) {
            Panel(title:T("Спектр системного звука")) {
                HStack {
                    Text(model.musicStarting ? T("Подготавливаю системное аудио…"):model.musicActive ? T("Захват системного звука включён"):T("Включи музыку на Mac и запусти визуализацию.")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.musicActive || model.musicStarting {
                        Button(model.musicStarting ? T("Отменить"):T("Остановить")){model.stopMusic()}.disabled(model.musicStopping)
                    } else {
                        Button(T("Запустить")){model.startMusic()}.buttonStyle(.borderedProminent).disabled(!model.canWrite || model.musicStopping)
                    }
                }
                SpectrumBars(levels:model.musicLevels).frame(height:185)
                HStack {
                    Text(T("60 Гц"));Spacer();Text(T("18 полос"));Spacer();Text(T("16 кГц"))
                }.font(.caption).foregroundStyle(.secondary)
                HStack(spacing:16) {
                    Image(systemName:"speaker.wave.2").foregroundStyle(accent)
                    Text(L(model.musicOutputName)).font(.callout)
                    Spacer()
                    Text(model.musicDecibels < -80 ? T("Тишина"):T("\(Int(model.musicDecibels.rounded())) дБ")).font(.system(.caption,design:.monospaced)).foregroundStyle(.secondary)
                    ProgressView(value:max(0,min(1,(model.musicDecibels+80)/80))).frame(width:120)
                }
            }
            HStack(alignment:.top,spacing:18) {
                Panel(title:T("Реакция на музыку")) {
                    HStack {
                        Text(T("Чувствительность"))
                        Spacer()
                        Text(String(format:"%.1f×",model.musicSensitivity)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value:$model.musicSensitivity,in:0.25...8,step:0.25)
                    Picker(T("Цвета спектра"),selection:$model.musicForeground) {
                        ForEach(MusicPalette.all){Text(L($0.name)).tag($0.id)}
                    }
                    Text(T("Источник — звук, который воспроизводят приложения Mac. Микрофон не используется."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Panel(title:T("Подсветка фона")) {
                    Picker(T("Цвет фона"),selection:$model.musicBackground) {
                        Text(T("Выключен")).tag(0)
                        ForEach(MusicPalette.all){Text(L($0.name)).tag($0.id)}
                    }
                    HStack {
                        Text(T("Яркость фона"));Spacer();Text("\(Int(model.musicBackgroundBrightness))%").foregroundStyle(.secondary)
                    }
                    Slider(value:$model.musicBackgroundBrightness,in:0...100,step:1).disabled(model.musicBackground==0)
                    Text(T("После остановки подсветка вернётся к настройкам локального профиля во вкладке «Подсветка»."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Panel(title:T("Экран и клавиши L99")) {
                Text(T("На клавиатуре открой плеер Play. Волна внизу экрана и подсветка клавиш будут реагировать на музыку. Кнопки воспроизведения и громкости работают отдельно."))
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    if model.musicStarting || model.musicStopping {ProgressView().controlSize(.small)}
                    Text(L(model.musicStatus)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    if model.musicActive || model.musicStarting {
                        Button(model.musicStarting ? T("Отменить"):T("Остановить")){model.stopMusic()}.disabled(model.musicStopping)
                    } else {
                        Button(T("Запустить")){model.startMusic()}.buttonStyle(.borderedProminent)
                            .disabled(!model.canWrite || model.musicStopping)
                    }
                }
                HStack {
                    Text(model.musicFramesSent>0 ? T("Отправлено кадров: \(model.musicFramesSent)"):T("Требуется разрешение macOS на запись системного аудио."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(T("Настройки конфиденциальности…")) {
                        if let url=URL(string:"x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension") {NSWorkspace.shared.open(url)}
                    }.controlSize(.small)
                }
                Text(T("Звук обрабатывается локально и не сохраняется. Во время записи настроек или картинки музыкальная передача приостанавливается."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SpectrumBars:View {
    @EnvironmentObject private var language:LanguageSettings
    var levels:[UInt8]
    var body:some View {
        let _=language.selection
        GeometryReader {geometry in
            HStack(alignment:.bottom,spacing:7) {
                ForEach(0..<18,id:\.self) {i in
                    RoundedRectangle(cornerRadius:4)
                        .fill(LinearGradient(colors:[Color(red:0.1,green:0.45,blue:0.9),accent,Color(red:0.4,green:0.95,blue:0.8)],startPoint:.bottom,endPoint:.top))
                        .frame(height:max(4,geometry.size.height*Double(levels[i])/99))
                        .frame(maxWidth:.infinity)
                }
            }.frame(height:geometry.size.height,alignment:.bottom)
                .animation(.linear(duration:0.07),value:levels)
        }.accessibilityElement(children:.ignore).accessibilityLabel(T("Живой музыкальный спектр"))
    }
}

struct RealtimePane: View {
    @EnvironmentObject private var language:LanguageSettings
    @EnvironmentObject var model:AppModel
    private func metric(_ value:Double?,_ unit:String)->String {
        value.map {"\(Int($0.rounded()))\(unit)"} ?? T("Недоступно")
    }
    var body:some View {
        let _=language.selection
        VStack(alignment:.leading,spacing:18) {
            HStack(alignment:.top,spacing:18) {
                Panel(title:T("Время и дата с Mac")) {
                    TimelineView(.periodic(from:.now,by:1)) {context in
                        VStack(alignment:.leading,spacing:8) {
                            Text(context.date,format:.dateTime.hour().minute().second()).font(.system(size:38,weight:.medium,design:.monospaced))
                            Text(context.date,format:.dateTime.day().month(.wide).year().weekday(.wide)).foregroundStyle(.secondary)
                        }
                    }
                    Text(TimeZone.current.identifier).font(.caption).foregroundStyle(.secondary)
                    Toggle(T("Синхронизировать при USB-подключении"),isOn:$model.syncClockOnConnect)
                    Text(T("При открытом приложении часы также синхронизируются после сна Mac.")).font(.caption).foregroundStyle(.secondary)
                }
                Panel(title:T("Показатели Mac")) {
                    HStack(spacing:28) {
                        value("CPU",metric(model.metrics.cpu,"%"),"cpu")
                        value("GPU",metric(model.metrics.gpu,"%"),"square.stack.3d.up")
                    }
                    Divider()
                    HStack(spacing:28) {
                        value(T("Температура CPU"),metric(model.metrics.cpuTemperature," °C"),"thermometer.medium")
                        value(T("Влажность"),"0%","humidity")
                    }
                    Text(L(model.metrics.temperatureSource)).font(.caption).foregroundStyle(.secondary)
                    if model.metrics.cpuTemperature==nil || model.metrics.gpu==nil {
                        Text(T("Для недоступных показателей на экран передаётся 0."))
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Panel(title:T("Передача на клавиатуру")) {
                Toggle(T("Обновлять показатели каждые 5 секунд"),isOn:$model.liveMetrics)
                Text(T("На клавиатуре открой Home → Real-time Data. Поле температуры покажет температуру CPU Mac; влажность — 0%. Вместе с показателями передаются текущие время и дата."))
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    if model.realtimeSending {ProgressView().controlSize(.small)}
                    Text(L(model.realtimeStatus)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Spacer()
                    Button(T("Синхронизировать сейчас")){model.syncRealtimeNow()}
                        .buttonStyle(.borderedProminent).disabled(!model.canWrite || model.realtimeSending)
                }
                if let date=model.lastRealtimeUpdate {
                    Text(T("Последняя отправка: \(date.formatted(date:.omitted,time:.standard))")).font(.caption).foregroundStyle(.secondary)
                }
                Text(T("Приложение должно оставаться открытым. При загрузке картинок передача показателей приостанавливается."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func value(_ label:String,_ reading:String,_ icon:String)->some View {
        VStack(alignment:.leading,spacing:8) {
            Label(label,systemImage:icon).font(.caption).foregroundStyle(.secondary)
            Text(reading).font(.system(size:27,weight:.medium,design:.rounded)).foregroundStyle(reading==T("Недоступно") ? Color.secondary:accent)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
