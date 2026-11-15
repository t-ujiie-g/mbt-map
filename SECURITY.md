# Security policy

moon-map reads data from the network (tiles, styles, GeoJSON, 3D Tiles, service documents), so malformed or hostile input is treated as a security concern: decoders are expected to fail safely, with bounded memory and time.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub's [private vulnerability reporting](https://github.com/t-ujiie-g/moon-map/security/advisories/new) rather than in a public issue. Include the input or steps that reproduce it if you can.

You can expect an acknowledgement within a week. Fixes are released as patch versions and credited in the advisory unless you prefer otherwise.

## Supported versions

Until 1.0, only the latest release receives security fixes.
