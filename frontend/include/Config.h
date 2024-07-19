#ifndef _KACONFIG_H
#define _KACONFIG_H

#include <vector>
#include <map>
#include <unordered_map>
#include <set>
#include <unordered_set>
#include <fstream>
#include <map>
//#define DEBUG

//#define STAT
using std::string;
using std::vector;
using std::map;

//
// Configurations
//

//#define DEBUG_MLTA

extern int ENABLE_MLTA;
#define SOUND_MODE 1
#define MAX_TYPE_LAYER 10

#define MAP_CALLER_TO_CALLEE 1
//#define UNROLL_LOOP_ONCE 1
#define MAP_DECLARATION_FUNCTION
//#define PRINT_ICALL_TARGET
// Path to source code
#define SOURCE_CODE_PATH "/data/ruizhe/semalloc/test/input"
//#define PRINT_SOURCE_LINE
//#define MLTA_FIELD_INSENSITIVE

const vector<string> InitialHeapFunctions = {"malloc", "realloc", "calloc", "posix_memalign", "memalign", "_Znwm", "_Znam", "aligned_alloc"};
const map<string, uint16_t> HeapFunctionSizeParameterIndex = {
        {"malloc", 0},
        {"realloc", 1},
        {"calloc", 1},
        {"posix_memalign", 2},
        {"memalign", 1},
	{"_Znwm", 0},
	{"_Znam", 0},
        {"aligned_alloc", 1}
};

#define SIZE_BIT 32
#define MAX_SIZE ((1UL << SIZE_BIT) - 1)
#define CSI_BIT 16
#define RH_BIT 14
#define CSI_OFFSET SIZE_BIT

#define LOOP_BIT         0x4000000000000000UL
#define LOOP_BIT_REVERSE 0xBFFFFFFFFFFFFFFFUL
#define HUGE_BIT         0x8000000000000000UL
#define HUGE_BIT_REVERSE 0x7FFFFFFFFFFFFFFFUL
#define CSI_MASK         0x0000FFFF00000000UL

const string CSTrackVariableName = "semallocCSTrack";
const string CSSRecursiveStackName = "CSSRecursiveStack";
const string CSSRecursiveOffsetTrackName = "CSSRecursiveOffsetTrack";
const string CSSLoopLayerTrackName = "CSSLoopLayerTrack";
const string CSSRecursiveHashName = "CSSRecursiveHash";
const string CSSHashFunctionName = "_Z15CSSHashFunctionPKmm";

#ifdef DEBUG
const string CSSDebugSaveFunctionName = "_Z12CSSSaveTrackmPmPS_PcS1_";
const string CSSDebugCheckFunctionName = "_Z13CSSCheckTrackmPmPS_PcS1_";
const string CSSDebugPrintFunctionName = "_ZL13CSSPrintTrackmPcS_S_";
const string CSSDebugArrayName = "CSSDebugArray";
#endif

#define CSS_RECURSIVE_STACK_BOUND 1000 // workaround
#endif
