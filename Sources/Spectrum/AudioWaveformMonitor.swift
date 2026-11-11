import Accelerate
import CoreAudio
import Foundation
import SpectrumCore

@MainActor
final class AudioWaveformMonitor {
    private let model: NotchModel
    private var stopTap: (() -> Void)?
    private var active = false
    private var generation = 0
    private var retryAfter = Date.distantPast

    init(model: NotchModel) { self.model = model }

    func setActive(_ active: Bool) {
        guard active != self.active else { return }
        self.active = active
        generation += 1
        guard active else {
            stopTap?()
            stopTap = nil
            model.waveformLevels = nil
            return
        }
        guard #available(macOS 14.2, *), Date() >= retryAfter else { return }
        let generation = self.generation
        do {
            let tap = try WaveformTap { [weak self] levels in
                DispatchQueue.main.async {
                    guard let self, self.generation == generation else { return }
                    self.model.waveformLevels = levels
                }
            }
            stopTap = { tap.stop() }
        } catch {
            retryAfter = Date().addingTimeInterval(30)
            log.error("starting audio waveform failed: \(error)")
        }
    }
}

@available(macOS 14.2, *)
private final class WaveformTap {
    private struct TapError: Error {
        let operation: String
        let status: OSStatus
    }

    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var running = false

    init(deliver: @escaping @Sendable ([Double]) -> Void) throws {
        do {
            let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
            description.name = "Spectrum Waveform"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try Self.check(AudioHardwareCreateProcessTap(description, &tap), "create audio tap")

            var property = AudioObjectPropertyAddress(
                mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var format = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try Self.check(
                AudioObjectGetPropertyData(tap, &property, 0, nil, &size, &format),
                "read tap format")
            guard format.mFormatID == kAudioFormatLinearPCM,
                format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32
            else { throw TapError(operation: "unsupported tap format", status: -1) }

            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Spectrum Waveform",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapListKey: [
                    [kAudioSubTapUIDKey: description.uuid.uuidString]
                ],
                kAudioAggregateDeviceTapAutoStartKey: true,
            ]
            try Self.check(
                AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device),
                "create tap device")

            let sampler = LevelSampler(deliver: deliver)
            try Self.check(
                AudioDeviceCreateIOProcIDWithBlock(
                    &ioProc, device, DispatchQueue(label: "spectrum.audio-levels")
                ) { _, input, _, _, _ in
                    sampler.read(input)
                }, "read system audio")
            try Self.check(AudioDeviceStart(device, ioProc), "start system audio")
            running = true
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let ioProc {
            if running { AudioDeviceStop(device, ioProc) }
            AudioDeviceDestroyIOProcID(device, ioProc)
            self.ioProc = nil
            running = false
        }
        if device != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(device)
            device = kAudioObjectUnknown
        }
        if tap != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tap)
            tap = kAudioObjectUnknown
        }
    }

    deinit { stop() }

    private static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw TapError(operation: operation, status: status) }
    }
}

/// Core Audio calls the sampler on the serial I/O queue.
private final class LevelSampler: @unchecked Sendable {
    private let deliver: @Sendable ([Double]) -> Void
    private var envelope = WaveformEnvelope()
    private var lastSample: UInt64 = 0

    init(deliver: @escaping @Sendable ([Double]) -> Void) {
        self.deliver = deliver
    }

    func read(_ input: UnsafePointer<AudioBufferList>) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard now - lastSample >= 66_666_667 else { return }
        lastSample = now
        var rms: Float = 0
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            guard let data = buffer.mData, count > 0 else { continue }
            var level: Float = 0
            vDSP_rmsqv(data.assumingMemoryBound(to: Float.self), 1, &level, vDSP_Length(count))
            rms = max(rms, level)
        }
        envelope.append(rms: rms)
        deliver(envelope.levels)
    }
}
