// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation
import SwiftUI

enum AppLanguage:String,CaseIterable,Identifiable {
    case system,ru,en,zhHans="zh-Hans"
    var id:String {rawValue}
    var name:String {
        switch self {case .system:return T("Как в macOS");case .ru:return "Русский";case .en:return "English";case .zhHans:return "简体中文"}
    }
    static func resolve(_ selection:AppLanguage,preferred:[String]=Locale.preferredLanguages)->String {
        guard selection == .system else{return selection.rawValue}
        for language in preferred {
            if language.hasPrefix("ru"){return "ru"}
            if language.hasPrefix("en"){return "en"}
            if language.hasPrefix("zh"){return "zh-Hans"}
        }
        return "en"
    }
}

/// Interpolation values remain data: they are never parsed as format strings.
struct TranslationText:ExpressibleByStringLiteral,ExpressibleByStringInterpolation {
    var key:String
    var arguments:[String]
    init(stringLiteral value:String){key=value;arguments=[]}
    init(stringInterpolation value:StringInterpolation){key=value.key;arguments=value.arguments}
    struct StringInterpolation:StringInterpolationProtocol {
        var key=""
        var arguments:[String]=[]
        init(literalCapacity:Int,interpolationCount:Int){key.reserveCapacity(literalCapacity);arguments.reserveCapacity(interpolationCount)}
        mutating func appendLiteral(_ value:String){key+=value}
        mutating func appendInterpolation<T>(_ value:T){key+="{\(arguments.count)}";arguments.append(String(describing:value))}
    }
}

final class AppLocalization:@unchecked Sendable {
    static let shared=AppLocalization()
    private let lock=NSRecursiveLock()
    private var language:String
    private let catalogs:[String:[String:String]]
    // Only generated messages are remembered; profile data is never translated.
    private var recent:[String:TranslationText]=[:]
    private var order:[String]=[]
    init(directory:URL?=nil,language:String?=nil){
        let selection=AppLanguage(rawValue:UserDefaults.standard.string(forKey:"appLanguage") ?? "system") ?? .system
        self.language=language ?? AppLanguage.resolve(selection)
        let folder=directory ?? Bundle.main.resourceURL?.appendingPathComponent("resources/localization")
        var values:[String:[String:String]]=[:]
        for code in ["ru","en","zh-Hans"] {
            if let url=folder?.appendingPathComponent(code+".json"),let data=try? Data(contentsOf:url),let catalog=try? JSONDecoder().decode([String:String].self,from:data){values[code]=catalog}
        }
        catalogs=values
    }
    var locale:Locale {lock.lock();defer{lock.unlock()};return Locale(identifier:language)}
    func select(_ code:String){lock.lock();defer{lock.unlock()};language=code}
    static func render(_ template:String,arguments:[String])->String {
        let pattern=try! NSRegularExpression(pattern:#"\{([0-9]+)\}"#)
        var result=template
        for match in pattern.matches(in:template,range:NSRange(template.startIndex...,in:template)).reversed() {
            guard let number=Range(match.range(at:1),in:template),let index=Int(template[number]),arguments.indices.contains(index),let range=Range(match.range,in:result) else{continue}
            result.replaceSubrange(range,with:arguments[index])
        }
        return result
    }
    func text(_ value:TranslationText)->String {
        lock.lock();defer{lock.unlock()}
        let result=Self.render(catalogs[language]?[value.key] ?? value.key,arguments:value.arguments)
        if recent[result]==nil {order.append(result)}
        recent[result]=value
        while order.count>1000 {recent.removeValue(forKey:order.removeFirst())}
        return result
    }
    func display(_ value:String)->String {
        lock.lock();defer{lock.unlock()}
        if let source=recent[value]{return Self.render(catalogs[language]?[source.key] ?? source.key,arguments:source.arguments)}
        return catalogs[language]?[value] ?? value
    }
}

func T(_ text:TranslationText)->String {AppLocalization.shared.text(text)}
func L(_ text:String)->String {AppLocalization.shared.display(text)}

@MainActor final class LanguageSettings:ObservableObject {
    @Published var selection:AppLanguage {
        didSet {UserDefaults.standard.set(selection.rawValue,forKey:"appLanguage");AppLocalization.shared.select(AppLanguage.resolve(selection))}
    }
    var locale:Locale {AppLocalization.shared.locale}
    init(){selection=AppLanguage(rawValue:UserDefaults.standard.string(forKey:"appLanguage") ?? "system") ?? .system;AppLocalization.shared.select(AppLanguage.resolve(selection))}
}
