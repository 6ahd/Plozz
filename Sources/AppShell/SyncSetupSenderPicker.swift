#if os(tvOS)
import CoreUI
import FeatureSyncSetup
import SwiftUI

struct SyncSetupSenderPicker: View {
    let invite: SyncSetupSourceInvite?
    let inviteExpired: Bool
    let devices: [DiscoveredPairingDevice]
    @Binding var code: String
    let onRefresh: () -> Void
    let onSelect: (DiscoveredPairingDevice) -> Void
    let onSendCode: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                VStack(spacing: 14) {
                    Text("Set up another device").font(.largeTitle.bold())
                        .plozzForeground(.primary)
                    Text("Scan with your iPhone or iPad camera, or choose a nearby device.")
                        .font(.title3).plozzForeground(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(alignment: .top, spacing: 80) {
                    SyncSetupSourceQR(invite: invite, expired: inviteExpired, onRefresh: onRefresh)
                        .frame(width: 420)
                    VStack(alignment: .leading, spacing: 32) {
                        SyncSetupNearbyDevices(devices: devices, onSelect: onSelect)
                        SyncSetupManualCodeEntry(code: $code, onSend: onSendCode)
                    }
                    .frame(width: 620)
                }
                Button("Cancel", role: .cancel, action: onClose)
                    .plozzActionButton(role: .secondary)
            }
            .frame(maxWidth: 1240)
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .scrollClipDisabled()
        .defaultScrollAnchor(.center, for: .alignment)
    }
}

private struct SyncSetupSourceQR: View {
    let invite: SyncSetupSourceInvite?
    let expired: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("iPhone or iPad").font(.headline).plozzForeground(.primary)
            if let invite, !expired {
                QRCodeView(invite.encoded())
                    .frame(width: 264, height: 264)
                    .padding(20)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Scan to set up your iPhone or iPad")
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "qrcode").font(.system(size: 64))
                        .plozzForeground(.secondary)
                    Text("This QR code expired.").plozzForeground(.secondary)
                    Button("New QR Code", action: onRefresh)
                        .plozzActionButton(role: .secondary)
                }
                .frame(height: 304)
            }
            Text("Use the same Wi-Fi, then confirm the matching code on this TV.")
                .font(.caption).plozzForeground(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct SyncSetupNearbyDevices: View {
    let devices: [DiscoveredPairingDevice]
    let onSelect: (DiscoveredPairingDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Nearby devices").font(.headline).plozzForeground(.primary)
            Text("On the other device, choose “Set Up from Another Device” in Plozz.")
                .font(.caption).plozzForeground(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if devices.isEmpty {
                HStack(spacing: 16) {
                    ProgressView()
                    Text("Looking for a device…").plozzForeground(.secondary)
                }
                .padding(.vertical, 20)
            } else {
                ForEach(devices) { device in
                    Button { onSelect(device) } label: {
                        SyncSetupNearbyDeviceLabel(device: device)
                    }
                }
            }
        }
    }
}

struct SyncSetupNearbyDeviceLabel: View {
    let device: DiscoveredPairingDevice

    var body: some View {
        HStack(spacing: 22) {
            Image(systemName: "display.2").font(.title2)
            VStack(alignment: .leading, spacing: 8) {
                Text(device.displayName).font(.title3.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                // Inherit the native button's foreground, including focus inversion.
                Text("Code \(SyncPairingCode.grouped(device.serviceName))")
                    .font(.caption.monospacedDigit())
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SyncSetupManualCodeEntry: View {
    @Binding var code: String
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Or enter a code").font(.headline).plozzForeground(.primary)
            HStack(spacing: 20) {
                TextField("Code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .disableAutocorrection(true)
                    .frame(maxWidth: .infinity)
                Button("Set Up", action: onSend)
                    .plozzActionButton(role: .secondary)
                    .disabled(SyncPairingCode.normalize(code).count < 4)
            }
        }
    }
}
#endif
