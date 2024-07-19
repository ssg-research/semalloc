#ifndef _COMMON_H_
#define _COMMON_H_

#include <llvm/IR/Module.h>
#include <llvm/Analysis/TargetLibraryInfo.h>
#include <llvm/ADT/Triple.h>
#include <llvm/Support/raw_ostream.h>
#include <llvm/Support/CommandLine.h>
#include <llvm/IR/DebugInfo.h>

#include <unistd.h>
#include <bitset>
#include <chrono>


#define Z3_ENABLED 0

#if Z3_ENABLED
#include <z3.h>
#endif

using std::string;
using std::set;
using std::pair;
using std::to_string;
using std::vector;

#define LOG(lv, stmt)                            \
    do {                                            \
        if (VerboseLevel >= lv)                        \
        errs() << stmt;                            \
    } while(0)


#define OP llvm::errs()

#ifdef DEBUG_MLTA
#define DBG OP
#else
#define DBG if (false) OP
#endif

#define debug_print(fmt, ...) \
            do { if (DEBUG) fprintf(stderr, fmt, __VA_ARGS__); } while (0)

#define WARN(stmt) LOG(1, "\n[WARN] " << stmt);

#define ERR(stmt)                                                    \
    do {                                                                \
        errs() << "ERROR (" << __FUNCTION__ << "@" << __LINE__ << ")";    \
        errs() << ": " << stmt;                                            \
        exit(-1);                                                        \
    } while(0)

/// Different colors for output
#define KNRM  "\x1B[0m"   /* Normal */
#define KRED  "\x1B[31m"  /* Red */
#define KGRN  "\x1B[32m"  /* Green */
#define KYEL  "\x1B[33m"  /* Yellow */
#define KBLU  "\x1B[34m"  /* Blue */
#define KMAG  "\x1B[35m"  /* Magenta */
#define KCYN  "\x1B[36m"  /* Cyan */
#define KWHT  "\x1B[37m"  /* White */


    extern llvm::cl::opt<unsigned> VerboseLevel;

//
// Common functions
//

    string getFileName(llvm::DILocation *Loc,
                       llvm::DISubprogram *SP = NULL);

    bool isConstant(llvm::Value *V);

    string getSourceLine(string fn_str, unsigned lineno);

    string getSourceFuncName(llvm::Instruction *I);

    llvm::StringRef getCalledFuncName(llvm::CallInst *CI);

    string extractMacro(string, llvm::Instruction *I);

    llvm::DILocation *getSourceLocation(llvm::Instruction *I);

    void printSourceCodeInfo(llvm::Value *V, string Tag = "VALUE");

    void printSourceCodeInfo(llvm::Function *F, string Tag = "FUNC");

    string getMacroInfo(llvm::Value *V);

    void getSourceCodeInfo(llvm::Value *V, string &file,
                           unsigned &line);

    int8_t getArgNoInCall(llvm::CallInst *CI, llvm::Value *Arg);

    llvm::Argument *getParamByArgNo(llvm::Function *F, int8_t ArgNo);

    size_t funcHash(llvm::Function *F, bool withName = false);

    size_t callHash(llvm::CallInst *CI);

    void structTypeHash(llvm::StructType *STy, set <size_t> &HSet);

    size_t typeHash(llvm::Type *Ty);

    size_t typeIdxHash(llvm::Type *Ty, int Idx = -1);

    size_t hashIdxHash(size_t Hs, int Idx = -1);

    size_t strIntHash(string str, int i);

    string structTyStr(llvm::StructType *STy);

    bool trimPathSlash(string &path, int slash);

    int64_t getGEPOffset(const llvm::Value *V, const llvm::DataLayout *DL);

    void LoadElementsStructNameMap(
            vector <pair<llvm::Module *, llvm::StringRef>> &Modules);

//
// Common data structures
//
class ModuleOracle {
public:
    ModuleOracle(llvm::Module &m) :
            dl(m.getDataLayout()),
            tli(llvm::TargetLibraryInfoImpl(llvm::Triple(m.getTargetTriple()))) {}

    ~ModuleOracle() {}

    // Getter
    const llvm::DataLayout &getDataLayout() {
        return dl;
    }

    llvm::TargetLibraryInfo &getTargetLibraryInfo() {
        return tli;
    }

    // Data layout
    uint64_t getBits() {
        return Bits;
    }

    uint64_t getPointerWidth() {
        return dl.getPointerSizeInBits();
    }

    uint64_t getPointerSize() {
        return dl.getPointerSize();
    }

    uint64_t getTypeSize(llvm::Type *ty) {
        return dl.getTypeAllocSize(ty);
    }

    uint64_t getTypeWidth(llvm::Type *ty) {
        return dl.getTypeSizeInBits(ty);
    }

    uint64_t getTypeOffset(llvm::Type *type, unsigned idx) {
        assert(llvm::isa<llvm::StructType>(type));
        return dl.getStructLayout(llvm::cast<llvm::StructType>(type))
                ->getElementOffset(idx);
    }

    bool isReintPointerType(llvm::Type *ty) {
        return (ty->isPointerTy() ||
                (ty->isIntegerTy() &&
                 ty->getIntegerBitWidth() == getPointerWidth()));
    }

protected:
    // Info provide
    const llvm::DataLayout &dl;
    llvm::TargetLibraryInfo tli;

    // Consts
    const uint64_t Bits = 8;
};

class Helper {
public:
    // LLVM value
    static string getValueName(llvm::Value *v) {
        if (!v->hasName()) {
            return to_string(reinterpret_cast<uintptr_t>(v));
        } else {
            return v->getName().str();
        }
    }

    static string getValueType(llvm::Value *v) {
        if (llvm::Instruction *inst = llvm::dyn_cast<llvm::Instruction>(v)) {
            return string(inst->getOpcodeName());
        } else {
            return string("value " + to_string(v->getValueID()));
        }
    }

    static string getValueRepr(llvm::Value *v) {
        string str;
        llvm::raw_string_ostream stm(str);

        v->print(stm);
        stm.flush();

        return str;
    }

#if Z3_ENABLED
    // Z3 expr
    static string getExprType(Z3_context ctxt, Z3_ast ast) {
      return string(Z3_sort_to_string(ctxt, Z3_get_sort(ctxt, ast)));
    }

    static string getExprRepr(Z3_context ctxt, Z3_ast ast) {
      return string(Z3_ast_to_string(ctxt, ast));
    }
#endif

    // String conversion
    static void convertDotInName(string &name) {
        replace(name.begin(), name.end(), '.', '_');
    }
};

class Dumper {
public:
    Dumper() {}

    ~Dumper() {}

    // LLVM value
    void valueName(llvm::Value *val) {
        llvm::errs() << Helper::getValueName(val) << "\n";
    }

    void typedValue(llvm::Value *val) {
        llvm::errs() << "[" << Helper::getValueType(val) << "]"
               << Helper::getValueRepr(val)
               << "\n";
    }

#if Z3_ENABLED
    // Z3 expr
    void typedExpr(Z3_context ctxt, Z3_ast ast) {
      errs() << "[" << Helper::getExprType(ctxt, ast) << "]"
             << Helper::getExprRepr(ctxt, ast)
             << "\n";
    }
#endif

};

extern Dumper DUMP;

#endif
