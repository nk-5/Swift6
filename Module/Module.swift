//
//  Module.swift
//  Module
//
//  Created by Keigo Nakagawa on 2025/07/31.
//

import Foundation

public protocol LoggerProtocol {
    func log(_ message: String)
}

//@MainActor
//public class Logger {
public actor Logger {
    public var isEnabled: Bool = true

    public init() {}

    public func log(_ message: String) {
        print("log:", message)
    }
}
