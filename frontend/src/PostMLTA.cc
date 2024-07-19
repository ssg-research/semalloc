#include "PostMLTA.hh"

void PostMLTAPass::RecoverInvokeCalls() {
    for (const auto& CalleeEntry: *_FunctionMap) {
        auto* Callers = CalleeEntry.second;
        for (auto* callPath: *Callers) {
            auto* callInst = llvm::dyn_cast<llvm::CallInst>(callPath->call_inst);

            // check converted from invoke or not
            if (_Call2InvokeMap.find(callInst) != _Call2InvokeMap.end()) {
                callPath->call_inst = _Call2InvokeMap[callInst];
            }
        }
    }

    for (auto entry: _Call2InvokeMap) {
        auto* callInst = entry.first;
        callInst->replaceAllUsesWith(entry.second);
        callInst->removeFromParent();
    }
}


void PostMLTAPass::run() {
    RecoverInvokeCalls();
    DuplicateInvokeUnwinds();
}


void PostMLTAPass::DuplicateInvokeUnwinds() {
    for (auto entry: _Call2InvokeMap) {
        auto* invokeInst = entry.second;
        auto* unwindDest = invokeInst->getUnwindDest();

        if (pred_size(unwindDest) == 1) {
            continue;
        }

        std::vector<llvm::BasicBlock*> unwindPredecessors;
        auto* landingPadInst = unwindDest->getFirstNonPHI();

        for (llvm::BasicBlock* p: predecessors(unwindDest)) {
            unwindPredecessors.push_back(p);
        }

        // first cut the destination to two parts: after the landingPad
        llvm::BasicBlock* mergeBlock = unwindDest->splitBasicBlock(landingPadInst->getNextNode(), "merge");


        // insert the PHI in the mergeBlock
        llvm::IRBuilder<> mBuilder(mergeBlock->getContext());
        mBuilder.SetInsertPoint(mergeBlock->getFirstNonPHI());
        llvm::PHINode* phi = mBuilder.CreatePHI(landingPadInst->getType(), 0);
        phi->addIncoming(landingPadInst, unwindDest);

        // give each invokeInst a unique landingPad
        for (int i = 1; i < unwindPredecessors.size(); i++) {
            auto* newTarget = llvm::BasicBlock::Create(unwindDest->getContext(),
                                                       unwindDest->getName() + "_copy", unwindDest->getParent());

            // replace the original usage to the bb
            llvm::Instruction& lastInst = unwindPredecessors[i]->back();
            auto* currentInvoke = llvm::dyn_cast<llvm::InvokeInst>(&lastInst);
            currentInvoke->setUnwindDest(newTarget);

            // create the landing pad
            auto* landingPadDuplicate = landingPadInst->clone();
            newTarget->getInstList().push_back(landingPadDuplicate);

            // update the phi
            phi->addIncoming(landingPadDuplicate, newTarget);

            // br to the merge
            llvm::IRBuilder<> builder(newTarget->getContext());
            builder.SetInsertPoint(newTarget);
            builder.CreateBr(mergeBlock);
        }

        // remove all usages of the original launchPad
        landingPadInst->replaceAllUsesWith(phi);

        // note actually you are replaceing the phi itself here
        // we need to fix here
        phi->setIncomingValue(0, landingPadInst);

        // Note that phi must happen before landpad, which is to say that there is no phi in merge
        // but there is phi in unwindDest
        // we need to move them to the merge
        std::set<llvm::PHINode*> phi2Remove;

        for (llvm::Instruction& instruction: *unwindDest) {
            auto* mergePhi = llvm::dyn_cast<llvm::PHINode>(&instruction);
            if (mergePhi == nullptr) {
                continue;
            }

            for (int i = 0; i < mergePhi->getNumIncomingValues(); i++) {
                auto* incomingBB = mergePhi->getIncomingBlock(i); // BB that does the invoke
                auto* newBB = llvm::dyn_cast<llvm::InvokeInst>(&incomingBB->back())->getUnwindDest();
                mergePhi->setIncomingBlock(i, newBB);
            }

            // move the phi to the merge block
            phi2Remove.insert(mergePhi);
            auto* newPhi = mergePhi->clone();
            mergeBlock->getInstList().push_front(newPhi);
            mergePhi->replaceAllUsesWith(newPhi);
        }

        for (auto* node: phi2Remove) {
            node->removeFromParent();
        }

        llvm::outs() << "One target replaced.\n";

    }

}