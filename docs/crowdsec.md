# CrowdSec

CrowdSec remediation belongs on OPNsense through the official `os-crowdsec` plugin. The retired ingress-nginx controller and its Lua bouncer are not part of this design.

Before setting `OPNSENSE_CROWDSEC_VERIFIED=true` for the production sanity gate:

1. Confirm the plugin is current and enabled.
2. Confirm acquisition and LAPI decisions are healthy.
3. Confirm the firewall aliases/tables update.
4. Run a controlled ban/unban test from a non-administration address.
5. Confirm LAN/VPN administration networks remain explicitly allowed.

Record plugin version, test timestamp, and screenshots/export in the operational evidence bundle.
