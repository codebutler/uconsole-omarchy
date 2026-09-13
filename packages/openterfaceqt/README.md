# Openterface KVM on uConsole Omarchy

Built from the checksum-pinned 0.5.30 upstream source release using system Qt6,
FFmpeg and GStreamer. No AppImage, bundled runtime, FUSE, XWayland dependency,
or library-path wrapper is used. The desktop entry explicitly selects native
Wayland. A small source patch also prefers Wayland when both display sockets are
available, so terminal launches do not silently choose XWayland.
X11 client libraries are build/link dependencies of upstream code; they
are not an X server and do not require XWayland to run the Wayland frontend.

Launch **Openterface KVM** from Omarchy's application launcher, or run
`env -u DISPLAY QT_QPA_PLATFORM=wayland openterfaceQT --backend ffmpeg`.
It does not autostart or require root.
An empty device list is expected until the KVM is installed and connected.

The system-theme patch removes upstream's forced Fusion style, pinned palette
and application-wide button stylesheet. Launch from the desktop to inherit its
Qt theme settings; for remote testing, use
`uwsm app -t service -- com.openterface.openterfaceQT.desktop`.
Custom artwork and individually styled upstream widgets are not reskinned.

Device-specific udev rules grant the active local session USB/HID/serial access.
Normal system video/audio rules handle capture devices. No global serial-group
membership, boot overlay, automatic firmware flashing, or GPIO changes are made.

The launcher selects upstream's FFmpeg/Qt rendering backend and removes DISPLAY
for this process only. Upstream's GStreamer defaults include X11 video sinks;
forcing the Qt window onto Wayland alone would not prevent those using XWayland.
System-wide XWayland and other applications are left untouched.

Upstream recommends GStreamer and 9600 baud serial for the extension module:
https://docs.openterface.com/products/kvmext/software-setup/
Our FFmpeg backend selection differs deliberately to keep video inside native Qt.
Video, audio, keyboard/mouse control and switching still require physical hardware
tests. App startup without hardware does not verify those features.

Upstream source (AGPL-3.0):
https://github.com/TechxArtisanStudio/Openterface_QT/tree/44246790c7fc5b0541b724f3f7e4426cd9a62096
Publish corresponding sources/patches alongside distributed binary releases.
