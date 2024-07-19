//
// Created by r53wang on 16/03/23.
//

#ifndef KANALYZER_CALLPATH_HH
#define KANALYZER_CALLPATH_HH

#include "llvm/IR/Instruction.h"

using std::string;

class CallPath {
public:
    enum CallType {
        DirectCall, IndirectCall
    };

    enum PathType {
        Default, MarkSimpleLoop, MarkSimpleInner, MarkInnerBranch, MarkInbound, MarkOutbound, MarkBranch
    };

    uint32_t edgeWeight;
    llvm::Instruction* call_inst;
    CallType call_type;
    PathType path_type;
    string Callee;
    string Caller;
    bool callsHMF;
    bool isRelevant;

    explicit CallPath(llvm::Instruction* _call_inst, CallType _call_type, PathType _path_type, string _callee, string _caller) {
        call_inst = _call_inst;
        call_type = _call_type;
        path_type = _path_type;
        Callee = _callee;
        Caller = _caller;
        callsHMF = false;
        isRelevant = false;
        edgeWeight = 0;
    }

};


#endif //KANALYZER_CALLPATH_HH
