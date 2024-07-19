//
// Created by r53wang on 1/8/24.
//

#ifndef KANALYZER_REDUCELIBRARYINDIRECTCALL_HH
#define KANALYZER_REDUCELIBRARYINDIRECTCALL_HH

#include "Common.h"
#include "Analyzer.h"
#include "CallPath.hh"
#include "Config.h"
#include "RecursiveHelper.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/Dominators.h"
#include "llvm/Pass.h"
#include <queue>

class ReduceLibraryIndirectCall {
private:
    llvm::Module* _M;

    /*
     * Callee -> Caller
     */
    map<string, string> HMFIndirectFunctions;

    void TraverseGlobalVariables4Malloc(llvm::Module*);
    void UpdateCFGWithIndirectCalls(map<string, vector<CallPath*>*>* FunctionMap);


public:
    ReduceLibraryIndirectCall(llvm::Module* M) {
        _M = M;
    }

    void run(map<string, vector<CallPath*>*>* FunctionMap);
};

#endif //KANALYZER_REDUCELIBRARYINDIRECTCALL_HH
