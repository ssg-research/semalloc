//
// Created by Ruizhe Wang on 2023-03-14.
//

#include "llvm/Pass.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Instruction.h"
#include "llvm/IR/Instructions.h"
#include "llvm/Support/Debug.h"
#include "llvm/IR/DebugInfo.h"
#include "llvm/IR/InstIterator.h"
#include "llvm/IR/Constants.h"
#include "llvm/ADT/StringExtras.h"
#include "llvm/Analysis/CallGraph.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/IR/InstrTypes.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/LoopPass.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"
#include "llvm/IR/IRBuilder.h"
#include "llvm/IR/CFG.h"

#include "Common.h"
#include "ConstructCG.hh"

#include <map>
#include <vector>


using namespace llvm;


void ConstructCGPass::PrintConstructedCG() {
//    outs() << "<<< Number of Functions <<< " << this->FunctionMap->size() << "\n";
//    for (auto const& MapEntry: *this->FunctionMap) {
//        outs() << MapEntry.first << " <- " << MapEntry.second->size() << "\n";
//        for (auto CalledInstance : *MapEntry.second) {
//            outs() << "\t" << CalledInstance->call_inst->getParent()->getParent()->getName().str() << "\n";
//        }
//    }

    for (auto const& MapEntry: *this->FunctionMap) {
        for (auto CalledInstance : *MapEntry.second) {
            outs() << "[LINE] " << MapEntry.first;
            outs() << " " << CalledInstance->call_inst->getParent()->getParent()->getName().str();
            if (CalledInstance->call_type == CallPath::IndirectCall) {
                outs() << " Indirect ";
            } else {
                outs() << " Direct ";
            }

//            if (CalledInstance->path_type == CallPath::PathType::MarkLoopSingle || CalledInstance->path_type == CallPath::PathType::MarkLoopFunction) {
//                outs() << "Loop\n";
//            } else {
//                outs() << "Unloop\n";
//            }
        }
    }
}


void ConstructCGPass::MergeIndirectFunctionCalls() {
    for (auto IC : this->GCtx->IndirectCallInsts) {
        for (auto Callee: GCtx->Callees[IC]) {
            this->FunctionMap->at(Callee->getName().str())->push_back(new CallPath(IC,
                                                                            CallPath::IndirectCall,
                                                                            CallPath::Default,
                                                                            Callee->getName().str(),
                                                                            IC->getFunction()->getName().str()));
        }
    }
}

void ConstructCGPass::AnalyzeDirectFunctionCallsWithinFunction(Function &F){
    for (auto &BB: F) {
        for (auto &Inst: BB) {
            if (auto* call_inst = dyn_cast<CallInst>(&Inst)) {
                // handle indirect call via MLTA
                if (call_inst->isIndirectCall()) {
                    continue;
                }

                //asm call
                if (call_inst->isInlineAsm()) {
                    continue;
                }

                Function* fn = call_inst->getCalledFunction();
                if (!fn) {
                    // bit cast
                    fn = dyn_cast<Function>(call_inst->getCalledOperand()->stripPointerCasts());
                }

                if (!fn) {
                    call_inst->print(outs());
                    outs() << "\n";
                    continue;
                }

                string CalledFunctionName = fn->getName().str();
                if (CalledFunctionName.rfind(LLVM_FUNCTION_PREFIX, 0) == 0) {
                    continue;
                }

                // thread spawn functions: omp or pthread
//                auto size = call_inst->arg_size();
//                for (int i = 0; i < size; i++) {
//                    auto tmp = call_inst->getArgOperand(i);
//                    auto finalFunc = dyn_cast<Function>(tmp);
//                    if (!finalFunc) {
//                        finalFunc = dyn_cast<Function>(tmp->stripPointerCasts());
//                    }
//
//                    if (finalFunc) {
//                        this->FunctionMap->at(finalFunc->getName().str())
//                        ->push_back(new CallPath(
//                                call_inst,
//                                CallPath::DirectCall,
//                                CallPath::Default,
//                                finalFunc->getName().str(),
//                                CalledFunctionName));
//                    }
//                }


                this->FunctionMap->at(CalledFunctionName)->push_back(new CallPath(call_inst,
                                                                                 CallPath::DirectCall,
                                                                                 CallPath::Default,
                                                                                 CalledFunctionName,
                                                                                 F.getName().str()));
            }
        }
    }
}


bool ConstructCGPass::doInitialization(llvm::Module *M) {
    for (auto &Function : M->getFunctionList()) {
        string Name = Function.getName().str();

        // LLVM internal functions
        if (Name.rfind(LLVM_FUNCTION_PREFIX, 0) == 0) {
            continue;
        }

        (*this->FunctionMap)[Name] = new vector<CallPath*>();
    }

    MergeIndirectFunctionCalls();

    return false;
}


void ConstructCGPass::LowerInvoke(llvm::Function &F) {
    for (BasicBlock &BB : F)
        if (auto *II = dyn_cast<InvokeInst>(BB.getTerminator())) {
            SmallVector<Value *, 16> CallArgs(II->args());
            SmallVector<OperandBundleDef, 1> OpBundles;
            II->getOperandBundlesAsDefs(OpBundles);
            // Insert a normal call instruction...
            CallInst *NewCall =
                    CallInst::Create(II->getFunctionType(), II->getCalledOperand(),
                                     CallArgs, OpBundles, "", II);
            NewCall->takeName(II);
            NewCall->setCallingConv(II->getCallingConv());
            NewCall->setAttributes(II->getAttributes());
            NewCall->setDebugLoc(II->getDebugLoc());
            II->replaceAllUsesWith(NewCall);

            // Insert an unconditional branch to the normal destination.
            BranchInst::Create(II->getNormalDest(), II);

            // Remove any PHI node entries from the exception destination.
            II->getUnwindDest()->removePredecessor(&BB);

            // Remove the invoke instruction now.
            II->eraseFromParent();
        }
}


bool ConstructCGPass::doModulePass(llvm::Module *M) {
    for (auto &Function : M->getFunctionList()) {
       // LowerInvoke(Function);
        AnalyzeDirectFunctionCallsWithinFunction(Function);
    }

    return false;
}

bool ConstructCGPass::run() {
    auto ModuleList = this->GCtx->Modules;

    for (auto M: ModuleList) {
        doInitialization(M.first);
    }

    for (auto M: ModuleList) {
        doModulePass(M.first);
    }
    return false;
}


map<string, vector<CallPath*>*>* ConstructCGPass::getFunctionMap() {
    return this->FunctionMap;
}
