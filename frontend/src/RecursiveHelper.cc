//
// Created by r53wang on 10/16/23.
//
#include "RecursiveHelper.h"


void extendInLoopRecursiveCall(llvm::Instruction* Inst) {
    auto* M = Inst->getModule();

    auto ROTrackVariable =
            M->getOrInsertGlobal(CSSRecursiveOffsetTrackName, llvm::Type::getInt64Ty(M->getContext()));
    auto RStack =
            M->getOrInsertGlobal(CSSRecursiveStackName, llvm::Type::getInt64PtrTy(M->getContext()));

    auto* IntrinsicFunc = llvm::Intrinsic::getDeclaration(M, llvm::Intrinsic::frameaddress, llvm::Type::getInt32Ty(M->getContext()));
    llvm::IRBuilder<> Builder (Inst);

    auto* mType = llvm::Type::getInt64Ty(Inst->getContext());
    auto* callInst = Builder.CreateCall(IntrinsicFunc, llvm::ConstantInt::get(mType, llvm::APInt(32, 0)));
    auto* convertInst = Builder.CreateIntCast(callInst, llvm::Type::getInt64Ty(M->getContext()), false);

    // load the ROTrackVariable
    auto* loadROTVInst = new llvm::LoadInst(ROTrackVariable->getType()->getPointerElementType(), ROTrackVariable, "", Inst);

    // load the insert point
    auto* RStackInsertPoint = Builder.CreateGEP(RStack->getType()->getPointerElementType(), RStack, loadROTVInst);
    auto* convertInst2 = Builder.CreateIntCast(RStackInsertPoint, llvm::Type::getInt64PtrTy(M->getContext()), false);

    // store frame pointer
    new llvm::StoreInst(convertInst, convertInst2, Inst);

    // increase ROTV
    llvm::Instruction* PlusInst = llvm::BinaryOperator::CreateAdd(
            loadROTVInst, llvm::ConstantInt::get(
                    ROTrackVariable->getType(), llvm::APInt(64, 1)));
    PlusInst->insertBefore(Inst);

    // store ROTV
    new llvm::StoreInst(PlusInst, ROTrackVariable, Inst);

    // CALL THE FUNCTION
    // after returns

    if (llvm::dyn_cast<llvm::CallInst>(Inst) != nullptr) {
        // get ROTV
        auto* loadROTVInst2 = new llvm::LoadInst(ROTrackVariable->getType()->getPointerElementType(), ROTrackVariable, "", Inst->getNextNode());

        // decrease ROTV
        llvm::Instruction* MinusInst = llvm::BinaryOperator::CreateSub(
                loadROTVInst2, llvm::ConstantInt::get(
                        ROTrackVariable->getType(), llvm::APInt(64, 1)));
        MinusInst->insertAfter(loadROTVInst2);

        // store ROTV
        new llvm::StoreInst(MinusInst, ROTrackVariable, MinusInst->getNextNode());
    } else {
        auto* invokeInst = llvm::dyn_cast<llvm::InvokeInst>(Inst);
        auto* target1 = invokeInst->getNormalDest();
        auto* target2 = invokeInst->getUnwindDest();

        // target 1

        // note that we should probably create a new BB as other bb might also jump to this target
        // TODO: currently always create new BB
        llvm::IRBuilder<> builder(target1->getContext());
        llvm::BasicBlock* newTarget1 = llvm::BasicBlock::Create(target1->getContext(), "invokeBB", target1->getParent());

        // replace the branch target to newTarget1
        invokeInst->setNormalDest(newTarget1);

        // get ROTV
        auto* loadROTVInst2 = builder.CreateLoad(ROTrackVariable->getType()->getPointerElementType(),
                                           ROTrackVariable, "");

        // decrease ROTV
        auto* MinusInst1 = builder.CreateSub(loadROTVInst2, llvm::ConstantInt::get(
                        ROTrackVariable->getType(), llvm::APInt(64, 1)));

        // store ROTV
        builder.CreateStore(MinusInst1, ROTrackVariable);

        // the new target should go back to the regular control flow
        builder.CreateBr(target1);

        // we need to handle the phi that in the original target1: all comes from invoke should now come from newtarget1
        for (auto& inst: *target1) {
            auto* targetPhi = llvm::dyn_cast<llvm::PHINode>(&inst);
            if (targetPhi == nullptr) {
                break; // phi must happen before others
            }

            for (int i = 0; i < targetPhi->getNumIncomingValues(); i++) {
                if (targetPhi->getIncomingBlock(i) == invokeInst->getParent()) {
                    targetPhi->setIncomingBlock(i, newTarget1);
                }
            }
        }

        // target 2
        // get ROTV
        loadROTVInst2 = new llvm::LoadInst(ROTrackVariable->getType()->getPointerElementType(),
                                     ROTrackVariable, "", target2->getFirstNonPHI()->getNextNode());

        // decrease ROTV
        auto* MinusInst = llvm::BinaryOperator::CreateSub(
                loadROTVInst2, llvm::ConstantInt::get(
                        ROTrackVariable->getType(), llvm::APInt(64, 1)));
        MinusInst->insertAfter(loadROTVInst2);

        // store ROTV
        new llvm::StoreInst(MinusInst, ROTrackVariable, MinusInst->getNextNode());
    }
}

/**
 * Load ROTV
 * Load RStack
 * Load RHashhashF
 * Call Hash function
 * Store the return value to RHash
 * Call OBound function
 */
void extendOutBoundRecursiveCall(llvm::Instruction* Inst) {
    auto* M = Inst->getModule();

    // get the function
    auto* functionType = llvm::FunctionType::get(
            llvm::Type::getInt64Ty(M->getContext()),
            {llvm::Type::getInt64PtrTy(M->getContext()), llvm::Type::getInt64Ty(M->getContext())},
            false);
    auto hashFunction = M->getOrInsertFunction(CSSHashFunctionName, functionType);

    // global variables
    auto RHVariable =
            M->getOrInsertGlobal(CSSRecursiveHashName, llvm::Type::getInt64Ty(M->getContext()));
    auto ROTrackVariable =
            M->getOrInsertGlobal(CSSRecursiveOffsetTrackName, llvm::Type::getInt64Ty(M->getContext()));
    auto RStack =
            M->getOrInsertGlobal(CSSRecursiveStackName, llvm::Type::getInt64PtrTy(M->getContext()));

    // load the ROTrackVariable
    auto* loadROTVInst = new llvm::LoadInst(ROTrackVariable->getType()->getPointerElementType(), ROTrackVariable, "loadROTV", Inst);

    // load the insert point
    auto* loadRStackInst = new llvm::LoadInst(RStack->getType()->getPointerElementType(), RStack, "loadRS", Inst);

    // call the hash function
    llvm::IRBuilder<> Builder (Inst);
    auto* callInst = Builder.CreateCall(hashFunction, {loadRStackInst, loadROTVInst});
    auto* convertInst = Builder.CreateIntCast(callInst, llvm::Type::getInt64Ty(M->getContext()), false);

    // store the return value
    new llvm::StoreInst(convertInst, RHVariable, Inst);

    // the loop logic
    insertIncreaseLoopLayerLogic(Inst);
    if (llvm::dyn_cast<llvm::CallInst>(Inst) != nullptr) {
        insertDecreaseLoopLayerLogic(Inst->getNextNode());
    } else {
        auto* invokeInst = llvm::dyn_cast<llvm::InvokeInst>(Inst);
        // first node in unwind must be land pad
        insertDecreaseLoopLayerLogic(invokeInst->getUnwindDest()->getFirstNonPHI()->getNextNode());
        insertDecreaseLoopLayerLogic(invokeInst->getNormalDest()->getFirstNonPHI());
    }
}

/**
 * Call IBound function
 * Load RHash
 * Store 0 to RHash
 */
void extendInBoundRecursiveCall(llvm::Instruction* Inst) {
    auto* M = Inst->getModule();
    auto RHVariable =
            M->getOrInsertGlobal(CSSRecursiveHashName, llvm::Type::getInt64Ty(M->getContext()));

    // store the hash
    if (llvm::dyn_cast<llvm::CallInst>(Inst) != nullptr) {
        new llvm::StoreInst(llvm::ConstantInt::get(llvm::Type::getInt64Ty(Inst->getContext()), llvm::APInt(64, 0)), RHVariable, Inst->getNextNode());
    } else {
        auto* invokeInst = llvm::dyn_cast<llvm::InvokeInst>(Inst);
        auto* target1 = invokeInst->getNormalDest();
        auto* target2 = invokeInst->getUnwindDest();

        new llvm::StoreInst(llvm::ConstantInt::get(llvm::Type::getInt64Ty(Inst->getContext()), llvm::APInt(64, 0)),
                      RHVariable, target1->getFirstNonPHI());
        new llvm::StoreInst(llvm::ConstantInt::get(llvm::Type::getInt64Ty(Inst->getContext()), llvm::APInt(64, 0)),
                      RHVariable, target2->getFirstNonPHI()->getNextNode());
    }
}


void insertIncreaseLoopLayerLogic(llvm::Instruction* insertBefore) {
    auto* M = insertBefore->getModule();
    auto* CSSLoopLayerTrack =
            M->getOrInsertGlobal(CSSLoopLayerTrackName, llvm::Type::getInt64Ty(M->getContext()));

    auto* LoadLoopLayer = new llvm::LoadInst(CSSLoopLayerTrack->getType()->getPointerElementType(), CSSLoopLayerTrack, "", insertBefore);
    llvm::Instruction* PlusLoopLayerInst = llvm::BinaryOperator::CreateAdd(
            LoadLoopLayer, llvm::ConstantInt::get(CSSLoopLayerTrack->getType(), llvm::APInt(64, 1)));
    PlusLoopLayerInst->insertAfter(LoadLoopLayer);
    new llvm::StoreInst(PlusLoopLayerInst, CSSLoopLayerTrack, insertBefore);
}

void insertDecreaseLoopLayerLogic(llvm::Instruction* insertBefore) {
    auto* M = insertBefore->getModule();
    auto* CSSLoopLayerTrack =
            M->getOrInsertGlobal(CSSLoopLayerTrackName, llvm::Type::getInt64Ty(M->getContext()));

    auto* LoadLoopLayer = new llvm::LoadInst(CSSLoopLayerTrack->getType()->getPointerElementType(), CSSLoopLayerTrack, "", insertBefore);
    llvm::Instruction* SubLoopLayerInst = llvm::BinaryOperator::CreateSub(
            LoadLoopLayer, llvm::ConstantInt::get(CSSLoopLayerTrack->getType(), llvm::APInt(64, 1)));
    SubLoopLayerInst->insertAfter(LoadLoopLayer);
    new llvm::StoreInst(SubLoopLayerInst, CSSLoopLayerTrack, SubLoopLayerInst->getNextNode());
}
