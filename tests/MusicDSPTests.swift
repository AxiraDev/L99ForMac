// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation
enum L99Error:LocalizedError {case message(String);var errorDescription:String? {switch self{case .message(let v):return v}}}
@main struct DSPTest {
 static func main() {
  let silence=SpectrumAnalyzer();silence.accept([Float](repeating:0,count:8192),sampleRate:48000)
  precondition(silence.snapshot().levels.allSatisfy{$0==0})
  for frequency in [100.0,1000.0,6000.0] {
   let analyzer=SpectrumAnalyzer()
   let samples=(0..<8192).map{Float(sin(2 * .pi * frequency * Double($0)/48000)*0.3)}
   analyzer.accept(samples,sampleRate:48000)
   let levels=analyzer.snapshot().levels
   let peak=levels.indices.max{levels[$0]<levels[$1]}!
   let expected=Int(log(frequency/60)/log(16000.0/60)*18)
   precondition(abs(peak-expected)<=1,"Incorrect frequency bin")
   precondition(levels[peak]>60,"Signal too weak")
   print("Sine",frequency,"Hz: peak band",peak,"level",levels[peak])
  }
  print("Silence and frequency mapping passed")
 }
}
