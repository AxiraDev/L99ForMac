// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation

func runLocalizationTests()throws->Int {
    var passed=0
    func check(_ condition:Bool,_ name:String)throws {
        guard condition else{throw L99Error.message("TEST FAILED: "+name)}
        passed+=1;print("PASS "+name)
    }
    try check(AppLanguage.resolve(.system,preferred:["ru-RU"])=="ru" && AppLanguage.resolve(.system,preferred:["zh-Hant-TW"])=="zh-Hans" && AppLanguage.resolve(.system,preferred:["de-DE","en-GB"])=="en","system language selection and fallback")
    try check(AppLanguage.resolve(.en,preferred:["ru-RU"])=="en" && AppLanguage.resolve(.ru,preferred:["en"])=="ru","manual language overrides system")
    let directory=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("resources/localization")
    var catalogs:[String:[String:String]]=[:]
    for code in ["ru","en","zh-Hans"] {catalogs[code]=try JSONDecoder().decode([String:String].self,from:Data(contentsOf:directory.appendingPathComponent(code+".json")))}
    let keys=Set(catalogs["ru"]!.keys)
    try check(keys.count>=418 && catalogs.values.allSatisfy{Set($0.keys)==keys && $0.values.allSatisfy{!$0.isEmpty}},"all catalogs contain the same complete nonempty key set")
    let localizer=AppLocalization(directory:directory,language:"en")
    try check(localizer.text("Поддержать разработчика")=="Support the developer","English translation is loaded")
    let filename="用户{1} %s.json"
    let english=localizer.text("Профиль сохранён: \(filename)")
    localizer.select("zh-Hans")
    try check(localizer.display(english)=="配置已保存："+filename,"existing status relocalizes and preserves interpolated user data")
    try check(AppLocalization.render("{1} / {0}",arguments:["{1}","50% ✓"])=="50% ✓ / {1}","placeholder reordering never reinterprets inserted values")
    try check(localizer.display("Unknown user macro 名称")=="Unknown user macro 名称" && localizer.text("A missing translation")=="A missing translation","unknown strings and user names remain unchanged")
    try check(SupportConfiguration.validatedURL(" https://boosty.to/example/donate ")?.host=="boosty.to" && ["","http://boosty.to/example","file:///tmp/test","javascript:alert(1)","https://user:secret@example.com"].allSatisfy{SupportConfiguration.validatedURL($0)==nil},"donation links require HTTPS and reject embedded credentials")
    let support=try JSONDecoder().decode(SupportConfiguration.self,from:Data(contentsOf:directory.deletingLastPathComponent().appendingPathComponent("support.json")))
    try check(SupportConfiguration(donationURL:"").url==nil && support.url?.absoluteString=="https://boosty.to/axira_dev/donate","empty support stays inactive and the release uses the developer donation page")
    var profile=Profile();profile.name="Личный профиль 用户";var macro=LocalMacro();macro.name="аа 用户";macro.steps=[MacroStep(),MacroStep(action:"Key up")];profile.macros=[macro];profile.bindings=[KeyBinding(keyID:13,fnLayer:false,kind:4,modifiers:1,macroID:macro.id)]
    let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
    let original=try encoder.encode(profile)
    let oldLanguage=AppLocalization.shared.locale.identifier
    defer{AppLocalization.shared.select(oldLanguage)}
    func packets()throws->[WirePacket] {try ProtocolCore.lighting(profile)+ProtocolCore.assignmentUpdate(profile,fnLayer:false)}
    let expected=try packets()
    for code in ["ru","en","zh-Hans"] {
        AppLocalization.shared.select(code)
        let actual=try packets()
        try check(try encoder.encode(profile)==original && actual.count==expected.count && zip(actual,expected).allSatisfy{$0.payload==$1.payload && $0.acknowledgement==$1.acknowledgement},"language \(code) preserves profile bytes and keyboard packets")
    }
    return passed
}
