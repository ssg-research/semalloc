#ifndef _MULTI_LAYER_TYPE_ANALYSIS_H
#define _MULTI_LAYER_TYPE_ANALYSIS_H

#include "Analyzer.h"
#include "Config.h"
#include "llvm/IR/Operator.h"

typedef pair<llvm::Type *, int> typeidx_t;
pair<llvm::Type *, int> typeidx_c(llvm::Type *Ty, int Idx);
typedef pair<size_t, int> hashidx_t;
pair<size_t, int> hashidx_c(size_t Hash, int Idx);

class MLTA {

protected:

    //
    // Variables
    //

    GlobalContext *Ctx;


    ////////////////////////////////////////////////////////////////
    // Important data structures for type confinement, propagation,
    // and escapes.
    ////////////////////////////////////////////////////////////////
    llvm::DenseMap<size_t, map<int, FuncSet>>typeIdxFuncsMap;
    map<size_t, map<int, set<hashidx_t>>>typeIdxPropMap;
    set<size_t>typeEscapeSet;
    // Cap type: We cannot know where the type can be futher
    // propagated to. Do not include idx in the hash
    set<size_t>typeCapSet;


    ////////////////////////////////////////////////////////////////
    // Other data structures
    ////////////////////////////////////////////////////////////////
    // Cache matched functions for CallInst
    llvm::DenseMap<size_t, FuncSet>MatchedFuncsMap;
    llvm::DenseMap<llvm::Value *, FuncSet>VTableFuncsMap;

    set<size_t>srcLnHashSet;
set<size_t>addrTakenFuncHashSet;

    map<size_t, set<size_t>>calleesSrcMap;
    map<size_t, set<size_t>>L1CalleesSrcMap;

    // Matched icall types -- to avoid repeatation
    llvm::DenseMap<size_t, FuncSet> MatchedICallTypeMap;

    // Set of target types
    set<size_t>TTySet;

    // Functions that are actually stored to variables
    FuncSet StoredFuncs;
    // Special functions like syscalls
    FuncSet OutScopeFuncs;

    // Alias struct pointer of a general pointer
    map<llvm::Function *, map<llvm::Value *, llvm::Value *>>AliasStructPtrMap;



    //
    // Methods
    //

    ////////////////////////////////////////////////////////////////
    // Type-related basic functions
    ////////////////////////////////////////////////////////////////
    bool fuzzyTypeMatch(llvm::Type *Ty1, llvm::Type *Ty2, llvm::Module *M1, llvm::Module *M2);

    void escapeType(llvm::Value *V);
    void propagateType(llvm::Value *ToV, llvm::Type *FromTy, int Idx = -1);

    llvm::Type *getBaseType(llvm::Value *V, set<llvm::Value *> &Visited);
    llvm::Type *_getPhiBaseType(llvm::PHINode *PN, set<llvm::Value *> &Visited);
    llvm::Function *getBaseFunction(llvm::Value *V);
    bool nextLayerBaseType(llvm::Value *V, std::list<typeidx_t> &TyList,
                           llvm::Value * &NextV, set<llvm::Value *> &Visited);
    bool nextLayerBaseTypeWL(llvm::Value *V, std::list<typeidx_t> &TyList,
                             llvm::Value * &NextV);
    bool getGEPLayerTypes(llvm::GEPOperator *GEP, std::list<typeidx_t> &TyList);
    bool getBaseTypeChain(std::list<typeidx_t> &Chain, llvm::Value *V,
            bool &Complete);
    bool getDependentTypes(llvm::Type *Ty, int Idx, set<hashidx_t> &PropSet);


    ////////////////////////////////////////////////////////////////
    // Target-related basic functions
    ////////////////////////////////////////////////////////////////
    void confineTargetFunction(llvm::Value *V, llvm::Function *F);
    void intersectFuncSets(FuncSet &FS1, FuncSet &FS2,
            FuncSet &FS);
    bool typeConfineInInitializer(llvm::GlobalVariable *GV);
    bool typeConfineInFunction(llvm::Function *F);
    bool typePropInFunction(llvm::Function *F);
    void collectAliasStructPtr(llvm::Function *F);

    // deprecated
    //bool typeConfineInStore(StoreInst *SI);
    //bool typePropWithCast(User *Cast);
    llvm::Value *getVTable(llvm::Value *V);


    ////////////////////////////////////////////////////////////////
    // API functions
    ////////////////////////////////////////////////////////////////
    // Use type-based analysis to find targets of indirect calls
    void findCalleesWithType(llvm::CallInst*, FuncSet&);
    bool findCalleesWithMLTA(llvm::CallInst *CI, FuncSet &FS);
    bool getTargetsWithLayerType(size_t TyHash, int Idx,
            FuncSet &FS);


    ////////////////////////////////////////////////////////////////
    // Util functions
    ////////////////////////////////////////////////////////////////
    bool isCompositeType(llvm::Type *Ty);
    llvm::Type *getFuncPtrType(llvm::Value *V);
    llvm::Value *recoverBaseType(llvm::Value *V);
    void unrollLoops(llvm::Function *F);
    void saveCalleesInfo(llvm::CallInst *CI, FuncSet &FS, bool mlta);
    void printTargets(FuncSet &FS, llvm::CallInst *CI = NULL);
    void printTypeChain(std::list<typeidx_t> &Chain);


public:

    // General pointer types like char * and void *
    map<llvm::Module *, llvm::Type *>Int8PtrTy;
    // long interger type
    map<llvm::Module *, llvm::Type *>IntPtrTy;
    map<llvm::Module *, const llvm::DataLayout *>DLMap;

    MLTA(GlobalContext *Ctx_) {
        Ctx = Ctx_;
    }

};

#endif
