// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation
import AppKit

struct MusicPreferences:Codable,Equatable {
    var foreground=2
    var background=0
    var brightness=15.0
    var sensitivity=1.0
    func validate()throws {
        guard (1...11).contains(foreground),(0...11).contains(background),brightness.isFinite,(0...100).contains(brightness),sensitivity.isFinite,(0.25...8).contains(sensitivity) else{throw L99Error.message(T("Неверные сохранённые настройки музыки."))}
    }
}
struct SavedSession:Codable {
    var version=1
    var profile:Profile
    var music:MusicPreferences
    var pending:[String]
    var syncClock:Bool
    var liveMetrics:Bool
    var savedAt:Date
}

/// User data never enters the source archive. In a source checkout it stays beside the app.
struct SessionStore {
    let directory:URL
    var projectRoot:URL? {
        let root=directory.deletingLastPathComponent()
        return directory.lastPathComponent=="local-state" && FileManager.default.fileExists(atPath:root.appendingPathComponent("core/Cargo.toml").path) ? root:nil
    }
    @MainActor func authorizeProjectFolder()throws->Bool {
        guard let root=projectRoot else{return true}
        let key="localStateFolderBookmark"
        if let data=UserDefaults.standard.data(forKey:key) {
            var stale=false
            if let url=try? URL(resolvingBookmarkData:data,options:[.withSecurityScope,.withoutUI],relativeTo:nil,bookmarkDataIsStale:&stale),url.standardizedFileURL==root.standardizedFileURL,url.startAccessingSecurityScopedResource() {
                if stale {UserDefaults.standard.set(try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil),forKey:key)}
                return true
            }
        }
        let panel=NSOpenPanel();panel.canChooseFiles=false;panel.canChooseDirectories=true;panel.allowsMultipleSelection=false
        panel.directoryURL=root;panel.title=T("Папка профиля L99");panel.prompt=T("Выбрать папку проекта")
        panel.message=T("Выбери папку проекта L99. Профиль и настройки музыки будут автоматически сохраняться в её подпапке local-state.")
        guard panel.runModal() == .OK,let url=panel.url else{return false}
        guard url.standardizedFileURL==root.standardizedFileURL else{throw L99Error.message(T("Нужна папка проекта, в которой находится это приложение."))}
        _ = url.startAccessingSecurityScopedResource()
        UserDefaults.standard.set(try url.bookmarkData(options:.withSecurityScope,includingResourceValuesForKeys:nil,relativeTo:nil),forKey:key)
        return true
    }
    init(directory:URL?=nil) {
        if let directory {self.directory=directory;return}
        let root=Bundle.main.bundleURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath:root.appendingPathComponent("core/Cargo.toml").path) {
            self.directory=root.appendingPathComponent("local-state",isDirectory:true)
        } else {
            self.directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("L99 for Mac",isDirectory:true)
        }
    }
    private var current:URL{directory.appendingPathComponent("session.json")}
    private var previous:URL{directory.appendingPathComponent("session.previous.json")}
    private func readBounded(_ url:URL)throws->Data {
        let file=try FileHandle(forReadingFrom:url);defer{try? file.close()}
        let data=try file.read(upToCount:4*1024*1024+1) ?? Data()
        guard data.count<=4*1024*1024 else{throw L99Error.message(T("Файл сохранённого сеанса слишком большой."))}
        return data
    }
    func restore(validate:(SavedSession)throws->Void)throws->(SavedSession,Bool)? {
        var lastError:Error?
        for (url,recovered) in [(current,false),(previous,true)] where FileManager.default.fileExists(atPath:url.path) {
            do {
                let value=try JSONDecoder().decode(SavedSession.self,from:readBounded(url))
                guard value.version==1 else{throw L99Error.message(T("Версия сохранённого сеанса не поддерживается."))}
                try value.music.validate();try validate(value)
                return (value,recovered)
            }catch{lastError=error}
        }
        if let lastError{throw lastError};return nil
    }
    func save(_ value:SavedSession,validate:(SavedSession)throws->Void)throws {
        func checked(_ session:SavedSession)throws {
            guard session.version==1 else{throw L99Error.message(T("Версия сеанса не поддерживается."))}
            try session.music.validate();try validate(session)
        }
        try checked(value)
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        let data=try encoder.encode(value)
        guard data.count<=4*1024*1024 else{throw L99Error.message(T("Профиль слишком большой для автосохранения."))}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        // Keep the last valid complete session; a damaged primary must not replace it.
        if let old=try? readBounded(current),let session=try? JSONDecoder().decode(SavedSession.self,from:old),(try? checked(session)) != nil {
            try old.write(to:previous,options:.atomic)
        }
        try data.write(to:current,options:.atomic)
    }
}
