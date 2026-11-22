#ifndef SCOUT_UPDATE_KEY_H
#define SCOUT_UPDATE_KEY_H

/// The public half of the Ed25519 key this build trusts for updates, in base64, or NULL for a build
/// given none, which refuses every update. Set by Scripts/build-scout.sh through Package.swift.
const char *_Nullable scout_update_public_key(void);

#endif
