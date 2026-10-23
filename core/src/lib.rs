// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

//! AULA L99 protocol recovered from DeviceDriver.exe 1.0.1.6.
//! No USB access occurs in this crate. See reverse/PROTOCOL.md for evidence.
use std::slice;
pub mod screen;
pub mod realtime;
pub mod music;

/// # Safety
/// `levels` addresses 18 initialized bytes; outputs hold capacity packets.
#[no_mangle]
pub unsafe extern "C" fn l99_build_music(levels:*const u8,foreground:u8,background:u8,brightness:u8,out:*mut u8,flags:*mut u8,capacity:usize)->i32 {
    if levels.is_null(){return -1;}
    copy_packets(music::packets(slice::from_raw_parts(levels,18),foreground,background,brightness),out,flags,capacity)
}

/// # Safety
/// `value` must point to an initialized Realtime; output arrays hold capacity packets.
#[no_mangle]
pub unsafe extern "C" fn l99_build_realtime(value: *const realtime::Realtime, out: *mut u8, flags: *mut u8, capacity: usize) -> i32 {
    if value.is_null() { return -1; }
    copy_packets(realtime::packets(*value), out, flags, capacity)
}

/// # Safety
/// Input and output pointers must be valid for the indicated lengths.
#[no_mangle]
pub unsafe extern "C" fn l99_encode_screen(rgba: *const u8, rgba_len: usize, delays: *const u16, frame_count: usize, animation: u8, out: *mut u8, capacity: usize) -> i32 {
    if rgba.is_null() || delays.is_null() || out.is_null() || !(1..=200).contains(&frame_count) || rgba_len != frame_count*screen::FRAME_RGBA {return -1;}
    let Ok(data)=screen::encode(slice::from_raw_parts(rgba,rgba_len),slice::from_raw_parts(delays,frame_count),animation!=0) else{return -1;};
    if capacity<data.len(){return -2;}
    std::ptr::copy_nonoverlapping(data.as_ptr(),out,data.len());data.len() as i32
}

pub const REPORT_SIZE: usize = 64;
pub type Report = [u8; REPORT_SIZE];

#[repr(C)]
#[derive(Clone,Copy)]
pub struct KeyColor {pub index:u16,pub r:u8,pub g:u8,pub b:u8}

pub fn custom_colors(colors:&[KeyColor],brightness:u8)->Result<Vec<Packet>,&'static str>{
    if brightness>5{return Err("Brightness out of range");}
    let mut packets=lighting(Lighting{mode:0x80,rgb:[0,0,0],brightness,speed:0,direction:0,colorful:false})?;
    let mut table=[0u8;576];
    for color in colors {
        let i=color.index as usize;if !(1..=121).contains(&i){return Err("Invalid light index");}
        table[i*4..i*4+4].copy_from_slice(&[i as u8,color.r,color.g,color.b]);
    }
    table[574..].copy_from_slice(&[0xaa,0x55]);
    packets.push(command(0x18,0));packets.push(command(0x23,9));
    packets.extend(table.chunks_exact(64).map(|p|{let mut bytes=[0;64];bytes.copy_from_slice(p);Packet{bytes,acknowledgement:false}}));
    packets.push(command(2,0));packets.push(command(0xf0,0));Ok(packets)
}

#[repr(C)]
#[derive(Clone,Copy,Debug)]
pub struct MacroEvent {pub slot:u16,pub usage:u16,pub delay_ms:u16,pub action:u8}

pub fn macro_table(events:&[MacroEvent],macro_count:usize)->Result<Vec<Packet>,&'static str>{
    if macro_count>100 || events.len()>337{return Err("Macro memory is full");}
    let mut blob=vec![0;400];
    for slot in 0..macro_count {
        let records:Vec<_>=events.iter().filter(|e|e.slot as usize==slot).collect();
        if records.is_empty(){blob[slot*4..slot*4+4].fill(0xff);continue;}
        let offset=blob.len() as u16;blob[slot*4..slot*4+2].copy_from_slice(&offset.to_le_bytes());
        let count=(records.len()*2)as u16;blob.extend_from_slice(&count.to_le_bytes());blob.extend_from_slice(&[0;6]);
        for event in records {
            if event.usage>255 || event.action>3{return Err("Invalid macro event");}
            let tag=match event.action {0=>0xb0,1=>0x30,2=>0x90,_=>0x10};
            blob.extend_from_slice(&[0,0,event.usage as u8,tag]);
            let delay=event.delay_ms.max(10).to_le_bytes();blob.extend_from_slice(&[delay[0],delay[1],0,0x50]);
        }
    }
    if events.iter().any(|e|e.slot as usize>=macro_count){return Err("Invalid macro slot");}
    let blocks=blob.len().div_ceil(64)+1;blob.resize(blocks*64,0);let len=blob.len();blob[len-2..].copy_from_slice(&[0xaa,0x55]);
    if blob.len()>3584{return Err("Macro memory is full");}
    let mut packets=vec![command(0x19,0),command(0x15,blocks as u8)];
    packets.extend(blob.chunks_exact(64).map(|p|{let mut bytes=[0;64];bytes.copy_from_slice(p);Packet{bytes,acknowledgement:false}}));
    packets.push(command(2,0));Ok(packets)
}

/// # Safety
/// Pointers must refer to initialized arrays of the given lengths.
#[no_mangle]
pub unsafe extern "C" fn l99_build_custom(colors:*const KeyColor,count:usize,brightness:u8,out:*mut u8,flags:*mut u8,capacity:usize)->i32 {
    if count>121 || (count>0 && colors.is_null()){return -1;}
    let colors=if count==0{&[]}else{slice::from_raw_parts(colors,count)};
    copy_packets(custom_colors(colors,brightness),out,flags,capacity)
}

/// # Safety
/// Pointers must refer to initialized arrays of the given lengths.
#[no_mangle]
pub unsafe extern "C" fn l99_build_macros(events:*const MacroEvent,count:usize,macro_count:usize,out:*mut u8,flags:*mut u8,capacity:usize)->i32 {
    if count>337 || (count>0 && events.is_null()){return -1;}
    let events=if count==0{&[]}else{slice::from_raw_parts(events,count)};
    copy_packets(macro_table(events,macro_count),out,flags,capacity)
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Packet {
    pub bytes: Report,
    pub acknowledgement: bool,
}

fn command(opcode: u8, count: u8) -> Packet {
    let mut bytes = [0; REPORT_SIZE];
    bytes[0] = 0x04;
    bytes[1] = opcode;
    bytes[8] = count;
    Packet { bytes, acknowledgement: true }
}

#[derive(Clone, Copy, Debug)]
pub struct Lighting {
    pub mode: u8,
    pub rgb: [u8; 3],
    pub brightness: u8,
    pub speed: u8,
    pub direction: u8,
    pub colorful: bool,
}

/// Exact five-packet sequence from 0x433840. COLORREF 0x00BBGGRR becomes R,G,B.
pub fn lighting(value: Lighting) -> Result<Vec<Packet>, &'static str> {
    if value.mode > 0x80 || value.brightness > 5 || value.speed > 5 || value.direction > 3 {
        return Err("Lighting parameter out of range");
    }
    let mut bytes = [0; REPORT_SIZE];
    bytes[0] = value.mode;
    if value.mode != 0 {
        bytes[1..4].copy_from_slice(&value.rgb);
        bytes[8] = value.colorful as u8;
        bytes[9] = value.brightness;
        bytes[10] = value.speed;
        bytes[11] = value.direction;
    }
    bytes[14..16].copy_from_slice(&[0xaa, 0x55]);
    let mut end = command(0xf0, 0);
    end.acknowledgement = false;
    Ok(vec![command(0x18, 0), command(0x13, 1), Packet { bytes, acknowledgement: false }, command(0x02, 0), end])
}

#[derive(Clone, Copy, Debug, Default)]
pub struct Settings {
    pub disable_win: bool,
    pub disable_alt_f4: bool,
    pub disable_alt_tab: bool,
    pub fn_toggle: bool,
    /// Original UI index: 0=never, 1=1 minute, 2=5 minutes, 3=30 minutes.
    pub sleep_index: u8,
    pub response_level: u8,
}

/// Four-packet wired settings sequence at 0x414190; not yet hardware validated.
pub fn settings(value: Settings) -> Result<Vec<Packet>, &'static str> {
    if value.sleep_index > 3 || !(1..=5).contains(&value.response_level) {
        return Err("Settings parameter out of range");
    }
    let mut setup = command(0x17, 1);
    setup.bytes[2] = 1;
    let mut bytes = [0; REPORT_SIZE];
    bytes[1] = 1;
    bytes[2] = value.disable_win as u8;
    bytes[3] = value.disable_alt_f4 as u8;
    bytes[4] = value.disable_alt_tab as u8;
    bytes[5] = value.fn_toggle as u8;
    bytes[6] = value.sleep_index;
    bytes[8] = value.response_level;
    bytes[62..64].copy_from_slice(&[0xaa, 0x55]);
    Ok(vec![command(0x18, 0), setup, Packet { bytes, acknowledgement: false }, command(0x02, 0)])
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default)]
pub struct Binding {
    pub index: u16,
    /// 0=default, 1=disabled, 2=keyboard, 3=consumer/media.
    pub kind: u8,
    pub modifiers: u8,
    pub usage: u16,
}

/// Complete 576-byte key table at 0x419690. Unknown keys remain firmware-default.
/// This writes an entire layer; it must never be described as a single-key patch.
pub fn keymap(bindings: &[Binding], fn_layer: bool) -> Result<Vec<Packet>, &'static str> {
    let mut table = [0u8; 576];
    let mut used = [false; 122];
    for binding in bindings {
        let i = binding.index as usize;
        if !(1..=121).contains(&i) || used[i] {
            return Err("Invalid or duplicate physical key index");
        }
        used[i] = true;
        let entry = &mut table[i * 4..i * 4 + 4];
        match binding.kind {
            0 => (),
            1 => entry.copy_from_slice(&[0x05, 0x03, 0, 0]),
            2 => {
                if binding.usage > 0xff { return Err("Keyboard usage exceeds one byte"); }
                let usage = binding.usage as u8;
                if (0xe0..=0xe7).contains(&usage) && binding.modifiers == 0 {
                    entry.copy_from_slice(&[2, 1 << (usage - 0xe0), 0, 0]);
                } else {
                    if (0xe0..=0xe7).contains(&usage) { return Err("Use the modifier mask for chord modifiers"); }
                    entry.copy_from_slice(&[2, binding.modifiers, usage, 0]);
                }
            }
            3 => entry.copy_from_slice(&[3, binding.usage as u8, (binding.usage >> 8) as u8, 0]),
            4 => {
                if binding.usage>=100{return Err("Macro slot out of range");}
                entry.copy_from_slice(&[6,binding.usage as u8,if binding.modifiers>1{1}else{0},binding.modifiers.max(1)]);
            }
            _ => return Err("Binding kind is not implemented"),
        }
    }
    table[574..576].copy_from_slice(&[0xaa, 0x55]);
    let mut packets = vec![command(0x18, 0), command(if fn_layer {0x27} else {0x11}, 9)];
    packets.extend(table.chunks_exact(64).map(|chunk| {
        let mut bytes = [0; 64];
        bytes.copy_from_slice(chunk);
        Packet { bytes, acknowledgement: false }
    }));
    packets.push(command(0x02, 0));
    // This call site waits for the f0 acknowledgement, unlike the RGB call site.
    packets.push(command(0xf0, 0));
    Ok(packets)
}

/// 65-byte Windows representation; byte zero is the report ID, NOT command 0x04.
pub fn windows_report(packet: &Packet) -> [u8; 65] {
    let mut out = [0; 65];
    out[1..].copy_from_slice(&packet.bytes);
    out
}

// C ABI: contiguous payloads; flags bit 0 requests an acknowledgement read.
// The caller supplies capacity in packets. On any error, nothing is copied.
fn copy_packets(result: Result<Vec<Packet>, &'static str>, out: *mut u8, flags: *mut u8, capacity: usize) -> i32 {
    let Ok(packets) = result else { return -1; };
    if out.is_null() || flags.is_null() || capacity < packets.len() { return -2; }
    unsafe {
        for (i, packet) in packets.iter().enumerate() {
            std::ptr::copy_nonoverlapping(packet.bytes.as_ptr(), out.add(i * REPORT_SIZE), REPORT_SIZE);
            *flags.add(i) = packet.acknowledgement as u8;
        }
    }
    packets.len() as i32
}

#[no_mangle]
pub extern "C" fn l99_build_lighting(mode: u8, r: u8, g: u8, b: u8, brightness: u8, speed: u8, direction: u8, colorful: u8, out: *mut u8, flags: *mut u8, capacity: usize) -> i32 {
    copy_packets(lighting(Lighting { mode, rgb: [r,g,b], brightness, speed, direction, colorful: colorful != 0 }), out, flags, capacity)
}

#[no_mangle]
pub extern "C" fn l99_build_settings(disable_win: u8, disable_alt_f4: u8, disable_alt_tab: u8, fn_toggle: u8, sleep_index: u8, response_level: u8, out: *mut u8, flags: *mut u8, capacity: usize) -> i32 {
    copy_packets(settings(Settings { disable_win: disable_win != 0, disable_alt_f4: disable_alt_f4 != 0, disable_alt_tab: disable_alt_tab != 0, fn_toggle: fn_toggle != 0, sleep_index, response_level }), out, flags, capacity)
}

/// # Safety
/// `bindings` must address `count` initialized Binding values, or count must be 0.
#[no_mangle]
pub unsafe extern "C" fn l99_build_keymap(bindings: *const Binding, count: usize, fn_layer: u8, out: *mut u8, flags: *mut u8, capacity: usize) -> i32 {
    if count > 121 || (count != 0 && bindings.is_null()) { return -1; }
    let bindings = if count == 0 { &[] } else { slice::from_raw_parts(bindings, count) };
    copy_packets(keymap(bindings, fn_layer != 0), out, flags, capacity)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn joined(packets: Vec<Packet>) -> Vec<u8> { packets.into_iter().flat_map(|p| p.bytes).collect() }
    #[test]fn macro_headers_events_and_palette(){
        let packets=macro_table(&[MacroEvent{slot:0,usage:4,delay_ms:50,action:0},MacroEvent{slot:0,usage:4,delay_ms:50,action:1}],1).unwrap();
        let table=joined(packets[2..packets.len()-1].to_vec());
        assert_eq!(&table[..2],&400u16.to_le_bytes());
        assert_eq!(&table[400..402],&[4,0]);
        assert_eq!(&table[408..416],&[0,0,4,0xb0,50,0,0,0x50]);
        assert_eq!(&table[416..424],&[0,0,4,0x30,50,0,0,0x50]);
        let colors=custom_colors(&[KeyColor{index:56,r:255,g:128,b:0}],5).unwrap();
        let rgb=joined(colors[7..16].to_vec());
        assert_eq!(&rgb[224..228],&[56,255,128,0]);
    }
    fn fixture(hex: &str) -> Vec<u8> {
        let hex=hex.trim();
        (0..hex.len()).step_by(2).map(|i|u8::from_str_radix(&hex[i..i+2],16).unwrap()).collect()
    }

    #[test]
    fn rgb_matches_original_x86_serializer() {
        let cases: [(Lighting, &str); 3] = [
            (Lighting {mode:11,rgb:[0x12,0x34,0x56],brightness:5,speed:3,direction:2,colorful:true},include_str!("../tests/fixtures/rgb_wave.hex")),
            (Lighting {mode:1,rgb:[0,255,128],brightness:2,speed:1,direction:0,colorful:false},include_str!("../tests/fixtures/rgb_static.hex")),
            (Lighting {mode:0,rgb:[0xab,0xcd,0xef],brightness:0,speed:5,direction:3,colorful:true},include_str!("../tests/fixtures/rgb_off.hex")),
        ];
        for (value, expected) in cases { assert_eq!(joined(lighting(value).unwrap()), fixture(expected)); }
    }

    #[test]
    fn full_layer_layout_and_modifiers() {
        let packets = keymap(&[
            Binding {index:56,kind:2,modifiers:8,usage:6}, // Cmd+C on physical A
            Binding {index:93,kind:2,modifiers:0,usage:0xe3},
            Binding {index:121,kind:1,..Binding::default()},
        ], false).unwrap();
        let table=joined(packets[2..11].to_vec());
        assert_eq!(&table[224..228], &[2,8,6,0]);
        assert_eq!(&table[372..376], &[2,8,0,0]);
        assert_eq!(&table[484..488], &[5,3,0,0]);
        assert_eq!(&table[574..], &[0xaa,0x55]);
        assert_eq!(packets.len(),13);
        assert_eq!(packets[1].bytes[8],9);
        assert!(packets[12].acknowledgement);
    }

    #[test]
    fn rejects_ambiguous_and_invalid_bindings() {
        let b=Binding {index:56,kind:2,usage:4,..Binding::default()};
        assert!(keymap(&[b,b],false).is_err());
        assert!(keymap(&[Binding {index:0,..b}],false).is_err());
        assert!(keymap(&[Binding {usage:0x104,..b}],false).is_err());
        assert!(keymap(&[Binding {usage:0xe3,modifiers:2,..b}],false).is_err());
    }

    #[test]
    fn ffi_does_not_partially_write_short_buffer() {
        let mut out=[0xcc;64];let mut flags=[0xcc];
        assert_eq!(l99_build_lighting(11,1,2,3,5,3,0,0,out.as_mut_ptr(),flags.as_mut_ptr(),1),-2);
        assert_eq!(out,[0xcc;64]);assert_eq!(flags,[0xcc]);
    }

    #[test]
    fn report_id_is_separate_from_payload() {
        let packet=command(0x18,0);let report=windows_report(&packet);
        assert_eq!(&report[..4],&[0,4,0x18,0]);
    }

    #[test]
    fn settings_limits_and_positions() {
        let packets=settings(Settings {sleep_index:2,response_level:3,disable_win:true,..Settings::default()}).unwrap();
        assert_eq!(&packets[1].bytes[..3], &[4,0x17,1]);
        assert_eq!(&packets[2].bytes[..9], &[0,1,1,0,0,0,2,0,3]);
        assert!(settings(Settings {response_level:0,..Settings::default()}).is_err());
    }
}
