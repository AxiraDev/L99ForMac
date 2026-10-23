// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import SwiftUI
import AppKit

@main
struct L99App: App {
    @StateObject private var model=AppModel()
    @StateObject private var language=LanguageSettings()
    init() {
        if CommandLine.arguments.contains("--metrics") || CommandLine.arguments.contains("--realtime-once") {
            do {
                let sampler=MacMetricsSampler()
                Thread.sleep(forTimeInterval:1)
                let metrics=sampler.sample()
                if CommandLine.arguments.contains("--realtime-once") {_ = try HIDTransport().send(metrics.packets())}
                let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];encoder.dateEncodingStrategy = .iso8601
                FileHandle.standardOutput.write(try encoder.encode(metrics));FileHandle.standardOutput.write(Data("\n".utf8))
                exit(0)
            } catch {FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8));exit(1)}
        }
        if let i=CommandLine.arguments.firstIndex(of:"--upload-screen"),CommandLine.arguments.count>i+1 {
            do {
                let destination:ScreenDestination=CommandLine.arguments.contains("--background") ? .background:CommandLine.arguments.contains("--gif") ? .animation:.photo
                let image=try ScreenEncoder.encode(url:URL(fileURLWithPath:CommandLine.arguments[i+1]),fit:.fit,rotation:0,animation:destination == .animation)
                let log=try DisplayTransport().upload(image.data,to:destination){value in
                    FileHandle.standardError.write(Data("Screen \(Int(value*100))%\n".utf8))
                }
                let report:[String:Any]=["frames":image.frames,"bytes":image.data.count,"log":log]
                FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:report,options:.prettyPrinted))
                exit(0)
            } catch {FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8));exit(1)}
        }
        if CommandLine.arguments.contains("--read-config") {
            do {
                let snapshot=try DeviceConfiguration.read(channel:SettingsFeatureChannel())
                let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
                FileHandle.standardOutput.write(try encoder.encode(snapshot));exit(0)
            } catch {FileHandle.standardError.write(Data((error.localizedDescription+"\n").utf8));exit(1)}
        }
        if CommandLine.arguments.contains("--diagnose") {
            FileHandle.standardOutput.write(HIDTransport().diagnosticJSON())
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(0)
        }
    }
    var body: some Scene {
        WindowGroup("L99 for Mac") {
            RootView().environmentObject(model).environmentObject(language).environment(\.locale,language.locale).frame(minWidth:1100,minHeight:740)
                .preferredColorScheme(.dark)
        }.defaultSize(width:1280,height:800).windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(replacing:.newItem) {
                    Button(T("Открыть профиль…"),action:model.loadProfile).keyboardShortcut("o").disabled(model.busy || model.loadingSession)
                    Button(T("Сохранить профиль…"),action:model.saveProfile).keyboardShortcut("s").disabled(model.busy || model.loadingSession)
                }
            }
    }
}
