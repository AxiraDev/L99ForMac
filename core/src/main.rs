// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

use aula_l99_core::{lighting, Lighting};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() != 1 || args[0] != "rgb-example" {
        eprintln!("Usage: l99-packets rgb-example\nPrints packets only; never opens hardware.");
        std::process::exit(2);
    }
    let packets=lighting(Lighting {mode:11,rgb:[0x12,0x34,0x56],brightness:5,speed:3,direction:2,colorful:true}).unwrap();
    for (i,p) in packets.iter().enumerate() {
        println!("{} ack={} {}", i+1,p.acknowledgement,p.bytes.iter().map(|b|format!("{b:02x}")).collect::<String>());
    }
}
