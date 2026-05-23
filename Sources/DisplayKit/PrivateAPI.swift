import CoreGraphics
import CoreFoundation

// Private CoreGraphics symbol used by Lunar's BlackOut and BetterDisplay to
// take a display offline without unplugging it. If Apple removes or changes
// the symbol on a future macOS, the enable/disable operations stop working;
// list/main keep working because they use only public APIs.
@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(
    _ config: CGDisplayConfigRef,
    _ display: CGDirectDisplayID,
    _ enabled: Bool
) -> CGError

// Public CoreGraphics symbol that the Swift overlay does not always re-export.
// Declared explicitly so DisplayKit compiles cleanly across Swift versions.
@_silgen_name("CGDisplayCreateUUIDFromDisplayID")
func CGDisplayCreateUUIDFromDisplayID(_ display: CGDirectDisplayID) -> Unmanaged<CFUUID>?
