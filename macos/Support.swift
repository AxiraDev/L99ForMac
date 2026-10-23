// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 L99 for Mac contributors

import Foundation

/// A public donation page, never payment credentials or an embedded checkout.
struct SupportConfiguration:Decodable {
    let donationURL:String
    static func validatedURL(_ value:String)->URL? {
        guard let components=URLComponents(string:value.trimmingCharacters(in:.whitespacesAndNewlines)),
              components.scheme?.lowercased()=="https",let host=components.host,!host.isEmpty,
              components.user==nil,components.password==nil,
              let url=components.url else{return nil}
        return url
    }
    var url:URL? {Self.validatedURL(donationURL)}
    static func load(bundle:Bundle = .main)->SupportConfiguration {
        guard let file=bundle.resourceURL?.appendingPathComponent("resources/support.json"),let data=try? Data(contentsOf:file),let value=try? JSONDecoder().decode(Self.self,from:data) else{return Self(donationURL:"")}
        return value
    }
}
