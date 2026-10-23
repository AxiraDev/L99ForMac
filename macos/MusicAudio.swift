// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation
import CoreAudio
import AudioToolbox
import Accelerate

struct MusicSpectrum {
    let levels:[UInt8]
    let decibels:Double
    let lastBuffer:Date
    static let silent=MusicSpectrum(levels:Array(repeating:0,count:18),decibels:-120,lastBuffer:.distantPast)
}

/// Analysis runs on the audio callback queue; only preferences/snapshots cross queues.
final class SpectrumAnalyzer: @unchecked Sendable {
    static let bandCount=18
    static let lowFrequency=60.0
    static let highFrequency=16000.0
    private let size=2048
    private let setup:FFTSetup
    private let lock=NSLock()
    private var gain=1.0
    private var latest=MusicSpectrum.silent
    private var input=[Float](repeating:0,count:2048)
    private var position=0
    private var smoothed=[Double](repeating:0,count:18)
    private var window=[Float](repeating:0,count:2048)
    private var real=[Float](repeating:0,count:1024)
    private var imaginary=[Float](repeating:0,count:1024)
    init() {
        setup=vDSP_create_fftsetup(11,FFTRadix(kFFTRadix2))!
        for i in window.indices {window[i]=Float(0.5-0.5*cos(2 * .pi * Double(i)/2047))}
    }
    deinit {vDSP_destroy_fftsetup(setup)}
    func setSensitivity(_ value:Double) {lock.lock();gain=max(0.25,min(8,value));lock.unlock()}
    func snapshot()->MusicSpectrum {
        lock.lock();defer{lock.unlock()}
        guard Date().timeIntervalSince(latest.lastBuffer)<0.8 else{return .silent}
        return latest
    }
    func accept(_ samples:[Float],sampleRate:Double) {
        guard sampleRate>=8000,sampleRate<=192000 else{return}
        for v in samples {
            input[position]=v.isFinite ? max(-1,min(1,v)):0
            position+=1
            if position==size {analyze(sampleRate:sampleRate);position=0}
        }
    }
    private func analyze(sampleRate:Double) {
        var squares:Double=0
        for i in 0..<size {squares+=Double(input[i])*Double(input[i])}
        for i in 0..<size/2 {real[i]=input[2*i]*window[2*i];imaginary[i]=input[2*i+1]*window[2*i+1]}
        lock.lock();let sensitivity=gain;lock.unlock()
        let gainDB=20*log10(sensitivity)
        let upper=min(Self.highFrequency,sampleRate*0.48)
        var bands=[Double](repeating:0,count:18)
        real.withUnsafeMutableBufferPointer {r in imaginary.withUnsafeMutableBufferPointer {im in
            var split=DSPSplitComplex(realp:r.baseAddress!,imagp:im.baseAddress!)
            vDSP_fft_zrip(setup,&split,1,11,FFTDirection(FFT_FORWARD))
            for band in 0..<18 {
                let from=Self.lowFrequency*pow(upper/Self.lowFrequency,Double(band)/18)
                let to=Self.lowFrequency*pow(upper/Self.lowFrequency,Double(band+1)/18)
                let low=max(1,min(size/2-1,Int(ceil(from*Double(size)/sampleRate))))
                let high=max(low+1,min(size/2,Int(ceil(to*Double(size)/sampleRate))))
                var peak:Float=0
                for bin in low..<high {peak=max(peak,r[bin]*r[bin]+im[bin]*im[bin])}
                let magnitude=Double(sqrt(peak))/1023.5
                let db=20*log10(max(magnitude,1e-10))+gainDB
                let normalized=max(0,min(1,(db+65)/60))
                let target=pow(normalized,1.15)
                let smoothing=target>smoothed[band] ? 0.75:0.22
                smoothed[band]+=(target-smoothed[band])*smoothing
                bands[band]=smoothed[band]
            }
        }}
        let rms=20*log10(max(sqrt(squares/Double(size)),1e-6))
        let value=MusicSpectrum(levels:bands.map{UInt8(max(0,min(99,Int(($0*99).rounded()))))},decibels:rms,lastBuffer:Date())
        lock.lock();latest=value;lock.unlock()
    }
}

/// A private Core Audio process tap. No microphone, video, audio files, or network.
/// Its aggregate device is private and is destroyed on Stop or process exit.
final class SystemAudioCapture: @unchecked Sendable {
    let analyzer=SpectrumAnalyzer()
    private let audioQueue=DispatchQueue(label:"l99.music.audio",qos:.userInitiated)
    private var tap:AudioObjectID=0
    private var aggregate:AudioObjectID=0
    private var ioProc:AudioDeviceIOProcID?
    private(set) var outputName=T("Системный звук Mac")
    private(set) var outputID:AudioObjectID=0
    deinit {stop()}

    static func defaultOutput()->AudioObjectID {
        var address=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDefaultOutputDevice,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        var value:AudioObjectID=0,size=UInt32(MemoryLayout<AudioObjectID>.size)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&value)
        return value
    }
    private func stringProperty(_ object:AudioObjectID,_ selector:AudioObjectPropertySelector)throws->String {
        var address=AudioObjectPropertyAddress(mSelector:selector,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
        let storage=UnsafeMutableRawPointer.allocate(byteCount:MemoryLayout<UnsafeRawPointer?>.size,alignment:MemoryLayout<UnsafeRawPointer?>.alignment)
        defer{storage.deallocate()}
        storage.storeBytes(of:Optional<UnsafeRawPointer>.none,as:UnsafeRawPointer?.self)
        var size=UInt32(MemoryLayout<UnsafeRawPointer?>.size)
        try check(AudioObjectGetPropertyData(object,&address,0,nil,&size,storage),T("Чтение аудиоустройства"))
        guard let pointer=storage.load(as:UnsafeRawPointer?.self) else{throw L99Error.message(T("Устройство вывода звука недоступно."))}
        return Unmanaged<CFString>.fromOpaque(pointer).takeRetainedValue() as String
    }
    func start() throws {
        guard #available(macOS 14.2,*) else{throw L99Error.message(T("Музыкальная визуализация требует macOS 14.2 или новее."))}
        do {
            outputID=Self.defaultOutput()
            guard outputID != 0 else{throw L99Error.message(T("Не найдено устройство вывода звука Mac."))}
            outputName=try stringProperty(outputID,kAudioObjectPropertyName)
            let description=CATapDescription(stereoGlobalTapButExcludeProcesses:[])
            description.name="L99 Music Spectrum"
            description.isPrivate=true
            description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description,&tap),T("Разрешение на системное аудио"))
            let tapUID=try stringProperty(tap,kAudioTapPropertyUID)
            var address=AudioObjectPropertyAddress(mSelector:kAudioTapPropertyFormat,mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
            var format=AudioStreamBasicDescription(),size=UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tap,&address,0,nil,&size,&format),T("Формат системного аудио"))
            guard format.mFormatID==kAudioFormatLinearPCM,format.mFormatFlags & kAudioFormatFlagIsFloat != 0,[32,64].contains(format.mBitsPerChannel) else {
                throw L99Error.message(T("Формат системного звука не поддерживается."))
            }
            let composition:[String:Any]=[
                kAudioAggregateDeviceNameKey:"L99 Audio Analysis",
                kAudioAggregateDeviceUIDKey:"local.l99.audio.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey:true,
                kAudioAggregateDeviceIsStackedKey:false,
                kAudioAggregateDeviceSubDeviceListKey:[],
                kAudioAggregateDeviceTapListKey:[[kAudioSubTapUIDKey:tapUID,kAudioSubTapDriftCompensationKey:true]],
                kAudioAggregateDeviceTapAutoStartKey:false
            ]
            try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary,&aggregate),T("Подготовка системного аудио"))
            let analyzer=self.analyzer
            let audioFormat=format
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc,aggregate,audioQueue) {_,data,_,_,_ in
                let buffers=UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating:data))
                let bytes=Int(audioFormat.mBitsPerChannel/8)
                let valid=buffers.filter {$0.mData != nil && $0.mNumberChannels>0}
                guard !valid.isEmpty else{return}
                let count=min(16384,valid.map{Int($0.mDataByteSize)/bytes/Int($0.mNumberChannels)}.min() ?? 0)
                guard count>0 else{return}
                let channels=valid.reduce(0){$0+Int($1.mNumberChannels)}
                var mono=[Float](repeating:0,count:count)
                for buffer in valid {
                    let channelCount=Int(buffer.mNumberChannels)
                    for frame in 0..<count {
                        for channel in 0..<channelCount {
                            let offset=frame*channelCount+channel
                            let value:Float=bytes==4 ? buffer.mData!.assumingMemoryBound(to:Float.self)[offset]:Float(buffer.mData!.assumingMemoryBound(to:Double.self)[offset])
                            mono[frame]+=value/Float(channels)
                        }
                    }
                }
                analyzer.accept(mono,sampleRate:audioFormat.mSampleRate)
            },T("Запуск анализа звука"))
            try check(AudioDeviceStart(aggregate,ioProc),T("Захват системного аудио"))
        } catch {stop();throw error}
    }
    func stop() {
        if aggregate != 0 {
            if let ioProc {_ = AudioDeviceStop(aggregate,ioProc);_ = AudioDeviceDestroyIOProcID(aggregate,ioProc);self.ioProc=nil}
            _ = AudioHardwareDestroyAggregateDevice(aggregate);aggregate=0
        }
        if #available(macOS 14.2,*),tap != 0 {_ = AudioHardwareDestroyProcessTap(tap);tap=0}
    }
    private func check(_ status:OSStatus,_ stage:String)throws {
        guard status==noErr else{throw L99Error.message(T("\(stage): ошибка macOS \(status). Проверь разрешение «Запись системного аудио» для L99 for Mac."))}
    }
}
