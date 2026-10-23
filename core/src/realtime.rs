// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

//! Volatile clock and telemetry update. No firmware or image-memory writes.
use crate::{command, Packet};

#[repr(C)]
#[derive(Clone, Copy, Debug)]
pub struct Realtime {
    pub year: u16,
    pub month: u8,
    pub day: u8,
    pub hour: u8,
    pub minute: u8,
    pub second: u8,
    /// Sunday = 0, Saturday = 6; always Gregorian, in the Mac's local zone.
    pub weekday: u8,
    pub cpu: u8,
    pub cpu_temperature: u8,
    pub gpu: u8,
    pub gpu_temperature: u8,
    /// Replaces the weather temperature on the built-in Real-time Data page.
    pub display_temperature: u8,
}

pub fn packets(value: Realtime) -> Result<Vec<Packet>, &'static str> {
    let leap = value.year % 4 == 0 && (value.year % 100 != 0 || value.year % 400 == 0);
    let days = match value.month {
        2 => if leap { 29 } else { 28 },
        4 | 6 | 9 | 11 => 30,
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        _ => return Err("Invalid month"),
    };
    if !(2000..=2099).contains(&value.year) || !(1..=days).contains(&value.day)
        || value.hour > 23 || value.minute > 59 || value.second > 59 || value.weekday > 6
        || value.cpu > 100 || value.gpu > 100 || value.cpu_temperature > 125
        || value.gpu_temperature > 125 || value.display_temperature > 125 {
        return Err("Invalid clock or metrics");
    }
    let mut bytes = [0; 64];
    bytes[1] = 1;
    bytes[2] = 0x5a;
    bytes[3..9].copy_from_slice(&[(value.year - 2000) as u8, value.month, value.day,
        value.hour, value.minute, value.second]);
    bytes[10] = value.weekday;
    bytes[13..17].copy_from_slice(&[value.cpu, value.cpu_temperature, value.gpu, value.gpu_temperature]);
    bytes[17..20].fill(value.display_temperature);
    // Weather icon and humidity remain zero. There is no network weather lookup.
    bytes[62..64].copy_from_slice(&[0xaa, 0x55]);
    Ok(vec![command(0x18, 0), command(0x28, 1),
        Packet { bytes, acknowledgement: false }, command(0x02, 0)])
}

#[cfg(test)]
mod tests {
    use super::*;
    fn sample() -> Realtime {
        Realtime { year: 2026, month: 10, day: 20, hour: 14, minute: 25, second: 30,
            weekday: 2, cpu: 37, cpu_temperature: 62, gpu: 18, gpu_temperature: 55, display_temperature: 61 }
    }
    #[test]
    fn matches_captured_serializer() {
        let data: Vec<u8> = packets(sample()).unwrap().into_iter().flat_map(|p| p.bytes).collect();
        let hex=include_str!("../tests/fixtures/realtime.hex").trim();
        let expected:Vec<u8>=(0..hex.len()).step_by(2).map(|i|u8::from_str_radix(&hex[i..i+2],16).unwrap()).collect();
        assert_eq!(data,expected);
        let p = packets(sample()).unwrap();
        assert_eq!(p.iter().map(|p| p.acknowledgement).collect::<Vec<_>>(), [true,true,false,true]);
    }
    #[test]
    fn rejects_invalid_calendar_and_metrics() {
        let mut v = sample(); v.month = 2; v.day = 29;
        assert!(packets(v).is_err());
        v.year = 2028; assert!(packets(v).is_ok());
        v.cpu = 101; assert!(packets(v).is_err());
        v.cpu = 100; v.weekday = 7; assert!(packets(v).is_err());
    }
}
