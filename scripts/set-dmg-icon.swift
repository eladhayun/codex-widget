// Finder file icons are extended metadata. HTTP downloads do not preserve them.
// The mounted volume's .VolumeIcon.icns is independently embedded in the DMG.
import AppKit

guard CommandLine.arguments.count == 3,
      let icon = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
    fputs("Usage: set-dmg-icon.swift ICON.icns IMAGE.dmg\n", stderr)
    exit(1)
}
guard NSWorkspace.shared.setIcon(icon, forFile: CommandLine.arguments[2], options: []) else {
    fputs("Could not set the DMG Finder icon.\n", stderr)
    exit(1)
}
