//
// Created by r53wang on 16/03/23.
//

#include "InstrumentIR.hh"
#include "llvm/IR/IRBuilder.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/Dominators.h"


void InstrumentIRPass::MarkOnlyRelevantFunctions() {
    /**
     * This functions runs a DFS, and
     * only mark functions relevant to HMF
     */

    std::set<string> GlobalVisited;
    std::set<string> finalFunctionMarkSet = this->FunctionMarkSet;

    for (auto const& MapEntry: this->FunctionMarkSet) { // function that calls HMF
        auto CallPathVector = this->FlippedFunctionMap->find(MapEntry)->second; // get the path

        // for each instance
        for (auto CallPath: *CallPathVector) {
            if (!CallPath->callsHMF) { // not HMF
                continue;
            }

            // add the corresponding HMF into the set
            if (finalFunctionMarkSet.find(CallPath->Callee) == finalFunctionMarkSet.end()) {
                finalFunctionMarkSet.insert(CallPath->Callee);
            }

            // this function is already visited
            if (GlobalVisited.find(MapEntry) != GlobalVisited.end()) {
                break;
            }

            // the following logic only need to run once -- until the end of the loop
            std::queue<string> CandidateQueue;
            llvm::outs() << "Function [" << MapEntry << "] calls HMF." << "" << "\n";

            // mark the caller of the HFI as relevant
            auto CurrentHFIPathVector = this->FunctionMap->find(MapEntry)->second;

            // update the current interfaces
            for (auto CurrentCallPath: *CurrentHFIPathVector) {
                llvm::outs() << "From " << CurrentCallPath->Caller << " to " << CurrentCallPath->Callee << "\n";
                CurrentCallPath->isRelevant = true;
            }

            // traverse all parent functions of current HFI
            for (auto CalledInstance: *(*this->FunctionMap)[MapEntry]) {
                string CallerFunctionName = CalledInstance->Caller;
                CandidateQueue.push(CallerFunctionName);
            }

            // traverse the whole tree
            while (!CandidateQueue.empty()) {
                auto CurrentFunction = CandidateQueue.front();
                CandidateQueue.pop();

                if (GlobalVisited.find(CurrentFunction) != GlobalVisited.end()) {
                    continue;
                }

                GlobalVisited.insert(CurrentFunction);

                // mark this function as well
                if (finalFunctionMarkSet.find(CurrentFunction) == finalFunctionMarkSet.end()) {
                    finalFunctionMarkSet.insert(CurrentFunction);
                }

                if (this->FunctionMap->find(CurrentFunction) != this->FunctionMap->end()) {
                    auto CurrentCallPathVector = this->FunctionMap->find(CurrentFunction)->second;

                    // update the current interfaces
                    for (auto CurrentCallPath: *CurrentCallPathVector) {
                        llvm::outs() << "From " << CurrentCallPath->Caller << " to " << CurrentCallPath->Callee << "\n";
                        CurrentCallPath->isRelevant = true;
                    }
                }

                // put all parents into the queue
                for (auto CalledInstance: *(*this->FunctionMap)[CurrentFunction]) {
                    string CallerFunctionName = CalledInstance->Caller;
                    if (GlobalVisited.find(CallerFunctionName) == GlobalVisited.end()) {
                        CandidateQueue.push(CallerFunctionName);
                    }
                }
            } // end parents of current HFI
        } // end for current HFI
    }

    // dump the all new entries to the global set
    for (const auto& CurrentFunction: finalFunctionMarkSet) {
        if (this->FunctionMarkSet.find(CurrentFunction) == this->FunctionMarkSet.end()) {
            this->FunctionMarkSet.insert(CurrentFunction);
        }
    }
}


void InstrumentIRPass::MarkLoopRelevantFunctions() {
    /**
     * This functions runs two DFS, and
     * mark functions that in the FunctionMarkSet
     * and also relevant to the loops.
     */

    std::set<string> GlobalVisited;
    auto finalMarkSet = this->RelevantLoopFunctionSet;

    for (auto const& MapEntry: this->RelevantLoopFunctionSet) {
        GlobalVisited.insert(MapEntry);
        std::queue<string> CandidateQueue;

        // ********************************************************************
        // traverse all parent functions of current loop function
        for (auto CalledInstance: *(*this->FunctionMap)[MapEntry]) {
            auto CallerFunctionName = CalledInstance->Caller;
            if (this->FunctionMarkSet.find(CallerFunctionName) != this->FunctionMarkSet.end()) {
                CandidateQueue.push(CallerFunctionName);
            }
        }

        // traverse the whole tree
        while (!CandidateQueue.empty()) {
            auto CurrentFunction = CandidateQueue.front();
            CandidateQueue.pop();

            if (GlobalVisited.find(CurrentFunction) != GlobalVisited.end()) {
                continue;
            }

            GlobalVisited.insert(CurrentFunction);

            // mark this function as well
            if (finalMarkSet.find(CurrentFunction) == finalMarkSet.end() &&
            this->FunctionMarkSet.find(CurrentFunction) != this->FunctionMarkSet.end()) {
                finalMarkSet.insert(CurrentFunction);
            }

            if (this->FunctionMap->find(CurrentFunction) != this->FunctionMap->end()) {
                auto CurrentCallPathVector = this->FunctionMap->find(CurrentFunction)->second;

                // update the current interfaces
                for (auto CurrentCallPath: *CurrentCallPathVector) {
                    CurrentCallPath->isRelevant = true;
                }
            }

            // put all parents into the queue
            for (auto CalledInstance: *(*this->FunctionMap)[CurrentFunction]) {
                string CallerFunctionName = CalledInstance->Caller;
                if (GlobalVisited.find(CallerFunctionName) == GlobalVisited.end()) {
                    CandidateQueue.push(CallerFunctionName);
                }
            }
        } // end parents of current HFI

        // ********************************************************************
        // traverse all children functions of current loop function
        if (this->FlippedFunctionMap->find(MapEntry) != this->FlippedFunctionMap->end()) {
            for (auto CalledInstance: *(*this->FlippedFunctionMap)[MapEntry]) {
                auto CalleeFunctionName = CalledInstance->Callee;
                if (this->FunctionMarkSet.find(CalleeFunctionName) != this->FunctionMarkSet.end()) {
                    CandidateQueue.push(CalleeFunctionName);
                }
            }
        }

        // traverse the whole tree
        while (!CandidateQueue.empty()) {
            auto CurrentFunction = CandidateQueue.front();
            CandidateQueue.pop();

            if (GlobalVisited.find(CurrentFunction) != GlobalVisited.end()) {
                continue;
            }

            GlobalVisited.insert(CurrentFunction);

            // mark this function as well
            if (finalMarkSet.find(CurrentFunction) == finalMarkSet.end() &&
                this->FunctionMarkSet.find(CurrentFunction) != this->FunctionMarkSet.end()) {
                finalMarkSet.insert(CurrentFunction);
            }

            if (this->FlippedFunctionMap->find(CurrentFunction) != this->FlippedFunctionMap->end()) {
                auto CurrentCallPathVector = this->FlippedFunctionMap->find(CurrentFunction)->second;

                // update the current interfaces
                for (auto CurrentCallPath: *CurrentCallPathVector) {
                    CurrentCallPath->isRelevant = true;
                }
            }

            // put all children into the queue
            if (this->FlippedFunctionMap->find(CurrentFunction) == this->FlippedFunctionMap->end()) {
                continue;
            }

            for (auto CalledInstance: *(*this->FlippedFunctionMap)[CurrentFunction]) {
                string CalleeFunctionName = CalledInstance->Callee;
                if (GlobalVisited.find(CalleeFunctionName) == GlobalVisited.end()) {
                    CandidateQueue.push(CalleeFunctionName);
                }
            }
        } // end children of current HFI
    }

    // dump the all new entries to the global set
    for (const auto& CurrentFunction: finalMarkSet) {
        this->RelevantAllFunctionSet.insert(CurrentFunction);
    }

    // intra loops
    auto insertSet = set<string>();
    auto removeSet = set<string>();
    for (const auto& CurrentFunction: this->RelevantAllFunctionSet) {
        if (this->FlippedIntraFunctionMap.find(CurrentFunction) != this->FlippedIntraFunctionMap.end()) {
            removeSet.insert(CurrentFunction);
            insertSet.insert(this->FlippedIntraFunctionMap[CurrentFunction]);
        }
    }

    for (const auto& entry: insertSet) {
        this->RelevantAllFunctionSet.insert(entry);
    }

    for (const auto& entry: removeSet) {
        this->RelevantAllFunctionSet.erase(entry);
    }
}


void InstrumentIRPass::instrIsInaLoop() {
    // logic of getting instruction level cycles
    llvm::DominatorTree DT = llvm::DominatorTree();
    auto loopInfo = new llvm::LoopInfoBase<llvm::BasicBlock, llvm::Loop>();

    // We only care about relevant functions
    for (auto const& MapEntry: this->FunctionMarkSet) {
        llvm::outs() << "COMPUTING " << MapEntry << "\n";
        for (auto CalledInstance : *(*this->FunctionMap)[MapEntry]) {
//            if (!CalledInstance->isRelevant) {
//                continue;
//            }
            DT.recalculate(*CalledInstance->call_inst->getFunction());
            loopInfo->releaseMemory();
            loopInfo->analyze(DT);

            // current instruction is in loop
            if (loopInfo->getLoopFor(CalledInstance->call_inst->getParent())) {
                CalledInstance->path_type = CallPath::PathType::MarkSimpleLoop;
                if (this->RelevantLoopFunctionSet.find(MapEntry) == this->RelevantLoopFunctionSet.end()) {
                    this->RelevantLoopFunctionSet.insert(MapEntry);
                }
                llvm::outs() << "\tLOOP: " << CalledInstance->Caller << "\n";
            } else {
                llvm::outs() << "\tNLOOP: " << CalledInstance->Caller << "\n";
            }
        }
    }

    llvm::outs() << "Running Kosaraju to find loops.\n";

    std::map<string, int> function2idMap;
    std::map<int, string> id2functionMap;
    std::map<int, CXXGraph::Node<int>> id2NodeGraph;
    int functionCount = 0;

    for (const auto& function: this->FunctionMarkSet) {
        function2idMap[function] = functionCount;
        id2functionMap[functionCount] = function;
        id2NodeGraph.emplace(functionCount, CXXGraph::Node<int>(std::to_string(functionCount), functionCount));
        functionCount++;
    }

    CXXGraph::T_EdgeSet<int> edgeSet;
    int edgeCount = 0;
    for (const auto& function: this->FunctionMarkSet) {
        if ((*this->FlippedFunctionMap).find(function) == (*this->FlippedFunctionMap).end()) {
            continue;
        }

        for (const auto& entry: *(*this->FlippedFunctionMap)[function]) {
            if ((this->FunctionMarkSet.find(entry->Caller) != this->FunctionMarkSet.end()) &&
                    (this->FunctionMarkSet.find(entry->Callee) != this->FunctionMarkSet.end())) {
                CXXGraph::DirectedEdge<int> edge(edgeCount,
                                                   id2NodeGraph.at(function2idMap[entry->Caller]),
                                                   id2NodeGraph.at(function2idMap[entry->Callee]));
                edgeSet.insert(std::make_shared<CXXGraph::DirectedEdge<int>>(edge));
            }
        }
    }

    CXXGraph::Graph<int> graph(edgeSet);
    llvm::outs() << "Number of nodes: " << graph.getNodeSet().size() << "\n";
    llvm::outs() << "Number of edges: " << graph.getEdgeSet().size() << "\n";

    CXXGraph::SCCResult<int> res = graph.kosaraju();
    auto nodes = graph.getNodeSet();
    auto cycleMap = std::map<int, std::vector<string>*>();
    llvm::outs() << "Number of components: " << res.noOfComponents << "\n";

    // we first count the number of nodes in each component
    for (const auto& node: nodes) {
        auto componentID = res.sccMap[(node->getId())];
        auto functionName = id2functionMap[stoi(node->getUserId())];

        if (cycleMap.find(componentID) == cycleMap.end()) {
            cycleMap.insert({componentID, new std::vector<string>});
        }

        cycleMap[componentID]->push_back(functionName);
    }

    // put the real intra loops into the vector
    for (auto entry: cycleMap) {
        if (entry.second->size() > 1) {
            this->FunctionCycles.push_back(*entry.second);
        }
    }

    // put all function nodes into the set
    for (const auto& Cycle: FunctionCycles) {
        string currentLoopIntraName;
        set<string>* currentLoopSet = nullptr;
        set<string> currentLoopRelevantLoopSet;

        // if the intra loop is relevant to HMF, all functions within it must be marked.
        if (this->FunctionMarkSet.find(Cycle.front()) == this->FunctionMarkSet.end()) {
            continue;
        }

        for (const auto& CycleNode: Cycle) {
            //  mark the function
            if (this->RelevantLoopFunctionSet.find(CycleNode) == this->RelevantLoopFunctionSet.end()) {
                this->RelevantLoopFunctionSet.insert(CycleNode);
            }
        } // end foreach node

        // we create the new set here
        currentLoopSet = new set<string>;
        currentLoopIntraName = "CSSINTRA_" + std::to_string(this->IntraFunctionMap.size());
        this->IntraFunctionMap[currentLoopIntraName] = currentLoopSet;

        // eventually put elements of the current set to the target set
        for (const auto& CycleNode: Cycle) { // update set for current loop
            if (currentLoopSet->find(CycleNode) == currentLoopSet->end()) {
                currentLoopSet->insert(CycleNode);
                this->FlippedIntraFunctionMap[CycleNode] = currentLoopIntraName;
            }
        }
    } // end for Cycles

    // mark all internal calls or outbound loops
    for (const auto& entry: this->FlippedIntraFunctionMap) {
        for (auto Instance: *this->FlippedFunctionMap->find(entry.first)->second) { // for all callees
            auto CalleeName = Instance->Callee;
            if (this->FlippedIntraFunctionMap.find(CalleeName) != this->FlippedIntraFunctionMap.end()) { // or name get replaced
                Instance->path_type = CallPath::PathType::MarkSimpleInner;
                Instance->Callee = this->FlippedIntraFunctionMap[Instance->Caller];
                Instance->Caller = this->FlippedIntraFunctionMap[Instance->Caller];
            } else { // call something out the intra loop
                Instance->path_type = CallPath::PathType::MarkOutbound;
                Instance->Caller = this->FlippedIntraFunctionMap[Instance->Caller];
            }
        }
    }

    // mark all inbound calls
    for (const auto& entry: this->FlippedIntraFunctionMap) {
        for (auto Instance: *this->FunctionMap->find(entry.first)->second) { // for all callers
            auto CallerName = Instance->Caller;

            // case 1, already polluted by the previous scenario
            if (CallerName == Instance->Callee) { // same intra loop
                // this function is called by more than two positions
                if (this->FunctionMap->find(entry.first)->second->size() > 1) {
                    Instance->path_type = CallPath::PathType::MarkInnerBranch;
                } else {
                    Instance->path_type = CallPath::PathType::MarkSimpleInner;
                }
                // case 2, not yet polluted
            } else if (this->FlippedIntraFunctionMap.find(CallerName) != this->FlippedIntraFunctionMap.end()) { // same intra loop
                // this function is called by more than two positions
                if (this->FunctionMap->find(entry.first)->second->size() > 1) {
                    Instance->path_type = CallPath::PathType::MarkInnerBranch;
                } else {
                    Instance->path_type = CallPath::PathType::MarkSimpleInner;
                }
                Instance->Callee = this->FlippedIntraFunctionMap[Instance->Callee];
                Instance->Caller = this->FlippedIntraFunctionMap[Instance->Callee];
            } else { // inbound function
                Instance->path_type = CallPath::PathType::MarkInbound;
                Instance->Callee = this->FlippedIntraFunctionMap[Instance->Callee];
            }
        }
    }

    // update the maps
    for (const auto& IntraLoop: this->IntraFunctionMap) {
        auto intraName = IntraLoop.first;
        this->FunctionMap->insert({intraName, new vector<CallPath*>()});
        this->FlippedFunctionMap->insert({intraName, new vector<CallPath*>()});

        this->RelevantLoopFunctionSet.insert(intraName);

        for (const auto& IntraElement: *IntraLoop.second) {
            for (auto* element: *(*this->FunctionMap)[IntraElement]) {
                (*this->FunctionMap)[intraName]->push_back(element);
            }
            for (auto* element: *(*this->FlippedFunctionMap)[IntraElement]) {
                (*this->FlippedFunctionMap)[intraName]->push_back(element);
            }

            // clear the old map
            (*this->FlippedFunctionMap)[IntraElement] = new vector<CallPath*>();
            (*this->FunctionMap)[IntraElement] = new vector<CallPath*>();

            if (this->RelevantLoopFunctionSet.find(IntraElement) != this->RelevantLoopFunctionSet.end()) {
                this->RelevantLoopFunctionSet.erase(IntraElement);
            }
        }
    }

    for (const auto& CycleEntry: this->IntraFunctionMap) {
        llvm::outs() << CycleEntry.first << "\n";
        for (const auto& key: *CycleEntry.second) {
            llvm::outs() << "\t" << key << "\n";
        }
    }
}


void InstrumentIRPass::UpdateHMFInterface() {
    llvm::outs() << "Working on updating HMF\n";
    // obtain the global variables
    auto CSTrackVariable =
            M->getOrInsertGlobal(CSTrackVariableName, llvm::Type::getInt64Ty(M->getContext()));
    auto CSSRecursiveHash =
            M->getOrInsertGlobal(CSSRecursiveHashName, llvm::Type::getInt64Ty(M->getContext()));
    auto* CSSLoopLayerTrack =
            M->getOrInsertGlobal(CSSLoopLayerTrackName, llvm::Type::getInt64Ty(M->getContext()));

    // for each function
    for (const auto& FunctionName: InitialHeapFunctions) {

        // function not called anywhere
        if (this->FunctionMap->find(FunctionName) == this->FunctionMap->end()) {
            continue;
        }

        // function marked
        for (auto CalledInstance: *(*this->FunctionMap)[FunctionName]) {
            uint16_t SizeParamIndex = HeapFunctionSizeParameterIndex.find(FunctionName)->second;
            llvm::Value* SizeParam = CalledInstance->call_inst->getOperand(SizeParamIndex);

            auto* BB = CalledInstance->call_inst->getParent();
            llvm::IRBuilder<> builder(BB->getContext());
            llvm::BasicBlock* thenBlock = llvm::BasicBlock::Create(BB->getContext(), "then", BB->getParent());
            llvm::BasicBlock* thenLoopBlock = llvm::BasicBlock::Create(BB->getContext(), "thenLoop", BB->getParent());
            llvm::BasicBlock* elseBlock = llvm::BasicBlock::Create(BB->getContext(), "else", BB->getParent());
            llvm::BasicBlock* mergeBlock = BB->splitBasicBlock(CalledInstance->call_inst, "merge");

            // condition branch
            auto* originalBR = &BB->back();
            originalBR->removeFromParent();

            builder.SetInsertPoint(BB);
            auto* condition = builder.CreateICmpUGT(SizeParam, llvm::ConstantInt::get(
                    llvm::Type::getInt64Ty(M->getContext()), llvm::APInt(64, MAX_SIZE)), "condition");
            builder.CreateCondBr(condition, elseBlock, thenBlock);

            // condition 1, size is smaller than 4096, we need to add everything together
            // load the ROTrackVariable
            builder.SetInsertPoint(thenBlock);
            auto* loadRH = builder.CreateLoad(CSSRecursiveHash->getType()->getPointerElementType(),CSSRecursiveHash, "loadRH");
            auto* loadCSTV = builder.CreateLoad(CSTrackVariable->getType()->getPointerElementType(),CSTrackVariable, "loadCSTV");
            auto* lShrCSTV = builder.CreateShl(loadCSTV, llvm::ConstantInt::get(
                    llvm::Type::getInt64Ty(M->getContext()), llvm::APInt(64, CSI_OFFSET)), "lshrCSTV");
            auto* maskCSTV = builder.CreateAnd(lShrCSTV, llvm::ConstantInt::get(
                    llvm::Type::getInt64Ty(M->getContext()), llvm::APInt(64, CSI_MASK)), "mask_csi");

            auto* addCSIInst = builder.CreateAdd(loadRH, maskCSTV);
            auto* NewInst2 = builder.CreateAdd(addCSIInst, SizeParam, "br1_add_");

            // possibly jump to the new block
            auto* loopCondition = builder.CreateICmpEQ(CSSLoopLayerTrack, llvm::ConstantInt::get(
                    llvm::Type::getInt64Ty(M->getContext()), llvm::APInt(64, 0)), "conditionLoop");

            // if zero, go back to merge directly
            builder.CreateCondBr(loopCondition, mergeBlock, thenLoopBlock);

            // condition 1.5, we do the extra loop logic
            builder.SetInsertPoint(thenLoopBlock);
            auto* markLoopBit = builder.CreateOr(NewInst2, llvm::ConstantInt::get(
                    llvm::Type::getInt64Ty(M->getContext()), llvm::APInt(64, LOOP_BIT)), "mask_loop");
            builder.CreateBr(mergeBlock);

            // condition 2, size is larger, we only need to set SI and add size
            builder.SetInsertPoint(elseBlock);

            auto* bb2OrBO = builder.CreateOr(SizeParam, llvm::ConstantInt::get(
                    llvm::Type::getInt64Ty(M->getContext()), llvm::APInt(64, HUGE_BIT)), "br2_and_");
            builder.CreateBr(mergeBlock);

            // eventually
            builder.SetInsertPoint(mergeBlock, mergeBlock->getFirstInsertionPt());

            llvm::PHINode* phi = builder.CreatePHI(llvm::Type::getInt64Ty(M->getContext()), 3);
            phi->addIncoming(NewInst2, thenBlock);
            phi->addIncoming(bb2OrBO, elseBlock);
            phi->addIncoming(markLoopBit, thenLoopBlock);

            // change the argument
            if (llvm::dyn_cast<llvm::CallInst>(CalledInstance->call_inst) != nullptr) {
                llvm::dyn_cast<llvm::CallInst>(CalledInstance->call_inst)->setArgOperand(SizeParamIndex, phi);
            } else {
                llvm::dyn_cast<llvm::InvokeInst>(CalledInstance->call_inst)->setArgOperand(SizeParamIndex, phi);
            }
        }
    }
    llvm::outs() << "HMF update done\n";
}


void InstrumentIRPass::FlipFunctionMap() {
    /*
     * Create a map: Caller -> Callee
     */
    for (auto const& MapEntry: *this->FunctionMap) {
        string CalleeFunctionName = MapEntry.first;

        for (auto CalledInstance : *MapEntry.second) {
            string CallerFunctionName = CalledInstance->Caller;

            // first occur the function name, create the associated vector.
            if (this->FlippedFunctionMap->find(CallerFunctionName) == this->FlippedFunctionMap->end()) {
                this->FlippedFunctionMap->insert({CallerFunctionName, new vector<CallPath*>()});
            }

            // insert the called instance
            (*this->FlippedFunctionMap)[CallerFunctionName]->push_back(CalledInstance);
        }
    }
}


bool InstrumentIRPass::doInitialization() {
    /**
     * This function marks all functions that directly or
     * indirectly calls heap management functions (HMF).
     *
     * This function also identifies functions that are
     * called by multiple functions.
     */

    // create the flipped function map first
    FlipFunctionMap();

    // mark all functions that directly calls the HMF
    for (const auto& FunctionName: InitialHeapFunctions) {

        // the specified HMF is not used in the whole program
        if (this->FunctionMap->find(FunctionName) == this->FunctionMap->end()) {
            continue;
        }

        // for each instruction that calls this HMF
        for (auto CalledInstance: *(*this->FunctionMap)[FunctionName]) {
            string CallerFunctionName = CalledInstance->Caller;

            // mark the current function
            if (this->FunctionMarkSet.find(CallerFunctionName) == this->FunctionMarkSet.end()) {
                this->FunctionMarkSet.insert(CallerFunctionName);
            }

            // set the edge as relevant
            CalledInstance->isRelevant = true;
            CalledInstance->callsHMF = true;
        }
    }

    MarkOnlyRelevantFunctions();
    return false;
}


void InstrumentIRPass::ConstructFinalCFG() {
    for (const auto& currentFunction: this->RelevantAllFunctionSet) {
        // put parents into the map
        auto currentCallerVector = new std::vector<CallPath*>();
        auto currentCalleeVector = new std::vector<CallPath*>();

        this->FinalCallerMap[currentFunction] = currentCallerVector;
        this->FinalCalleeMap[currentFunction] = currentCalleeVector;

        if (this->FunctionMap->find(currentFunction) != this->FunctionMap->end()) {
            for (auto currentCaller: *this->FunctionMap->find(currentFunction)->second) {

                // this is indeed an inner loop
                if (currentCaller->Caller == currentCaller->Callee) {
                    continue;
                }

                // the target function should also be relevant
                auto targetFunction = currentCaller->Caller;
                if (this->RelevantAllFunctionSet.find(targetFunction) == this->RelevantAllFunctionSet.end()) {
                    continue;
                }

                currentCallerVector->push_back(currentCaller);
            }
        }

        if (this->FlippedFunctionMap->find(currentFunction) != this->FlippedFunctionMap->end()) {
            for (auto currentCallee: *this->FlippedFunctionMap->find(currentFunction)->second) {
                // this is indeed an inner loop
                if (currentCallee->Caller == currentCallee->Callee) {
                    continue;
                }

                // the target function should also be relevant
                auto targetFunction = currentCallee->Callee;
                if (this->RelevantAllFunctionSet.find(targetFunction) == this->RelevantAllFunctionSet.end()) {
                    continue;
                }

                currentCalleeVector->push_back(currentCallee);
            }
        }
    } // end for each function

    // Mark branch functions
    for (const auto& currentFunction: this->RelevantAllFunctionSet) {
        // branch function
        if (this->FinalCallerMap.find(currentFunction)->second->size() > 1) {
            for (auto Inst: *this->FinalCallerMap.find(currentFunction)->second) {
                if (Inst->path_type == CallPath::PathType::Default) {
                    Inst->path_type = CallPath::PathType::MarkBranch;
                }
            }
        }
    }
}


void InstrumentIRPass::ComputeEdgeWeight() {
    /**
     * This function does a topological sort and
     * assign the weight to each edge.
     */
    std::map<string, uint64_t> TopologicalCount;
    std::set<string> LeftFunctions = this->RelevantAllFunctionSet;
    for (const auto& CurrentFunction: this->RelevantAllFunctionSet) {
        TopologicalCount[CurrentFunction] = this->FinalCalleeMap[CurrentFunction]->size();
    }

    // Debug: Recursive functions should be represented using the INTRA_ID
    for (const auto& CurrentFunction: this->RelevantAllFunctionSet) {
        for (auto *Entry: *this->FinalCalleeMap[CurrentFunction]) {
            auto Callee = Entry->Callee;
            if (this->FlippedIntraFunctionMap.find(Callee) != this->FlippedIntraFunctionMap.end()) {
                llvm::errs() << "Callee target " << Callee << " of " << CurrentFunction <<
                       " invalid is part of the intra loop" << this->FlippedIntraFunctionMap[Callee] << "\n";
                exit(1);
            }

            if (Entry->Caller != CurrentFunction) {
                llvm::errs() << "The caller of path " << Entry->Caller << " -> " << Entry->Callee
                << " should be " << CurrentFunction << "\n";
                exit(1);
            }
        }

        for (auto *Entry: *this->FinalCallerMap[CurrentFunction]) {
            auto Caller = Entry->Caller;
            if (this->FlippedIntraFunctionMap.find(Caller) != this->FlippedIntraFunctionMap.end()) {
                llvm::errs() << "Caller target " << Caller << " of " << CurrentFunction <<
                       " invalid is part of the intra loop" << this->FlippedIntraFunctionMap[Caller] << "\n";
                exit(1);
            }

            if (Entry->Callee != CurrentFunction) {
                llvm::errs() << "The callee of path " << Entry->Caller << " -> " << Entry->Callee
                       << " should be " << CurrentFunction << "\n";
                exit(1);
            }
        }
    }

    // Debug: Call path in the callee map should also in the caller map.
    for (const auto& CurrentFunction: this->RelevantAllFunctionSet) {
        for (auto *Entry: *this->FinalCalleeMap[CurrentFunction]) {
            auto Callee = Entry->Callee;
            auto* CallerVector = this->FinalCallerMap[Callee];
            bool find = false;

            for (auto* FlipEntry: *CallerVector) {
                if (FlipEntry == Entry) {
                    find = true;
                    break;
                }
            }

            if (!find) {
                llvm::errs() << "Function " << Callee << " is called by " << Entry->Caller <<
                " but the call path can only be found in the ->callee map\n";
                exit(1);
            }
        }
    }

    // Debug: Call path in the caller map should also in the callee map.
    for (const auto& CurrentFunction: this->RelevantAllFunctionSet) {
        for (auto *Entry: *this->FinalCallerMap[CurrentFunction]) {
            auto Caller = Entry->Caller;
            auto* CalleeVector = this->FinalCalleeMap[Caller];
            bool find = false;

            for (auto* FlipEntry: *CalleeVector) {
                if (FlipEntry == Entry) {
                    find = true;
                    break;
                }
            }

            if (!find) {
                llvm::errs() << "Function " << Caller << " is called by " << Entry->Callee <<
                       " but the call path can only be found in the ->caller map\n";
                exit(1);
            }
        }
    }

    while (!LeftFunctions.empty()) {
        string eliminateFunction;
        for (const auto& CurrentFunction: LeftFunctions) {
            if (TopologicalCount[CurrentFunction] == 0) {
                eliminateFunction = CurrentFunction;
                break;
            }
        }

        if (eliminateFunction.empty()) {
            for (const auto& key: LeftFunctions) {
                auto realCount = TopologicalCount[key];
                auto expectedCount = 0;

                for (const auto& Entry: *this->FinalCalleeMap[key]) {
                    if (LeftFunctions.find(Entry->Callee) != LeftFunctions.end()) {
                        expectedCount++;
                    }
                }

                if (realCount != expectedCount) {
                    llvm::errs() << "Count for function " << key << " is not correct!!!\n";
                    llvm::errs() << "The number of children of function should be " << expectedCount
                    << " but is indeed " << realCount << "\n";

                    for (const auto& Entry: *this->FinalCalleeMap[key]) {
                        if (LeftFunctions.find(Entry->Callee) != LeftFunctions.end()) {
                            llvm::errs() << "Target " << Entry->Callee << " waiting to be eliminated.\n";
                        } else {
                            llvm::errs() << "Target " << Entry->Callee << " already eliminated.\n";
                        }
                    }
                }
            }

            // fallback figure
            llvm::errs() << "###########################################\n";
            for (const auto& key: LeftFunctions) {
                for (const auto& Entry: *this->FinalCalleeMap[key]) {
                    if (LeftFunctions.find(Entry->Callee) != LeftFunctions.end()) {
                        llvm::errs() << Entry->Caller << " " << Entry->Callee << "\n";
                    }
                }
            }
            llvm::errs() << "###########################################\n";
            llvm::errs() << "ERROR: Cannot run t-sort\n";
            exit(-1);
        }

        TopologicalOrder.push(eliminateFunction);
        llvm::outs() << eliminateFunction << "\n";
        LeftFunctions.erase(eliminateFunction);
        for (const auto& CurrentFunction: LeftFunctions) {
            auto currentCount = TopologicalCount[CurrentFunction];
            for (auto* Entry: *this->FinalCalleeMap[CurrentFunction]) {
                if (Entry->Callee == eliminateFunction) {
                    currentCount--;
                }
            }
            TopologicalCount[CurrentFunction] = currentCount;
        }
    }

    auto localOrder = TopologicalOrder;
    // assign the weight now
    while (!localOrder.empty()) {
        auto CurrentFunction = localOrder.front();
        localOrder.pop();

        uint32_t accumulatedWeight = 0;
        for (auto* Entry: *this->FinalCalleeMap[CurrentFunction]) {
            Entry->edgeWeight = accumulatedWeight;
            if (this->ComprehensiveOutboundMap.find(Entry->Callee) != ComprehensiveOutboundMap.end() && this->ComprehensiveOutboundMap[Entry->Callee] != 0) {
                accumulatedWeight += this->ComprehensiveOutboundMap[Entry->Callee] + 1;
            } else {
                accumulatedWeight++;
            }
        }

        this->ComprehensiveOutboundMap[CurrentFunction] = accumulatedWeight;
        llvm::outs() << CurrentFunction << " " << accumulatedWeight << "\n";
    }
}


bool InstrumentIRPass::doModulePass() {
#ifdef STAT
    uint32_t AllocationSiteCount = 0;
#endif
    // create the global variable
    auto int64Type = llvm::Type::getInt64Ty(M->getContext());
    auto int64ArrayType = llvm::ArrayType::get(int64Type, CSS_RECURSIVE_STACK_BOUND);
    auto int64ArrayPointerType = llvm::PointerType::get(int64ArrayType, 0);

    auto* CSTrackVariable = new llvm::GlobalVariable(*M, int64Type, false, llvm::GlobalVariable::CommonLinkage, llvm::ConstantInt::get(
            int64Type, llvm::APInt(64, 0)));
    CSTrackVariable->setName(CSTrackVariableName);
    CSTrackVariable->setThreadLocalMode(llvm::GlobalValue::GeneralDynamicTLSModel);

    auto* CSSRecursiveOffsetTrack = new llvm::GlobalVariable(*M, int64Type, false, llvm::GlobalVariable::CommonLinkage, llvm::ConstantInt::get(
            int64Type, llvm::APInt(64, 0)));
    CSSRecursiveOffsetTrack->setName(CSSRecursiveOffsetTrackName);
    CSSRecursiveOffsetTrack->setThreadLocalMode(llvm::GlobalValue::GeneralDynamicTLSModel);

    auto* CSSRecursiveHash = new llvm::GlobalVariable(*M, int64Type, false, llvm::GlobalVariable::CommonLinkage, llvm::ConstantInt::get(
            int64Type, llvm::APInt(64, 0)));
    CSSRecursiveHash->setName(CSSRecursiveHashName);
    CSSRecursiveHash->setThreadLocalMode(llvm::GlobalValue::GeneralDynamicTLSModel);

    auto* CSSRecursiveStack = new llvm::GlobalVariable(*M, int64ArrayType, false, llvm::GlobalVariable::CommonLinkage,
                                                 llvm::ConstantAggregateZero::get(int64ArrayType));
    CSSRecursiveStack->setName(CSSRecursiveStackName);
    CSSRecursiveStack->setThreadLocalMode(llvm::GlobalValue::GeneralDynamicTLSModel);

    auto* CSSLoopLayerTrack = new llvm::GlobalVariable(*M, int64Type, false, llvm::GlobalVariable::CommonLinkage,
                                                       llvm::ConstantAggregateZero::get(int64Type));
    CSSLoopLayerTrack->setName(CSSLoopLayerTrackName);
    CSSLoopLayerTrack->setThreadLocalMode(llvm::GlobalValue::GeneralDynamicTLSModel);


#ifdef DEBUG
    auto DebugStackType = llvm::ArrayType::get(int64Type, this->FunctionIDMap.size() + 10);
    auto* CSSDebugStack = new llvm::GlobalVariable(*M, DebugStackType, false, llvm::GlobalVariable::CommonLinkage,
                                                       llvm::ConstantAggregateZero::get(DebugStackType));
    CSSDebugStack->setName(CSSDebugArrayName);
    CSSDebugStack->setThreadLocalMode(llvm::GlobalValue::GeneralDynamicTLSModel);
#endif

    // we first carry the marks of nonmarked functions to their children
    // we can do this because the children is only called once and only from us
    // otherwise, the current function is forced to be marked
    auto tmpQueue = this->TopologicalOrder;
    std::stack<string> reverseOrder;
    while (!tmpQueue.empty()) {
        reverseOrder.push(tmpQueue.front());
        tmpQueue.pop();
    }

    // we must use reverse order here: start with main
    while (!reverseOrder.empty()) {
        auto currentFunction = reverseOrder.top();
        reverseOrder.pop();

        for (auto CallPath: *this->FinalCalleeMap[currentFunction]) {
            // no mark
            if (CallPath->path_type == CallPath::PathType::Default) {

                // update the children
                auto children = CallPath->Callee;
                if (!this->FinalCalleeMap[children]->empty()) {
                    llvm::outs() << "Carry the weights from " << CallPath->Caller << " to " << CallPath->Callee <<  " value " << CallPath->edgeWeight << "\n";
                    for (auto ChildrenCallPath: *this->FinalCalleeMap[children]) {
                        ChildrenCallPath->edgeWeight += CallPath->edgeWeight;
                    }
                } else { // although it is not a branch, we must trace this path
                    llvm::outs () << "Force set path from " << CallPath->Caller << " to " << children << "\n";
                    CallPath->path_type = CallPath::PathType::MarkBranch;
                }
            }
        } // end for paths
    } // end reverse order

    // we first handle inner branch
    for (const auto& entry: this->FlippedIntraFunctionMap) {
        for (auto Instance: *this->FunctionMap->find(entry.first)->second) { // for all callers
            if (Instance->path_type == CallPath::PathType::MarkInnerBranch) {
                extendInLoopRecursiveCall(Instance->call_inst);
            }
        }
    }

    // assign path IDs
    for (auto const& MapEntry: this->RelevantAllFunctionSet) {
        auto* CallPathVector = this->FinalCalleeMap[MapEntry];
        std::set<void*> uniqueCallInstSet;

        // for each instance
        for (auto CallPath: *CallPathVector) {
            // no mark
            if (CallPath->path_type == CallPath::PathType::Default) {
                continue;
            }
#ifdef STAT
            if (CallPath->callsHMF) {
                CallPath->edgeWeight = AllocationSiteCount++;
                llvm::outs() << CallPath->Caller << " calls "
                             << CallPath->Callee << " with weight " << CallPath->edgeWeight << "\n";
            } else {
                CallPath->edgeWeight = 0;
            }
#endif

            // skip the entry if it is already handled
            // we can do this as the algorithm says yes: it is the callee not caller
            if (uniqueCallInstSet.find(CallPath->call_inst) != uniqueCallInstSet.end()) {
                continue;
            } else {
                uniqueCallInstSet.insert(CallPath->call_inst);
            }

            auto CallInstance = CallPath->call_inst;

            // we handle the recursive first, and do the regular logic below
            if (CallPath->path_type == CallPath::PathType::MarkSimpleInner || CallPath->path_type == CallPath::PathType::MarkInnerBranch) {
                continue; // no need to do below
            } else if (CallPath->path_type == CallPath::PathType::MarkOutbound) {
                extendOutBoundRecursiveCall(CallInstance);
            } else if (CallPath->path_type == CallPath::PathType::MarkInbound) {
                extendInBoundRecursiveCall(CallInstance);
            }

            if (CallPath->edgeWeight != 0) {
                auto* LoadBefore = new llvm::LoadInst(CSTrackVariable->getType()->getPointerElementType(), CSTrackVariable, "", CallInstance);

                // create and insert the new instruction
                llvm::Instruction* PlusInst = llvm::BinaryOperator::CreateAdd(
                        LoadBefore, llvm::ConstantInt::get(
                                CSTrackVariable->getType(), llvm::APInt(64, CallPath->edgeWeight)));

                // before calling the function
                PlusInst->insertBefore(CallInstance);

                // store the track variable
                new llvm::StoreInst(PlusInst, CSTrackVariable, CallInstance);
            }

            // increase the loop layer count
            if (CallPath->path_type != CallPath::PathType::MarkBranch) {
                llvm::outs() << "[Node] <Loop> " << CallPath->Callee << "\n";
                insertIncreaseLoopLayerLogic(CallInstance);
            } else {
                llvm::outs() << "[Node] <Sing> " << CallPath->Callee << "\n";
            }

            // after calling the function
            // Option 1: this is a CallInst
            if (llvm::dyn_cast<llvm::CallInst>(CallInstance) != nullptr) {

                if (CallPath->edgeWeight != 0) {
                    llvm::LoadInst* LoadAfter;
                    if (CallInstance->getNextNode() == nullptr) {
                        llvm::IRBuilder<> builder(CallInstance->getParent());
                        LoadAfter = builder.CreateLoad(CSTrackVariable->getType()->getPointerElementType(), CSTrackVariable);
                    } else {
                        LoadAfter = new llvm::LoadInst(CSTrackVariable->getType()->getPointerElementType(), CSTrackVariable, "", CallInstance->getNextNode());
                    }

                    llvm::Instruction* MinusInst = llvm::BinaryOperator::CreateSub(
                            LoadAfter, llvm::ConstantInt::get(
                                    CSTrackVariable->getType(), llvm::APInt(64, CallPath->edgeWeight)));

                    MinusInst->insertAfter(LoadAfter);

                    // store the track variable
                    new llvm::StoreInst(MinusInst, CSTrackVariable, MinusInst->getNextNode());
                }

                // mark a bit for loop
                if (CallPath->path_type != CallPath::PathType::MarkBranch) {
                    insertDecreaseLoopLayerLogic(CallInstance->getNextNode());
                }
            } else {
                // Option2: This is an invoke inst
                auto* InvokeInstruction = llvm::dyn_cast<llvm::InvokeInst>(CallInstance);
                auto* target1 = InvokeInstruction->getNormalDest();
                auto* target2 = InvokeInstruction->getUnwindDest();

                // Work on Target1 first

                // note that we should probably create a new BB as other bb might also jump to this target
                // TODO: currently always create new BB
                llvm::IRBuilder<> builder(target1->getContext());
                llvm::BasicBlock* newTarget1 = llvm::BasicBlock::Create(target1->getContext(), "invokeBB", target1->getParent());

                // replace the branch target to newtarget1
                InvokeInstruction->setNormalDest(newTarget1);
                builder.SetInsertPoint(newTarget1);

                if (CallPath->edgeWeight != 0) {
                    auto* LoadAfter1 = builder.CreateLoad(CSTrackVariable->getType()->getPointerElementType(), CSTrackVariable);

                    auto* MinusInst1 = builder.CreateSub(LoadAfter1, llvm::ConstantInt::get(
                            CSTrackVariable->getType(), llvm::APInt(64, CallPath->edgeWeight)));

                    // store the track variable
                    builder.CreateStore(MinusInst1, CSTrackVariable);
                }

                // the new target should go back to the regular control flow
                builder.CreateBr(target1);

                // we need to handle the phi that in the original target1: all comes from invoke should now come from newtarget1
                for (auto& inst: *target1) {
                    auto* targetPhi = llvm::dyn_cast<llvm::PHINode>(&inst);
                    if (targetPhi == nullptr) {
                        break; // phi must happen before others
                    }

                    for (int i = 0; i < targetPhi->getNumIncomingValues(); i++) {
                        if (targetPhi->getIncomingBlock(i) == InvokeInstruction->getParent()) {
                            targetPhi->setIncomingBlock(i, newTarget1);
                        }
                    }
                }

                // mark a bit for loop
                if (CallPath->path_type != CallPath::PathType::MarkBranch) {
                    insertDecreaseLoopLayerLogic(newTarget1->getFirstNonPHI());
                }

                if (CallPath->edgeWeight != 0) {
                    // Work on Target2 then
                    auto* LoadAfter2 = new llvm::LoadInst(CSTrackVariable->getType()->getPointerElementType(),
                                                    CSTrackVariable, "", target2->getFirstNonPHI()->getNextNode());

                    auto* MinusInst = llvm::BinaryOperator::CreateSub(
                            LoadAfter2, llvm::ConstantInt::get(
                                    CSTrackVariable->getType(), llvm::APInt(64, CallPath->edgeWeight)));

                    MinusInst->insertAfter(LoadAfter2);

                    // store the track variable
                    new llvm::StoreInst(MinusInst, CSTrackVariable, MinusInst->getNextNode());
                }

                // mark a bit for loop
                if (CallPath->path_type != CallPath::PathType::MarkBranch) {
                    insertDecreaseLoopLayerLogic(target2->getFirstNonPHI()->getNextNode());
                }
            } // end handling after

#ifdef DEBUG
            // skip check for invoke now
            if (CallPath->call_inst->getNextNode() == nullptr) {
                InsertSaveTrackLogic(CallPath->call_inst, this->FunctionIDMap[CallPath->Caller],
                                     CallPath->Caller, CallPath->Callee);
                continue;
            }
            InsertSaveTrackLogic(CallPath->call_inst, this->FunctionIDMap[CallPath->Caller],
                                 CallPath->Caller, CallPath->Callee);
            InsertCheckTrackLogic(CallPath->call_inst->getNextNode(), this->FunctionIDMap[CallPath->Caller],
                                  CallPath->Caller, CallPath->Callee);
#endif
        } // end instance
    }

    // modify the HMF
    UpdateHMFInterface();
    return false;
}


bool InstrumentIRPass::run() {
    llvm::outs() << "[STEP 1]: Find all relevant functions.\n";
    doInitialization();

    llvm::outs() << "[STEP 2]: Find all loops (remove all non-relevant functions).\n";
    instrIsInaLoop();

    llvm::outs() << "[STEP 3]: Find all functions relevant to the loops.\n";
    MarkLoopRelevantFunctions();

    llvm::outs() << "[STEP 4]: Construct the CFG that only contains relevant functions.\n";
    ConstructFinalCFG();

    llvm::outs() << "[STEP 5]: Compute the weights.\n";
    ComputeEdgeWeight();

    llvm::outs() << "[STEP 6]: Update the interfaces.\n";

    llvm::outs() << "Number of CFG Nodes: " << this->FinalCalleeMap.size() << "\n";
    llvm::outs() << "Number of SCCs: " << this->IntraFunctionMap.size() << "\n";

    size_t n_callsite = 0;
    for (const auto& callee: InitialHeapFunctions) {
        if (this->FinalCallerMap.find(callee) == this->FinalCallerMap.end()) {
            continue;
        }
        n_callsite += this->FinalCallerMap[callee]->size();
    }
    llvm::outs() << "Number of Call Sites: " << n_callsite << "\n";

    size_t n_edges = 0;
    for (const auto& entry: this->FinalCalleeMap) {
        n_edges += entry.second->size();
    }
    llvm::outs() << "Number of CFG Edges: " << n_edges << "\n";

#ifdef DEBUG
    AssignFunctionID();
#endif
    doModulePass();

    PrintFinalMap();

    llvm::outs() << "Analysis done.\n";
    return false;
}


void InstrumentIRPass::PrintFinalMap() {
    llvm::outs() << "####################################\n";
    for (const auto& MapEntry : this->FinalCalleeMap) {
        llvm::outs() << "Function " << MapEntry.first << " calls " << MapEntry.second->size() << " functions\n";
        for (auto *CalleeEntry: *MapEntry.second) {
            llvm::outs() << "\t";
            if (CalleeEntry->path_type == CalleeEntry->MarkBranch) {
                llvm::outs() << " [branch] ";
            } else if (CalleeEntry->path_type == CalleeEntry->MarkSimpleLoop) {
                llvm::outs() << " [siloop] ";
            } else if (CalleeEntry->path_type == CalleeEntry->MarkInbound) {
                llvm::outs() << " [ibound] ";
            } else if (CalleeEntry->path_type == CalleeEntry->MarkOutbound) {
                llvm::outs() << " [obound] ";
            } else {
                llvm::outs() << " [nthing] ";
            }
            llvm::outs() << CalleeEntry->Callee << "\n";
        }
    }
    llvm::outs() << "####################################\n";
}


#ifdef DEBUG
    void InstrumentIRPass::AssignFunctionID() {
    uint64_t i = 0;
    for (const auto& entry: this->RelevantAllFunctionSet) {
        this->FunctionIDMap[entry] = i++;
    }
}
#endif
