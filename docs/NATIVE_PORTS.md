# Native ports

Android is the functional target in 1.0.0. Windows and iOS cannot share the
Android `VpnService`; each needs a platform VPN host and entitlements.

## Windows

Use the official embeddable `amneziawg-windows` tunnel service and expose a
small Flutter method-channel API matching `AmneziaWgBridge`: start, stop, state,
statistics and a VPN-bound HTTPS probe. Packaging must install/remove the
service with administrator consent. The UI must not claim a connection before
the service reports a live tunnel.

## iOS

Use the official `amneziawg-apple` WireGuardKit fork inside a Packet Tunnel
Network Extension. The app and extension require an Apple Developer team,
Network Extension entitlement and a shared App Group. Ordinary consumer iOS
apps cannot offer Android-style arbitrary per-app split tunnelling; that part
must be disabled or clearly labelled unless the app is deployed as a managed
per-app VPN.

These requirements are documented instead of publishing non-functional
Windows/iOS shells as VPN clients.
