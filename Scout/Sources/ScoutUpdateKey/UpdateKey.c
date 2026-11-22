#include "ScoutUpdateKey.h"
#include <stddef.h>

const char *scout_update_public_key(void) {
#ifdef SCOUT_UPDATE_PUBLIC_KEY
    return SCOUT_UPDATE_PUBLIC_KEY;
#else
    return NULL;
#endif
}
