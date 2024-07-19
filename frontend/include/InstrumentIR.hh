//
// Created by r53wang on 16/03/23.
//

#ifndef KANALYZER_INSTRUMENTIR_HH
#define KANALYZER_INSTRUMENTIR_HH

#include "CallPath.hh"
#include "Config.h"
#include "debug.hh"
#include "RecursiveHelper.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/Dominators.h"
#include "llvm/Pass.h"
#include "CXXGraph/CXXGraph.hpp"
#include <queue>
#include <memory>
#include <fstream>
#include <iostream>

using std::set;
using std::string;

class InstrumentIRPass{

private:
    llvm::Module* M;

    /*
     * Callee -> Caller
     */
    map<string, vector<CallPath*>*>* FunctionMap;

    /*
     * Caller -> Callee
     */
    map<string, vector<CallPath*>*>* FlippedFunctionMap;

    set<CallPath*> CallPathMarkSet;

    /*
     * Set of all possible usable functions
     */
    set<string> FunctionMarkSet;

    /**
     * Set of all functions that are loops and relevant HMF
     */
    set<string> RelevantLoopFunctionSet;

    /**
     * Set of all functions that relevant to both loop and HMF
     */
    set<string> RelevantAllFunctionSet;

    vector<vector<string>> FunctionCycles;

    /**
     * IntraName -> Functions
     */
    map<string, set<string>*> IntraFunctionMap;

    /**
     * FunctionName -> IntroName
     */
    map<string, string> FlippedIntraFunctionMap;

    /**
     * FunctionName -> Comprehensive Outbound
     */
    map<string, uint32_t> ComprehensiveOutboundMap;

    /**
     * All children
     */
    map<string, vector<CallPath*>*> FinalCalleeMap;

    /**
     * All parents
     */
    map<string, vector<CallPath*>*> FinalCallerMap;

    std::queue<string> TopologicalOrder;

#ifdef DEBUG
    std::map<string, uint64_t> FunctionIDMap;
#endif

    // Caller -> Callee
    void FlipFunctionMap();

    void UpdateHMFInterface();

    // Find all functions that calls HMF
    void MarkOnlyRelevantFunctions();

    // Find all functions in loop
    void instrIsInaLoop();

    // Find all functions that are relevant to the loop and calls HMF
    void MarkLoopRelevantFunctions();

    // Construct the loop function only CFG
    void ConstructFinalCFG();

    // Compute the weight of each edge
    void ComputeEdgeWeight();

#ifdef DEBUG
    void AssignFunctionID();
#endif


public:
    InstrumentIRPass(llvm::Module* _M, map<string, vector<CallPath*>*>* _Function_Map){
        M = _M;
        FunctionMap = _Function_Map;
        FlippedFunctionMap = new map<string, vector<CallPath*>*>;
    }

    bool doInitialization();
    bool doModulePass();
    bool run();

    void PrintFinalMap();
};


#endif //KANALYZER_INSTRUMENTIR_HH
