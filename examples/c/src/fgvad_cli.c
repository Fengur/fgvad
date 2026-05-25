#include <stdio.h>
#include "fgvad.h"

int main(void) {
    enum FgVadState s = fgvad_state(NULL);
    printf("fgvad C demo: fgvad_state(NULL) = %d (expect 0=Idle)\n", (int)s);
    return s == FgVadState_Idle ? 0 : 1;
}
