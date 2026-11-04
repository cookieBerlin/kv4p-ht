#if os(macOS)
    import CoreAudio
    import Foundation
    import os

    /// Silences all other apps on a Mac through a Core Audio tap, which silences them only while it is read. The audio
    /// read here is thrown away. All logic lives in `OtherAudioController`; this file is excluded from coverage (ADR-0044).
    public final class CoreAudioOtherAppsMute: OtherAudioSwitching, @unchecked Sendable {
        private struct Failure: Error, CustomStringConvertible {
            let call: String
            let status: OSStatus

            var description: String { "\(call) failed: \(status)" }
        }

        private static let log = Logger(subsystem: "io.github.cookieberlin.kv4pht", category: "other-apps")

        /// Core Audio calls block, too long for the main thread; everything below runs here.
        private let queue = DispatchQueue(label: "kv4p.other-apps", qos: .userInitiated)
        private var tap = AudioObjectID(kAudioObjectUnknown)
        private var device = AudioObjectID(kAudioObjectUnknown)
        private var proc: AudioDeviceIOProcID?
        private var outputChanged: AudioObjectPropertyListenerBlock?

        public init() {
            let outputChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.rebuild() }
            self.outputChanged = outputChanged
            var output = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &output, queue, outputChanged)
        }

        deinit {
            stop()
        }

        /// Another process puts out audio; this one does not count.
        public var isOtherAudioPlaying: Bool {
            let own = getpid()
            return Self.processes().contains { process in
                guard let pid: pid_t = Self.value(of: process, kAudioProcessPropertyPID), pid != own,
                    let isRunning: UInt32 = Self.value(of: process, kAudioProcessPropertyIsRunningOutput)
                else { return false }
                return isRunning != 0
            }
        }

        public func lowerOtherAudio(_ mode: OtherAudioMode) async throws {
            try await startIfNeeded()
        }

        public func silenceOtherAudio() async throws {
            try await startIfNeeded()
        }

        public func releaseOtherAudio() async {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                queue.async { [self] in
                    stop()
                    done.resume()
                }
            }
        }

        /// The output never stopped, so there is nothing to bring back.
        public func mixWithOtherAudio() async throws {}

        /// Who counts as playing, for the log.
        private static func playingProcesses() -> String {
            let own = getpid()
            return processes().compactMap { process -> String? in
                guard let pid: pid_t = value(of: process, kAudioProcessPropertyPID), pid != own,
                    let isRunning: UInt32 = value(of: process, kAudioProcessPropertyIsRunningOutput), isRunning != 0
                else { return nil }
                var property = address(kAudioProcessPropertyBundleID)
                var bundle: Unmanaged<CFString>?
                var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
                _ = AudioObjectGetPropertyData(process, &property, 0, nil, &size, &bundle)
                return "\(bundle?.takeRetainedValue() as String? ?? "?") (\(pid))"
            }
            .joined(separator: ", ")
        }

        private func startIfNeeded() async throws {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
                queue.async { [self] in
                    do {
                        Self.log.info("other audio: playing: \(Self.playingProcesses(), privacy: .public)")
                        try startTap()
                        done.resume()
                    } catch {
                        Self.log.error("other audio: mute failed: \(String(describing: error), privacy: .public)")
                        stop()
                        done.resume(throwing: error)
                    }
                }
            }
        }

        /// A tap belongs to one output device; it silences nothing once the user changed to another.
        private func rebuild() {
            guard proc != nil else { return }
            stop()
            do {
                try startTap()
            } catch {
                Self.log.error(
                    "other audio: mute failed after a change of output: \(String(describing: error), privacy: .public)"
                )
                stop()
            }
        }

        private func startTap() throws {
            guard proc == nil else { return }
            guard let own = Self.ownProcess() else { throw Failure(call: "own process", status: -1) }
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [own])
            description.name = "kv4p HT other apps"
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            try Self.check("create tap", AudioHardwareCreateProcessTap(description, &tap))

            guard
                let output: AudioObjectID = Self.value(
                    of: AudioObjectID(kAudioObjectSystemObject),
                    kAudioHardwarePropertyDefaultOutputDevice
                ),
                let outputUID = Self.deviceUID(of: output)
            else { throw Failure(call: "default output", status: -1) }
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "kv4p HT other apps",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [
                    [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]
                ],
            ]
            try Self.check("create aggregate", AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device))
            try Self.check("create proc", AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { _, _, _, _, _ in })
            try Self.check("start device", AudioDeviceStart(device, proc))
        }

        private func stop() {
            if let proc {
                AudioDeviceStop(device, proc)
                AudioDeviceDestroyIOProcID(device, proc)
            }
            proc = nil
            if device != kAudioObjectUnknown {
                AudioHardwareDestroyAggregateDevice(device)
            }
            device = AudioObjectID(kAudioObjectUnknown)
            if tap != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tap)
            }
            tap = AudioObjectID(kAudioObjectUnknown)
        }

        // MARK: Core Audio properties

        private static func check(_ call: String, _ status: OSStatus) throws {
            if status != noErr { throw Failure(call: call, status: status) }
        }

        private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        }

        private static func value<T>(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
            var property = address(selector)
            var size = UInt32(MemoryLayout<T>.size)
            let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
            defer { pointer.deallocate() }
            guard AudioObjectGetPropertyData(object, &property, 0, nil, &size, pointer) == noErr else { return nil }
            return pointer.move()
        }

        private static func ownProcess() -> AudioObjectID? {
            var property = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
            var pid = getpid()
            var own = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &property,
                UInt32(MemoryLayout<pid_t>.size),
                &pid,
                &size,
                &own
            )
            return status == noErr && own != kAudioObjectUnknown ? own : nil
        }

        private static func deviceUID(of device: AudioObjectID) -> String? {
            var property = address(kAudioDevicePropertyDeviceUID)
            var uid: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &uid) == noErr else { return nil }
            return uid?.takeRetainedValue() as String?
        }

        private static func processes() -> [AudioObjectID] {
            let system = AudioObjectID(kAudioObjectSystemObject)
            var property = address(kAudioHardwarePropertyProcessObjectList)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr else { return [] }
            var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            guard AudioObjectGetPropertyData(system, &property, 0, nil, &size, &list) == noErr else { return [] }
            return list
        }
    }
#endif
