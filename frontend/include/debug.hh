#ifndef KANALYZER_DEBUG_HH
#define KANALYZER_DEBUG_HH
#include <cstdio>
#include <llvm/IR/Instruction.h>
#include <llvm/IR/IRBuilder.h>
#include "Config.h"
#include "llvm/Pass.h"


static void InsertSaveTrackLogic(llvm::Instruction* InsertBefore, uint64_t funcID, const string& caller, const string& callee) {
#ifndef DEBUG
    return;
#else
    auto* M = InsertBefore->getModule();
    llvm::IRBuilder<> Builder (InsertBefore);
    auto* Int64SSType = llvm::PointerType::getUnqual(
            llvm::Type::getInt64PtrTy(InsertBefore->getContext()));

    // get the function
    auto* functionType = llvm::FunctionType::get(
            llvm::Type::getVoidTy(InsertBefore->getContext()), {
                llvm::Type::getInt64Ty(InsertBefore->getContext()),
                llvm::Type::getInt64PtrTy(InsertBefore->getContext()),
                Int64SSType,
                llvm::Type::getInt8PtrTy(InsertBefore->getContext(), 0),
                llvm::Type::getInt8PtrTy(InsertBefore->getContext(), 0)
                },
            false);
    auto saveFunction = M->getOrInsertFunction(CSSDebugSaveFunctionName, functionType);

    // get the variables
    auto CSTrackVariable =
            M->getOrInsertGlobal(CSTrackVariableName, llvm::Type::getInt64Ty(M->getContext()));
    auto PositionInt = llvm::ConstantInt::get(llvm::Type::getInt64Ty(M->getContext()), llvm::APInt(64, funcID));
    auto DebugArray = M->getOrInsertGlobal(CSSDebugArrayName, llvm::Type::getInt64PtrTy(M->getContext()));
    auto CallerString = Builder.CreateGlobalStringPtr(caller);
    auto CalleeString = Builder.CreateGlobalStringPtr(callee);

    // make the call
    Builder.CreateCall(saveFunction, {PositionInt, CSTrackVariable, DebugArray, CallerString, CalleeString});
#endif
}

static void InsertCheckTrackLogic(llvm::Instruction* InsertBefore, uint64_t funcID, const string& caller, const string& callee) {
#ifndef DEBUG
    return;
#else
    auto* M = InsertBefore->getModule();
    llvm::IRBuilder<> Builder (InsertBefore);
    auto* Int64SSType = llvm::PointerType::getUnqual(
            llvm::Type::getInt64PtrTy(InsertBefore->getContext()));

    // get the function
    auto* functionType = llvm::FunctionType::get(
            llvm::Type::getVoidTy(InsertBefore->getContext()), {
                    llvm::Type::getInt64Ty(InsertBefore->getContext()),
                    llvm::Type::getInt64PtrTy(InsertBefore->getContext()),
                    Int64SSType,
                    llvm::Type::getInt8PtrTy(InsertBefore->getContext(), 0),
                    llvm::Type::getInt8PtrTy(InsertBefore->getContext(), 0)
            },
            false);
    auto saveFunction = M->getOrInsertFunction(CSSDebugCheckFunctionName, functionType);

    // get the variables
    auto CSTrackVariable =
            M->getOrInsertGlobal(CSTrackVariableName, llvm::Type::getInt64Ty(M->getContext()));
    auto PositionInt = llvm::ConstantInt::get(llvm::Type::getInt64Ty(M->getContext()), llvm::APInt(64, funcID));
    auto DebugArray = M->getOrInsertGlobal(CSSDebugArrayName, llvm::Type::getInt64PtrTy(M->getContext()));
    auto CallerString = Builder.CreateGlobalStringPtr(caller);
    auto CalleeString = Builder.CreateGlobalStringPtr(callee);

    // make the call
    Builder.CreateCall(saveFunction, {PositionInt, CSTrackVariable, DebugArray, CallerString, CalleeString});
#endif
}

static void InsertPrintTrackLogic(llvm::Instruction* InsertBefore) {
#ifndef DEBUG
    return;
#else

#endif
}

#endif