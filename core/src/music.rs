// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

//! Transient spectrum updates: 18 bands consumed by the L99 firmware.
use crate::{command, Packet};

pub fn packets(levels: &[u8], foreground:u8, background:u8, brightness:u8) -> Result<Vec<Packet>, &'static str> {
    if levels.len()!=18 || levels.iter().any(|&v|v>99) || foreground>11 || background>11 || brightness>100 {
        return Err("Invalid music parameters");
    }
    let mut data=[0;64];
    data[..3].copy_from_slice(&[foreground,background,brightness]);
    data[3..21].copy_from_slice(levels);
    // The original sends 25 level slots; this firmware consumes the first 18.
    // Enter a fresh volatile transaction. Raw levels echo in the reply; byte 3 is
    // a level, not an ACK. Only the three command reports carry a status.
    Ok(vec![command(0x18,0),command(0x78,1),Packet{bytes:data,acknowledgement:false},command(2,0)])
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn matches_isolated_music_serializer() {
        let levels=[0,10,20,30,40,50,60,70,80,90,99,95,75,55,35,15,5,0];
        let p=packets(&levels,2,0,35).unwrap();
        let data:Vec<u8>=p[1..].iter().flat_map(|p|p.bytes).collect();
        let hex=include_str!("../tests/fixtures/music.hex").trim();
        let expected:Vec<u8>=(0..hex.len()).step_by(2).map(|i|u8::from_str_radix(&hex[i..i+2],16).unwrap()).collect();
        assert_eq!(data,expected);
        assert_eq!(p[0],command(0x18,0));
        assert_eq!(p.iter().map(|p|p.acknowledgement).collect::<Vec<_>>(),[true,true,false,true]);
    }
    #[test]
    fn rejects_unsafe_levels_and_modes() {
        assert!(packets(&[0;17],1,0,0).is_err());
        assert!(packets(&[100;18],1,0,0).is_err());
        assert!(packets(&[0;18],13,0,0).is_err());
        assert!(packets(&[0;18],1,0,101).is_err());
        assert!(packets(&[0;18],1,0,0).is_ok());
    }
}
