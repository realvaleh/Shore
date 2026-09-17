import CoreAudio
import Foundation
import IOKit.ps
import SwiftUI

struct LiveChip: Identifiable, Equatable {
    enum Kind: String {
        case battery
        case volume
    }

    var kind: Kind
    var id: Kind { kind }
    var symbol: String
    var label: String
    var progress: Double
    var emphasized: Bool
}

@MainActor
final class LiveChipStore: ObservableObject {
    @Published private(set) var chips: [LiveChip] = []

    private var timer: Timer?
    private var lastVolume: Double?
    private var lastBattery: Double?
    private var lastCharging: Bool?
    private var volumePulseUntil = Date.distantPast
    private var batteryPulseUntil = Date.distantPast

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func toggleMute() {
        VolumeControl.toggleMute()
        refresh()
    }

    func nudgeVolume(_ delta: Double) {
        VolumeControl.nudge(delta)
        refresh()
    }

    private func refresh() {
        var next: [LiveChip] = []
        let now = Date()

        if let battery = BatteryReading.current() {
            if lastBattery.map({ abs($0 - battery.level) > 0.01 }) ?? false
                || lastCharging.map({ $0 != battery.charging }) ?? false {
                batteryPulseUntil = now.addingTimeInterval(1.4)
            }
            lastBattery = battery.level
            lastCharging = battery.charging
            next.append(
                LiveChip(
                    kind: .battery,
                    symbol: battery.symbol,
                    label: "\(Int((battery.level * 100).rounded()))%",
                    progress: battery.level,
                    emphasized: now < batteryPulseUntil
                )
            )
        }

        if let volume = VolumeReading.current() {
            if lastVolume.map({ abs($0 - volume.level) > 0.012 }) ?? false {
                volumePulseUntil = now.addingTimeInterval(1.2)
            }
            lastVolume = volume.level
            next.append(
                LiveChip(
                    kind: .volume,
                    symbol: volume.symbol,
                    label: volume.muted ? "Mute" : "\(Int((volume.level * 100).rounded()))",
                    progress: volume.muted ? 0 : volume.level,
                    emphasized: now < volumePulseUntil
                )
            )
        }

        chips = next
    }
}

struct ChipRow: View {
    @ObservedObject var store: LiveChipStore
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(store.chips) { chip in
                LiveChipView(
                    chip: chip,
                    compact: compact,
                    onTap: {
                        if chip.kind == .volume {
                            store.toggleMute()
                        }
                    },
                    onVerticalDrag: chip.kind == .volume
                        ? { store.nudgeVolume($0) }
                        : nil
                )
            }
        }
        // Chips own their clicks so they never collapse / pin the island.
        .buttonStyle(.plain)
    }
}

struct LiveChipView: View {
    var chip: LiveChip
    var compact: Bool = false
    var onTap: () -> Void
    var onVerticalDrag: ((Double) -> Void)?

    @State private var lastDrag: CGFloat = 0

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: chip.symbol)
                    .font(.system(size: 9, weight: .semibold))
                Text(chip.label)
                    .font(ShoreType.chip())
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
                    .opacity(compact ? 0 : 1)
                    .frame(width: compact ? 0 : nil, alignment: .leading)
                    .clipped()
            }
            .foregroundStyle(ShorePalette.foam.opacity(chip.emphasized ? 1 : 0.86))
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, 3)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(ShorePalette.seaGlass.opacity(chip.progress * 0.18))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(chip.emphasized ? 0.22 : 0.08), lineWidth: 0.6)
                    }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .help(helpText)
        .scaleEffect(chip.emphasized ? 1.04 : 1)
        .animation(.shoreFoam, value: chip.emphasized)
        .simultaneousGesture(volumeDrag)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(chip.kind == .volume ? .isButton : [])
    }

    private var volumeDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard let onVerticalDrag else { return }
                let delta = Double(lastDrag - value.translation.height) / 140
                lastDrag = value.translation.height
                if abs(delta) > 0.0005 {
                    onVerticalDrag(delta)
                }
            }
            .onEnded { _ in lastDrag = 0 }
    }

    private var helpText: String {
        switch chip.kind {
        case .battery: "Battery \(chip.label) — live reading"
        case .volume: "Click to mute or unmute. Drag vertically to change volume."
        }
    }

    private var accessibilityText: String {
        switch chip.kind {
        case .battery: "Battery \(chip.label)"
        case .volume: "Volume \(chip.label)"
        }
    }

    private var accessibilityHint: String {
        switch chip.kind {
        case .battery: "Display only. Does not collapse the island."
        case .volume: "Toggles mute. Does not collapse the island."
        }
    }
}

private struct BatteryReading {
    var level: Double
    var charging: Bool

    var symbol: String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case 0.9...: return "battery.100percent"
        case 0.65..<0.9: return "battery.75percent"
        case 0.4..<0.65: return "battery.50percent"
        case 0.15..<0.4: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    static func current() -> BatteryReading? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [AnyObject]
        else { return nil }

        for source in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as NSDictionary? else {
                continue
            }
            let type = desc[kIOPSTypeKey] as? String
            guard type == kIOPSInternalBatteryType else { continue }
            let current = (desc[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let maxCapacity = (desc[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
            guard maxCapacity > 0 else { continue }
            let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
            return BatteryReading(
                level: Swift.min(1, Swift.max(0, current / maxCapacity)),
                charging: charging
            )
        }
        return nil
    }
}

private struct VolumeReading {
    var level: Double
    var muted: Bool

    var symbol: String {
        if muted || level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.33 { return "speaker.wave.1.fill" }
        if level < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    static func current() -> VolumeReading? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr, device != 0 else {
            return nil
        }

        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyMute
        address.mScope = kAudioDevicePropertyScopeOutput
        address.mElement = kAudioObjectPropertyElementMain
        let muteStatus = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)

        var volume = Float32(0)
        size = UInt32(MemoryLayout<Float32>.size)
        address.mSelector = kAudioDevicePropertyVolumeScalar
        var volumeStatus = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        if volumeStatus != noErr {
            address.mElement = 1
            volumeStatus = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        }
        guard volumeStatus == noErr else { return nil }

        return VolumeReading(
            level: min(1, max(0, Double(volume))),
            muted: muteStatus == noErr && muted != 0
        )
    }
}

private enum VolumeControl {
    static func toggleMute() {
        guard let device = defaultOutputDevice() else { return }
        var address = outputAddress(kAudioDevicePropertyMute)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        if status == noErr {
            var next: UInt32 = muted == 0 ? 1 : 0
            _ = AudioObjectSetPropertyData(device, &address, 0, nil, size, &next)
            return
        }
        if let reading = VolumeReading.current() {
            setLevel(reading.muted || reading.level <= 0.001 ? 0.5 : 0)
        }
    }

    static func nudge(_ delta: Double) {
        guard let reading = VolumeReading.current() else { return }
        if reading.muted, delta > 0 {
            toggleMute()
        }
        setLevel(reading.level + delta)
    }

    static func setLevel(_ value: Double) {
        guard let device = defaultOutputDevice() else { return }
        var address = outputAddress(kAudioDevicePropertyVolumeScalar)
        var volume = Float32(Swift.min(1, Swift.max(0, value)))
        var size = UInt32(MemoryLayout<Float32>.size)
        var status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume)
        if status != noErr {
            address.mElement = 1
            status = AudioObjectSetPropertyData(device, &address, 0, nil, size, &volume)
        }
        _ = status
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr, device != 0 else {
            return nil
        }
        return device
    }

    private static func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
