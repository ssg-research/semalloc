//
// Created by r53wang on 10/15/23.
//

#ifndef KANALYZER_RECURSIVEHELPER_H
#define KANALYZER_RECURSIVEHELPER_H

#include "llvm/IR/IRBuilder.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/Dominators.h"
#include "llvm/Pass.h"
#include "Config.h"

/**
 * Load ROTrackVariable
 * Load RStackInsertPoint
 * Call Intrinsic
 * Store FramePointer
 * ROTrackVariable += 1
 * Store ROTrackVariable
 * Call Inst
 * Load ROTrackVariable
 * ROTrackVariable -= 1
 * Store ROTrackVariable
 */
void extendInLoopRecursiveCall(llvm::Instruction* Inst);

/**
 * Load ROTV
 * Load RStack
 * Load RHash
 * Call Hash function
 * Store the return value to RHash
 * Call OBound function
 */
void extendOutBoundRecursiveCall(llvm::Instruction* Inst);

/**
 * Call IBound function
 * Load RHash
 * Store 0 to RHash
 */
void extendInBoundRecursiveCall(llvm::Instruction* Inst);

void insertIncreaseLoopLayerLogic(llvm::Instruction* insertBefore);

void insertDecreaseLoopLayerLogic(llvm::Instruction* insertBefore);
#endif //KANALYZER_RECURSIVEHELPER_H
