//
// Created by r53wang on 1/8/24.
//

#include "ReduceLibraryIndirectCall.hh"

void ReduceLibraryIndirectCall::TraverseGlobalVariables4Malloc(llvm::Module* M) {
    for (auto &GV : M->globals()) {
        // Check if the global variable is a pointer to a function
        if (GV.getValueType()->isPointerTy()) {
            // Check if the initializer points to malloc
            if (GV.hasInitializer()) {
                if (auto *F = llvm::dyn_cast<llvm::Function>(GV.getInitializer())) {
                    for (const auto& HMF: InitialHeapFunctions) {
                        if (F->getName().str() == HMF) {
                            llvm::outs() << "Global variable " << GV.getName().str()
                                         << " is initialized with " << HMF << "\n";

                            HMFIndirectFunctions[GV.getName().str()] = HMF;
                        }
                    }
                }
            }
        }
    }
}


void ReduceLibraryIndirectCall::UpdateCFGWithIndirectCalls(map<string, vector<CallPath*>*>* FunctionMap) {
    for (llvm::Function &F: *_M) {
        for (llvm::BasicBlock &BB : F) {
            for (auto &I : BB) {
                if (llvm::dyn_cast<llvm::CallInst>(&I) == nullptr) {
                    continue;
                }

                // must be an indirect call
                auto CI = llvm::dyn_cast<llvm::CallInst>(&I);
                if (!CI->isIndirectCall()) {
                    continue;
                }

                if (auto *loadedVal = llvm::dyn_cast<llvm::LoadInst>(CI->getCalledOperand())) {
                    if (auto *globalVar = llvm::dyn_cast<llvm::GlobalVariable>(loadedVal->getPointerOperand())) {
                        auto calleeName = globalVar->getName().str();
                        if (HMFIndirectFunctions.find(calleeName) == HMFIndirectFunctions.end()) {
                            continue;
                        }

                        // find the target, update the CFG
                        llvm::outs() << "Indirect call to " << HMFIndirectFunctions[calleeName] << " masked by "
                                     << calleeName << "\n";

                        FunctionMap->at(HMFIndirectFunctions[calleeName])->push_back(
                                new CallPath(CI,
                                             CallPath::IndirectCall,
                                             CallPath::Default,
                                             HMFIndirectFunctions[calleeName],
                                             F.getName().str()));
                    }
                }
            } // end for instructions
        }
    }
}

void ReduceLibraryIndirectCall::run(map<string, vector<CallPath*>*>* FunctionMap) {
    TraverseGlobalVariables4Malloc(_M);
    UpdateCFGWithIndirectCalls(FunctionMap);
}

