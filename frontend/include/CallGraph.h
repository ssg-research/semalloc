#ifndef _CALL_GRAPH_H
#define _CALL_GRAPH_H

#include "Analyzer.h"
#include "MLTA.h"
#include "Config.h"

class CallGraphPass : 
	public virtual IterativeModulePass, public virtual MLTA {

	private:

		//
		// Variables
		//

		// Index of the module
		int MIdx;

		set<llvm::CallInst *>CallSet;
		set<llvm::CallInst *>ICallSet;
		set<llvm::CallInst *>MatchedICallSet;


		//
		// Methods
		//
		void doMLTA(llvm::Function *F);


	public:
		static int AnalysisPhase;

		explicit CallGraphPass(GlobalContext *Ctx_)
			: IterativeModulePass(Ctx_, "CallGraph"),
			MLTA(Ctx_) {

				LoadElementsStructNameMap(Ctx->Modules);
				MIdx = 0;
			}

		bool doInitialization(llvm::Module *) override;
        bool doFinalization(llvm::Module *) override;
		bool doModulePass(llvm::Module *) override;

};

#endif
