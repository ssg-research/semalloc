//
// Created by Ruizhe Wang on 2023-03-14.
//

#ifndef KANALYZER_CONSTRUCTCG_HH
#define KANALYZER_CONSTRUCTCG_HH


#include "Analyzer.h"
#include "Config.h"
#include "CallPath.hh"

#define LLVM_FUNCTION_PREFIX "llvm."

class ConstructCGPass :
        public virtual IterativeModulePass {

private:

    //
    // Variables
    //
    map<string, vector<CallPath*>*>* FunctionMap;
    GlobalContext *GCtx;
    //
    // Methods
    //
    void AnalyzeDirectFunctionCallsWithinFunction(llvm::Function &F);

    void MergeIndirectFunctionCalls();

    static void LowerInvoke(llvm::Function &F);


public:
    explicit ConstructCGPass(GlobalContext *Ctx_)
            : IterativeModulePass(Ctx_, "ConstructCG") {
        GCtx = Ctx_;
        FunctionMap = new map<string, vector<CallPath*>*>;
    }

    bool doInitialization(llvm::Module *) override;
    bool doModulePass(llvm::Module *) override;
    bool run();
    void PrintConstructedCG();

    map<string, vector<CallPath*>*>* getFunctionMap();

};


#endif //KANALYZER_CONSTRUCTCG_HH
