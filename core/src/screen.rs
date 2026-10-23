// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

//! Independently implemented user-image containers for the L99 display.
use std::collections::HashMap;
pub const WIDTH: usize=320;
pub const HEIGHT: usize=480;
pub const FRAME_RGBA: usize=WIDTH*HEIGHT*4;
pub const FRAME_RGB565: usize=WIDTH*HEIGHT*2;

pub fn crc16(data:&[u8])->u16 {
    let mut value=0xffffu16;
    for b in data {value^=*b as u16;for _ in 0..8 {value=(value>>1)^if value&1!=0{0xa001}else{0};}}
    value
}
fn rgb565(rgba:&[u8])->Vec<u8>{
    rgba.chunks_exact(4).flat_map(|p|{
        let v=((p[0] as u16 & 0xf8)<<8)|((p[1] as u16 & 0xfc)<<3)|(p[2] as u16>>3);
        v.to_le_bytes()
    }).collect()
}
/// An LT frame contains a 256-entry RGB565 palette and either indices or runs.
/// This is a format implementation, not manufacturer source or machine code.
fn lt_frame(pixels:&[u8],width:u16,height:u16)->Result<Vec<u8>,&'static str>{
    let mut palette=Vec::<u16>::new();
    let mut lookup=HashMap::<u16,u8>::new();
    let mut indices=Vec::with_capacity(pixels.len()/2);
    for p in pixels.chunks_exact(2){
        let color=u16::from_le_bytes([p[0],p[1]]);
        let index=if let Some(index)=lookup.get(&color){*index}else{
            if palette.len()==256{return Err("GIF frames must be quantized to at most 256 colors");}
            let index=palette.len()as u8;palette.push(color);lookup.insert(color,index);index
        };
        indices.push(index);
    }
    let mut runs=Vec::new();let mut position=0;
    while position<indices.len(){
        let color=indices[position];let mut count=1;
        while count<256 && position+count<indices.len() && indices[position+count]==color{count+=1;}
        runs.extend_from_slice(&[(count-1)as u8,color]);position+=count;
    }
    let compressed=runs.len()<indices.len();
    let content=if compressed{&runs}else{&indices};
    let size=12+516+content.len();
    let mut out=Vec::with_capacity(size+1);
    out.extend_from_slice(b"LT");out.extend_from_slice(&width.to_le_bytes());out.extend_from_slice(&height.to_le_bytes());
    out.extend_from_slice(&[1,3]);out.extend_from_slice(&(size as u32).to_le_bytes());
    let descriptor=content.len()as u32 | if compressed{0x01000000}else{0};
    out.extend_from_slice(&descriptor.to_le_bytes());
    for i in 0..256{out.extend_from_slice(&palette.get(i).copied().unwrap_or(0).to_le_bytes());}
    out.extend_from_slice(content);if out.len()%2!=0{out.push(0);}
    Ok(out)
}
fn encode_images(rgba:&[u8],delays_ms:&[u16],animation:bool,width:u16,height:u16)->Result<Vec<u8>,&'static str>{
    let frames=delays_ms.len();let frame_bytes=width as usize*height as usize*4;
    if !(1..=200).contains(&frames) || (!animation && frames!=1) || frame_bytes==0 || rgba.len()!=frames*frame_bytes{return Err("Expected complete RGBA frames");}
    let mut bodies=Vec::with_capacity(frames);
    for frame in rgba.chunks_exact(frame_bytes){
        let pixels=rgb565(frame);
        bodies.push(if animation{lt_frame(&pixels,width,height)?}else{pixels});
    }
    let body:Vec<u8>=bodies.iter().flatten().copied().collect();
    let checksum=crc16(&body);
    let mut out=Vec::with_capacity(body.len()+if animation{20*frames}else{11});
    if animation {
        let mut offset=20*frames;
        for (i,delay) in delays_ms.iter().enumerate(){
            out.extend_from_slice(&(offset as u32).to_le_bytes());out.extend_from_slice(&(body.len()as u32).to_le_bytes());
            out.extend_from_slice(&width.to_le_bytes());out.extend_from_slice(&height.to_le_bytes());
            out.extend_from_slice(&[3,frames as u8,0,0]);out.extend_from_slice(&delay.to_le_bytes());out.extend_from_slice(&checksum.to_le_bytes());
            offset+=bodies[i].len();
        }
    } else {
        out.extend_from_slice(&(body.len()as u32).to_le_bytes());out.extend_from_slice(&width.to_le_bytes());out.extend_from_slice(&height.to_le_bytes());
        out.push(0);out.extend_from_slice(&checksum.to_le_bytes());
    }
    out.extend_from_slice(&body);Ok(out)
}
pub fn encode(rgba:&[u8],delays_ms:&[u16],animation:bool)->Result<Vec<u8>,&'static str>{encode_images(rgba,delays_ms,animation,WIDTH as u16,HEIGHT as u16)}

#[cfg(test)]mod tests{
    use super::*;
    fn fixture(s:&str)->Vec<u8>{let s=s.trim();(0..s.len()).step_by(2).map(|i|u8::from_str_radix(&s[i..i+2],16).unwrap()).collect()}
    #[test]fn crc_standard_vector(){assert_eq!(crc16(b"123456789"),0x4b37);}
    #[test]fn complete_native_animation_fixture(){
        let frames:[u32;16]=[0xffff0000,0xff00ff00,0xff0000ff,0xff000000,0xffffffff,0xff123456,0xfff0b060,0xff306090,0xffabcdef,0xffabcdef,0xffabcdef,0xffabcdef,0xff123456,0xff123456,0xff123456,0xff123456];
        let rgba:Vec<u8>=frames.iter().flat_map(|p|[(*p>>16)as u8,(*p>>8)as u8,*p as u8,255]).collect();
        let data=encode_images(&rgba,&[350,140,350,140],true,2,2).unwrap();
        assert_eq!(data,fixture(include_str!("../tests/fixtures/gif_complete_four_frames.hex")));
    }
    #[test]fn animation_lt_runs_and_boundaries(){
        let rgba=vec![0;FRAME_RGBA*2];let data=encode(&rgba,&[100,200],true).unwrap();
        let offset=u32::from_le_bytes(data[..4].try_into().unwrap())as usize;
        assert_eq!(offset,40);assert_eq!(&data[offset..offset+2],b"LT");
        assert_eq!(&data[offset+6..offset+8],&[1,3]);
        let packed=&data[offset+528..];assert_eq!(&packed[..4],&[255,0,255,0]);
        assert_eq!(u16::from_le_bytes([data[18],data[19]]),crc16(&data[40..]));
        assert!(encode(&rgba,&[100,200],false).is_err());
    }
    #[test]fn lt_run_limit_and_raw_indices(){
        let mut pixels=Vec::new();for _ in 0..257{pixels.extend_from_slice(&0x1234u16.to_le_bytes());}
        let frame=lt_frame(&pixels,257,1).unwrap();
        assert_eq!(&frame[528..],&[255,0,0,0]);
        assert_eq!(u32::from_le_bytes(frame[12..16].try_into().unwrap()),0x01000004);
        let pixels=[0,0,1,0,2,0,3,0];let frame=lt_frame(&pixels,2,2).unwrap();
        assert_eq!(&frame[528..],&[0,1,2,3]);assert_eq!(&frame[12..16],&[4,0,0,0]);
        assert_eq!(&frame[16..24],&pixels);
    }
    #[test]fn picture_container(){
        let mut rgba=vec![0;FRAME_RGBA];rgba[..12].copy_from_slice(&[255,0,0,255,0,255,0,255,0,0,255,255]);
        let data=encode(&rgba,&[100],false).unwrap();assert_eq!(data.len(),307211);
        assert_eq!(&data[..9],&[0,0xb0,4,0,0x40,1,0xe0,1,0]);assert_eq!(&data[11..17],&[0,0xf8,0xe0,7,0x1f,0]);
        assert_eq!(u16::from_le_bytes([data[9],data[10]]),crc16(&data[11..]));assert!(encode(&rgba,&[],false).is_err());assert!(encode(&[],&[100],false).is_err());
    }
}
