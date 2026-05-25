#include "event_fmt.h"
#include <stdio.h>

const char *fgvad_event_label(enum FgVadEvent e) {
    switch (e) {
        case FgVadEvent_None_:               return "None";
        case FgVadEvent_SentenceStarted:     return "SentenceStarted";
        case FgVadEvent_SentenceEnded:       return "SentenceEnded";
        case FgVadEvent_SentenceForceCut:    return "SentenceForceCut";
        case FgVadEvent_HeadSilenceTimeout:  return "HeadSilenceTimeout";
        case FgVadEvent_MaxDurationReached:  return "MaxDurationReached";
        default:                             return "Unknown";
    }
}

const char *fgvad_state_label(enum FgVadState s) {
    switch (s) {
        case FgVadState_Idle:       return "Idle";
        case FgVadState_Detecting:  return "Detecting";
        case FgVadState_Started:    return "Started";
        case FgVadState_Voiced:     return "Voiced";
        case FgVadState_Trailing:   return "Trailing";
        case FgVadState_End:        return "End";
        default:                    return "Unknown";
    }
}

const char *fgvad_end_reason_label(enum FgVadEndReason r) {
    switch (r) {
        case FgVadEndReason_None_:              return "None";
        case FgVadEndReason_SpeechCompleted:    return "SpeechCompleted";
        case FgVadEndReason_HeadSilenceTimeout: return "HeadSilenceTimeout";
        case FgVadEndReason_MaxDurationReached: return "MaxDurationReached";
        case FgVadEndReason_ExternalStop:       return "ExternalStop";
        default:                                return "Unknown";
    }
}

const char *fgvad_result_type_label(enum FgVadResultType t) {
    switch (t) {
        case FgVadResultType_Silence:        return "Silence";
        case FgVadResultType_SentenceStart:  return "SentenceStart";
        case FgVadResultType_Active:         return "Active";
        case FgVadResultType_SentenceEnd:    return "SentenceEnd";
        default:                             return "Unknown";
    }
}

void fgvad_format_timestamp(uint64_t sample_offset, char *buf, size_t buf_size) {
    uint64_t total_ms = sample_offset / 16; /* 16 samples per ms @ 16kHz */
    uint64_t mm = total_ms / 60000;
    uint64_t ss = (total_ms / 1000) % 60;
    uint64_t mmm = total_ms % 1000;
    snprintf(buf, buf_size, "%02llu:%02llu.%03llu",
             (unsigned long long)mm,
             (unsigned long long)ss,
             (unsigned long long)mmm);
}
