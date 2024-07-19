#include "PreMLTA.hh"

void PreMLTAPass::LowerInvokeCalls() {

    for (llvm::Function &F: *_M) {
        for (llvm::BasicBlock &BB : F) {
            if (auto *II = llvm::dyn_cast<llvm::InvokeInst>(BB.getTerminator())) {
                llvm::SmallVector<llvm::Value *, 16> CallArgs(II->args());
                llvm::SmallVector<llvm::OperandBundleDef, 1> OpBundles;
                II->getOperandBundlesAsDefs(OpBundles);
                // Insert a normal call instruction...
                llvm::CallInst *NewCall =
                        llvm::CallInst::Create(II->getFunctionType(), II->getCalledOperand(),
                                         CallArgs, OpBundles, "", II);
                NewCall->setName("CallInstance_");

                // Carry the args
                NewCall->setCallingConv(II->getCallingConv());
                NewCall->setAttributes(II->getAttributes());
                NewCall->setDebugLoc(II->getDebugLoc());
                II->replaceAllUsesWith(NewCall);

                // update the map
                this->InvokeMap.insert({NewCall, II});
            }
        }
    }
}

void PreMLTAPass::run() {
    LowerInvokeCalls();
}


map<llvm::CallInst*, llvm::InvokeInst*> PreMLTAPass::getInvokeMap() {
    return this->InvokeMap;
}