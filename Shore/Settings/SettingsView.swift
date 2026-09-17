import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: ShoreSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            moduleCard(
                title: "Island",
                subtitle: "Hugs the hardware notch. Hover expands instantly; click pins the player.",
                symbol: "water.waves",
                isOn: $settings.islandEnabled
            )
            moduleCard(
                title: "File shelf",
                subtitle: "Drop files onto the island to park them, then drag them out when you need them.",
                symbol: "tray",
                isOn: $settings.fileShelfEnabled
            )
            moduleCard(
                title: "Dock Tide Line",
                subtitle: "A quiet glass shoreline above the Dock. Click-through, original, minimal.",
                symbol: "dock.rectangle",
                isOn: $settings.dockEnabled
            )
            Toggle(isOn: $settings.sampleWhenIdle) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sample media when idle")
                        .font(.system(size: 13, weight: .medium))
                    Text("Keeps a design preview track when MediaRemote has nothing to show.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 4)
            Spacer(minLength: 0)
            Text("Shore stays on this Mac. v1 is free. Unsigned builds need a Gatekeeper bypass — see the README.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 380, height: 520)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "water.waves")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ShorePalette.seaGlass)
                .frame(width: 36, height: 36)
                .background(ShorePalette.inkLift, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Shore")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Quiet extras for the Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func moduleCard(title: String, subtitle: String, symbol: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ShorePalette.foam)
                .frame(width: 28, height: 28)
                .background(ShorePalette.ink, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(ShoreSettings.shared)
}
