# Native ports

Android is the functional target in 1.0.0. Windows and iOS cannot share the
Android `VpnService`; each needs a platform VPN host and entitlements.

## Windows

Version 1.1.6 embeds the official signed AmneziaWG 1.0.2 x64 tunnel runtime inside the
Pokolenie WARP ZIP. It does not install or launch the AmneziaWG manager UI and
does not create a second shortcut or startup entry. It creates a named tunnel
service with administrator consent, confirms the
Windows service is RUNNING, validates HTTPS over the full route, and reads
traffic via `awg show ... dump`. App-level split tunnelling still requires an
audited WFP driver and is deliberately disabled rather than emulated.

## iOS

Use the official `amneziawg-apple` WireGuardKit fork inside a Packet Tunnel
Network Extension. The app and extension require an Apple Developer team,
Network Extension entitlement and a shared App Group. Ordinary consumer iOS
apps cannot offer Android-style arbitrary per-app split tunnelling; that part
must be disabled or clearly labelled unless the app is deployed as a managed
per-app VPN.

These requirements are documented instead of publishing non-functional
Windows/iOS shells as VPN clients.
