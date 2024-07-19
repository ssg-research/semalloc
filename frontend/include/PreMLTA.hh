//
// Created by r53wang on 16/03/23.
//

#ifndef KANALYZER_PREMLTA_HH
#define KANALYZER_PREMLTA_HH

#include "Common.h"
#include "Analyzer.h"
#include "CallPath.hh"
#include "Config.h"
#include "RecursiveHelper.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/Dominators.h"
#include "llvm/Pass.h"
#include <queue>

class PreMLTAPass {
private:
    llvm::Module* _M;
    map<llvm::CallInst*, llvm::InvokeInst*> InvokeMap;

    void LowerInvokeCalls();


public:
    PreMLTAPass(llvm::Module* M) {
        _M = M;
    }

    void run();
    map<llvm::CallInst*, llvm::InvokeInst*> getInvokeMap();

};


#endif //KANALYZER_PREMLTA_HH
