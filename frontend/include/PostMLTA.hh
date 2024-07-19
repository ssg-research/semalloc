//
// Created by r53wang on 16/03/23.
//

#ifndef KANALYZER_POSTMLTA_HH
#define KANALYZER_POSTMLTA_HH

#include "Common.h"
#include "Analyzer.h"
#include "CallPath.hh"
#include "Config.h"
#include "RecursiveHelper.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/Dominators.h"
#include "llvm/Pass.h"
#include <queue>

class PostMLTAPass {
private:
    llvm::Module* _M;

    /*
     * Callee -> Caller
     */
    map<string, vector<CallPath*>*>* _FunctionMap;
    map<llvm::CallInst*, llvm::InvokeInst*> _Call2InvokeMap;

    void RecoverInvokeCalls();
    void DuplicateInvokeUnwinds();


public:
    PostMLTAPass(llvm::Module* M, map<string,
                 vector<CallPath*>*>* FunctionMap,
                 const map<llvm::CallInst*, llvm::InvokeInst*>& Call2InvokeMap) {
        _M = M;
        _FunctionMap = FunctionMap;
        _Call2InvokeMap = Call2InvokeMap;
    }

    void run();
};


#endif //KANALYZER_POSTMLTA_HH
