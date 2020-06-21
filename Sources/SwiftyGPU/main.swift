//
//  main.swift
//  
//
//  Created by Palle Klewitz on 21.06.20.
//  Copyright (c) 2020 - Palle Klewitz
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import Foundation
import IOKit

extension String {
    func leftPadding(toLength targetLength: Int, using character: Character) -> String {
        if count > targetLength {
            return String(self.suffix(targetLength))
        } else if count == targetLength {
            return self
        } else {
            return String(repeating: character, count: targetLength - count) + self
        }
    }
}

func getAccelerators() -> [Dictionary<String, AnyObject>] {
    var accelerators: [Dictionary<String, AnyObject>] = []
    var iterator = io_iterator_t()
    if IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(kIOAcceleratorClassName), &iterator) == kIOReturnSuccess {
        repeat {
            let entry = IOIteratorNext(iterator)
            defer {
                IOObjectRelease(entry)
            }
            guard entry != 0 else {
                break
            }
            var serviceDict: Unmanaged<CFMutableDictionary>? = nil
            
            guard IORegistryEntryCreateCFProperties(entry, &serviceDict, kCFAllocatorDefault, 0) == kIOReturnSuccess else {
                break
            }
            if let serviceDict = serviceDict {
                accelerators.append(Dictionary(uniqueKeysWithValues: (serviceDict.takeRetainedValue() as NSDictionary as Dictionary).map {($0 as! String, $1)}))
            }
        } while true

        IOObjectRelease(iterator)
    }
    return accelerators
}

func getPCIDevices() -> [Dictionary<String, AnyObject>] {
    var accelerators: [Dictionary<String, AnyObject>] = []
    var iterator = io_iterator_t()
    if IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching("IOPCIDevice"), &iterator) == kIOReturnSuccess {
        repeat {
            let entry = IOIteratorNext(iterator)
            defer {
                IOObjectRelease(entry)
            }
            guard entry != 0 else {
                break
            }
            var serviceDict: Unmanaged<CFMutableDictionary>? = nil
            
            guard IORegistryEntryCreateCFProperties(entry, &serviceDict, kCFAllocatorDefault, 0) == kIOReturnSuccess else {
                break
            }
            if let serviceDict = serviceDict {
                accelerators.append(Dictionary(uniqueKeysWithValues: (serviceDict.takeRetainedValue() as NSDictionary as Dictionary).map {($0 as! String, $1)}))
            }
        } while true

        IOObjectRelease(iterator)
    }
    return accelerators
}

func devicesMatch(accelerator: [String: AnyObject], pciDevice: [String: AnyObject]) -> Bool {
    let vendorID = (pciDevice["vendor-id"] as? Data)?.withUnsafeBytes { bytes -> UInt32? in
        bytes.bindMemory(to: UInt32.self).first
    } ?? 0xFFFF
    let deviceID = (pciDevice["device-id"] as? Data)?.withUnsafeBytes { bytes -> UInt32? in
        bytes.bindMemory(to: UInt32.self).first
    } ?? 0xFFFF
    
    guard let pciMatch = (accelerator["IOPCIMatch"] as? String ?? accelerator["IOPCIPrimaryMatch"] as? String)?.uppercased() else {
        return false
    }
    guard vendorID != 0xFFFF else {
        return false
    }
    if deviceID != 0xFFFF {
        let combo = deviceID << 16 | vendorID
        return pciMatch.contains(String(combo, radix: 16).uppercased())
    } else {
        return pciMatch.hasSuffix(String(vendorID, radix: 16).uppercased()) || pciMatch.contains(String(vendorID, radix: 16).uppercased() + " ")
    }
}

let accelerators = getAccelerators()
let pciDevices = getPCIDevices()

struct Device {
    var accelerator: [String: AnyObject]
    var pciDevice: [String: AnyObject]
    
    var name: String? {
        let nameCandidates: [String?] = [
            (pciDevice["model"] as? Data).flatMap {String(data: $0, encoding: .utf8)},
            accelerator["IOGLBundleName"] as? String
        ]
        return nameCandidates.reduce(nil, {$0 ?? $1}).map {String($0.prefix(while: {$0 != "\u{0}"}))}
    }
    
    var usedVRAMMiB: Int? {
        guard let totalVRAMMiB = self.totalVRAMMiB else {
            return nil
        }
        if let statistics = accelerator["PerformanceStatistics"] {
            let memCandidates: [Int?] = [
                (statistics["vramUsedBytes"] as? NSNumber)?.intValue,
                (statistics["vramFreeBytes"] as? NSNumber).map {(totalVRAMMiB << 20) - $0.intValue},
                (statistics["gartUsedBytes"] as? NSNumber)?.intValue,
                (statistics["gartFreeBytes"] as? NSNumber).map {(totalVRAMMiB << 20) - $0.intValue}
            ]
            return (memCandidates.reduce(nil, {$0 ?? $1}) ?? 0) >> 20
        } else {
            return nil
        }
    }
    
    var totalVRAMMiB: Int? {
        if let totalMiB = (accelerator["VRAM,totalMB"] as? NSNumber)?.intValue {
            return totalMiB
        } else if let totalMiB = (pciDevice["VRAM,totalMB"] as? NSNumber)?.intValue {
            return totalMiB
        } else if let totalB = (pciDevice["ATY,memsize"] as? NSNumber)?.intValue {
            return totalB >> 20
        } else {
            return nil
        }
    }
    
    var deviceUtilizationPercent: Int? {
        if let statistics = accelerator["PerformanceStatistics"] {
            let utilizationCandidates: [Int?] = [
                (statistics["Device Utilization %"] as? NSNumber)?.intValue,
                (statistics["hardwareWaitTime"] as? NSNumber).map {max(min($0.intValue / 1000 / 1000 / 10, 100), 0)}
            ]
            
            return utilizationCandidates.reduce(nil, {$0 ?? $1})
        } else {
            return nil
        }
    }
}

struct DeviceUtilization: Codable {
    var name: String?
    var usedVRAMBytes: Int?
    var totalVRAMByte: Int?
    var deviceUtilizationPercent: Int?
}

struct Report: Codable {
    var devices: [DeviceUtilization]
    var timestamp: Date
}

var devs: [Device] = []
var remainingPCIDevices = pciDevices

for acc in accelerators {
    guard let pciDeviceIdx = remainingPCIDevices.firstIndex(where: {devicesMatch(accelerator: acc, pciDevice: $0)}) else {
        continue
    }
    let pciDevice = remainingPCIDevices.remove(at: pciDeviceIdx)
    devs.append(Device(accelerator: acc, pciDevice: pciDevice))
}

if CommandLine.arguments.contains("--raw") {
    let report = Report(
        devices: devs.map { dev in
            DeviceUtilization(name: dev.name, usedVRAMBytes: dev.usedVRAMMiB.map {$0 << 20}, totalVRAMByte: dev.totalVRAMMiB.map {$0 << 20}, deviceUtilizationPercent: dev.deviceUtilizationPercent)
        },
        timestamp: Date()
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    let data = try encoder.encode(report)
    print(String(data: data, encoding: .utf8)!)
    exit(0)
}

let formatter = DateFormatter()
formatter.timeStyle = .long
formatter.dateStyle = .long

print(String(repeating: "-", count: 80))
print("| SwiftyGPU " + formatter.string(from: Date()).leftPadding(toLength: 66, using: " ") + " |")
print(String(repeating: "-", count: 80))

print("| ID | Name".padding(toLength: 39, withPad: " ", startingAt: 0) + "|          VRAM (used/total) | GPU Util ".padding(toLength: 40, withPad: " ", startingAt: 0) + "|")
print(String(repeating: "-", count: 80))

for (i, (dev)) in devs.enumerated() {
    print("|" + "\(i)".leftPadding(toLength: 3, using: " ") + " | ", terminator: "") // total length: 6
    
    var name = dev.name ?? "<unknown device>"
    if name.count >= 31 {
        name = name.prefix(28) + "..."
    }
    
    print(name.padding(toLength: 32, withPad: " ", startingAt: 0) + "|", terminator: "") // total length: 32
    
    let usedVRAMMiB: Int = dev.usedVRAMMiB ?? -1
    let totalVRAMMiB: Int = dev.totalVRAMMiB ?? -1
    
    let usagePercent: Int = dev.deviceUtilizationPercent ?? -1
    
    let totalVRAM = "\(totalVRAMMiB) MiB"
    let usedVRAM = "\(usedVRAMMiB) MiB"
    
    print(" \(usedVRAM) / \(totalVRAM)".leftPadding(toLength: 27, using: " ") + " |", terminator: "")
    
    print(" \(usagePercent) %".leftPadding(toLength: 9, using: " ") + " |")

    print(String(repeating: "-", count: 80))
}

