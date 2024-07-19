#include <llvm/IR/InlineAsm.h>
#include <llvm/IR/InstIterator.h>
#include <llvm/IR/Instructions.h>
#include <llvm/IR/Operator.h>
#include <fstream>
#include <sstream>
#include <regex>
#include "Common.h"
#include "Config.h"


// Map from struct elements to its name
static map<string, set<llvm::StringRef>>elementsStructNameMap;

bool trimPathSlash(string &path, int slash) {
	while (slash > 0) {
		path = path.substr(path.find('/') + 1);
		--slash;
	}

	return true;
}

string getFileName(llvm::DILocation *Loc, llvm::DISubprogram *SP) {
	string FN;
	if (Loc)
		FN = Loc->getFilename().str();
	else if (SP)
		FN = SP->getFilename().str();
	else
		return "";

	int slashToTrim = 2;
	char *user = getlogin();
	// if (strstr(user, "r53wang")) {
	// 	slashToTrim = 0;
	// 	trimPathSlash(FN, slashToTrim);
	// 	FN = string(SOURCE_CODE_PATH) + "/" + FN;
	// } 
	// else {
	// 	OP << "== Warning: please specify the path of linux source.";
	// }
	return FN;
}

/// Check if the value is a constant.
bool isConstant(llvm::Value *V) {
  // Invalid input.
  if (!V) 
    return false;

  // The value is a constant.
    llvm::Constant *Ct = llvm::dyn_cast<llvm::Constant>(V);
  if (Ct) 
    return true;

  return false;
}

/// Get the source code line
string getSourceLine(string fn_str, unsigned lineno) {
	std::ifstream sourcefile(fn_str);
	string line;
	sourcefile.seekg(std::ios::beg);
	
	for(int n = 0; n < lineno - 1; ++n){
		sourcefile.ignore(std::numeric_limits<std::streamsize>::max(), '\n');
	}
	getline(sourcefile, line);

	return line;
}

string getSourceFuncName(llvm::Instruction *I) {

    llvm::DILocation *Loc = getSourceLocation(I);
	if (!Loc)
		return "";
	unsigned lineno = Loc->getLine();
	std::string fn_str = getFileName(Loc);
	string line = getSourceLine(fn_str, lineno);
	
	while(line[0] == ' ' || line[0] == '\t')
		line.erase(line.begin());
	line = line.substr(0, line.find('('));
	return line;
}

string extractMacro(string line, llvm::Instruction *I) {
	string macro, word, FnName;
	std::regex caps("[^\\(][_A-Z][_A-Z0-9]+[\\);,]+");
    std::smatch match;
	
	// detect function macros
	if (llvm::CallInst *CI = llvm::dyn_cast<llvm::CallInst>(I)) {
		FnName = getCalledFuncName(CI).str();
		caps = "[_A-Z][_A-Z0-9]{2,}";
		std::regex keywords("(\\s*)(for|if|while)(\\s*)(\\()");

		if (regex_search(line, match, keywords))
		  line = line.substr(match[0].length());
		
		if (line.find(FnName) != std::string::npos) {
			if (regex_search(FnName, match, caps))
				return FnName;

		} else {
			//identify non matching functions as macros
			//std::count(line.begin(), line.end(), '"') > 0
			std::size_t eq_pos = line.find_last_of("=");
			if (eq_pos == std::string::npos)
				eq_pos = 0;
			else
				++eq_pos;

			std::size_t paren = line.find('(', eq_pos);
			return line.substr(eq_pos, paren-eq_pos);
		}

	} else {
		// detect macro constant variables
		std::size_t lhs = -1;
		std::stringstream iss(line.substr(lhs+1));

		while (iss >> word) {
			if (regex_search(word, match, caps)) {
				macro = word;
				return macro;
			}
		}
	}

	return "";
}

/// Get called function name of V.
llvm::StringRef getCalledFuncName(llvm::CallInst *CI) {

    llvm::Value *V;
	V = CI->getCalledOperand();
	assert(V);

    llvm::InlineAsm *IA = llvm::dyn_cast<llvm::InlineAsm>(V);
	if (IA)
		return llvm::StringRef(IA->getAsmString());

    llvm::User *UV = llvm::dyn_cast<llvm::User>(V);
	if (UV) {
		if (UV->getNumOperands() > 0) {
            llvm::Value *VUV = UV->getOperand(0);
			return VUV->getName();
		}
	}

	return V->getName();
}

llvm::DILocation *getSourceLocation(llvm::Instruction *I) {
  if (!I)
    return NULL;

    llvm::MDNode *N = I->getMetadata("dbg");
  if (!N)
    return NULL;

    llvm::DILocation *Loc = llvm::dyn_cast<llvm::DILocation>(N);
  if (!Loc || Loc->getLine() < 1)
		return NULL;

	return Loc;
}

/// Print out source code information to facilitate manual analyses.
void printSourceCodeInfo(llvm::Value *V, string Tag) {
  llvm::Instruction *I = llvm::dyn_cast<llvm::Instruction>(V);
  if (!I)
    return;

  llvm::DILocation *Loc = getSourceLocation(I);
  if (!Loc)
    return;

  unsigned LineNo = Loc->getLine();
  std::string FN = getFileName(Loc);
  string line = getSourceLine(FN, LineNo);
  FN = Loc->getFilename().str();
  //FN = FN.substr(FN.find('/') + 1);
  //FN = FN.substr(FN.find('/') + 1);

  while(line[0] == ' ' || line[0] == '\t')
    line.erase(line.begin());
  OP << " ["
    << "\033[34m" << Tag << "\033[0m" << "] "
    << FN
    << " +" << LineNo
#ifdef PRINT_SOURCE_LINE
  << " "
    << "\033[35m" << line << "\033[0m" <<'\n';
  OP<<*I
#endif
        <<"\n";
}


void printSourceCodeInfo(llvm::Function *F, string Tag) {

    llvm::DISubprogram *SP = F->getSubprogram();

  if (SP) {
    string FN = getFileName(NULL, SP);
    string line = getSourceLine(FN, SP->getLine());
    while(line[0] == ' ' || line[0] == '\t')
      line.erase(line.begin());

    FN = SP->getFilename().str();
    //FN = FN.substr(FN.find('/') + 1);
    //FN = FN.substr(FN.find('/') + 1);

    OP << " ["
      << "\033[34m" << Tag << "\033[0m" << "] "
      << FN
      << " +" << SP->getLine()
#ifdef PRINT_SOURCE_LINE
      << " "
      << "\033[35m" << line << "\033[0m"
#endif
      <<'\n';
  }
#ifdef PRINT_SOURCE_LINE
  else {
    OP << " ["
      << "\033[34m" << "??" << "\033[0m" << "] "
      << F->getParent()->getName()<<": "<<F->getName()<<'\n';
  }
#endif
}

string getMacroInfo(llvm::Value *V) {

    llvm::Instruction *I = llvm::dyn_cast<llvm::Instruction>(V);
	if (!I) return "";

    llvm::DILocation *Loc = getSourceLocation(I);
	if (!Loc) return "";

	unsigned LineNo = Loc->getLine();
	std::string FN = getFileName(Loc);
	string line = getSourceLine(FN, LineNo);
	FN = Loc->getFilename().str();
	const char *filename = FN.c_str();
	filename = strchr(filename, '/') + 1;
	filename = strchr(filename, '/') + 1;
	int idx = filename - FN.c_str();

	while(line[0] == ' ' || line[0] == '\t')
		line.erase(line.begin());

	string macro = extractMacro(line, I);

	//clean up the ending and whitespaces
	macro.erase(std::remove (macro.begin(), macro.end(),' '), macro.end());
	unsigned length = 0;
	for (auto it = macro.begin(), e = macro.end(); it != e; ++it)
		if (*it == ')' || *it == ';' || *it == ',') {
			macro = macro.substr(0, length);
			break;
		} else {
			++length;
		}

	return macro;
}

/// Get source code information of this value
void getSourceCodeInfo(llvm::Value *V, string &file,
                               unsigned &line) {
  file = "";
  line = 0;

  auto I = llvm::dyn_cast<llvm::Instruction>(V);
  if (!I)
    return;

    llvm::MDNode *N = I->getMetadata("dbg");
  if (!N)
    return;

    llvm::DILocation *Loc = llvm::dyn_cast<llvm::DILocation>(N);
  if (!Loc || Loc->getLine() < 1)
    return;

  file = Loc->getFilename().str();
  line = Loc->getLine();
}

int8_t getArgNoInCall(llvm::CallInst *CI, llvm::Value *Arg) {
	
	int8_t Idx = 0;
	for (auto AI = CI->arg_begin(), E = CI->arg_end(); 
			AI != E; ++AI) {
		if (*AI == Arg) {
			return Idx;
		}
		++Idx;
	}
	return -1;
}

llvm::Argument *getParamByArgNo(llvm::Function *F, int8_t ArgNo) {

  if (ArgNo >= F->arg_size())
    return NULL;

  int8_t idx = 0;
    llvm::Function::arg_iterator ai = F->arg_begin();
  while (idx != ArgNo) {
    ++ai;
    ++idx;
  }
  return ai;
}

void LoadElementsStructNameMap(
		vector<pair<llvm::Module*, llvm::StringRef>> &Modules) {

	for (auto M : Modules) {
		for (auto STy : M.first->getIdentifiedStructTypes()) {
			assert(STy->hasName());
			if (STy->isOpaque())
				continue;

			string strSTy = structTyStr(STy);
			elementsStructNameMap[strSTy].insert(STy->getName());
		}
	}
}

void cleanString(string &str) {
	// process string
	// remove c++ class type added by compiler
	size_t pos = str.find("(%class.");
	if (pos != string::npos) {
		//regex pattern1("\\(\\%class\\.[_A-Za-z0-9]+\\*,?");
		std::regex pattern("^[_A-Za-z0-9]+\\*,?");
		std::smatch match;
		string str_sub = str.substr(pos + 8);
		if (regex_search(str_sub, match, pattern)) {
			str.replace(pos + 1, 7 + match[0].length(), "");
		}
	}
	string::iterator end_pos = remove(str.begin(), str.end(), ' ');
	str.erase(end_pos, str.end());
}

string funcTypeString(llvm::FunctionType *FTy) {

	string output;
	for (llvm::FunctionType::param_iterator pi = FTy->param_begin();
			pi != FTy->param_end(); ++ pi) {
        llvm::Type *PTy = *pi;
		string sig;
        llvm::raw_string_ostream rso(sig);
		PTy->print(rso);
		output += rso.str();
		//output += to_string(PTy->getTypeID());
		//output += ","; 
	}
	return output;
}

size_t funcHash(llvm::Function *F, bool withName) {

	std::hash<string> str_hash;
	string output;

#ifdef HASH_SOURCE_INFO
	DISubprogram *SP = F->getSubprogram();

	if (SP) {
		output = SP->getFilename();
		output = output + to_string(uint_hash(SP->getLine()));
	}
	else {
#endif
    string sig;
    llvm::raw_string_ostream rso(sig);
    llvm::FunctionType *FTy = F->getFunctionType();
    FTy->print(rso);
    output = rso.str();
    //output = funcTypeString(FTy);

    if (withName)
        output += F->getName();
#ifdef HASH_SOURCE_INFO
	}
#endif
	// process string
	cleanString(output);

	return str_hash(output);
}

size_t callHash(llvm::CallInst *CI) {

    llvm::CallBase *CB = llvm::dyn_cast<llvm::CallBase>(CI);
	//Value *CO = CI->getCalledOperand();
	//if (CO) {
	//	Function *CF = dyn_cast<Function>(CO);
	//	if (CF)
	//		return funcHash(CF);
	//}
    std::hash<string> str_hash;
	string sig;
    llvm::raw_string_ostream rso(sig);
    llvm::FunctionType *FTy = CB->getFunctionType();
	FTy->print(rso);
	string strip_str = rso.str();
	//string strip_str = funcTypeString(FTy);
	cleanString(strip_str);

	return str_hash(strip_str);
}

string structTyStr(llvm::StructType *STy) {
	string ty_str;
	string sig;
	for (auto Ty : STy->elements()) {
		ty_str += to_string(Ty->getTypeID());
	}
	return ty_str;
}

void structTypeHash(llvm::StructType *STy, set<size_t> &HSet) {
  std::hash<string> str_hash;
  string sig;
  string ty_str;

  // TODO: Use more but reliable information
  // FIXME: A few cases may not even have a name
  if (STy->hasName()) {
    ty_str = STy->getName().str();
    HSet.insert(str_hash(ty_str));
  }
  else {
    string sstr = structTyStr(STy);
    if (elementsStructNameMap.find(sstr)
        != elementsStructNameMap.end()) {
      for (auto SStr : elementsStructNameMap[sstr]) {
        ty_str = SStr.str();
        HSet.insert(str_hash(ty_str));
      }
    }
  }
}

size_t typeHash(llvm::Type *Ty) {
  std::hash<string> str_hash;
  string sig;
  string ty_str;

  if (llvm::StructType *STy = llvm::dyn_cast<llvm::StructType>(Ty)) {
    // TODO: Use more but reliable information
    // FIXME: A few cases may not even have a name
    if (STy->hasName()) {
      ty_str = STy->getName().str();
    }
    else {
      string sstr = structTyStr(STy);
      if (elementsStructNameMap.find(sstr)
          != elementsStructNameMap.end()) {
        ty_str = elementsStructNameMap[sstr].begin()->str();
      }
    }
  }
#ifdef SOUND_MODE
  else if (llvm::ArrayType *ATy = llvm::dyn_cast<llvm::ArrayType>(Ty)) {

    // Compiler sometimes fails recoginize size of array (compiler
    // bug?), so let's just use the element type

    //Ty = ATy->getElementType();
    llvm::raw_string_ostream rso(sig);
    Ty->print(rso);
    ty_str = rso.str() + "[array]";
    string::iterator end_pos = remove(ty_str.begin(), ty_str.end(), ' ');
    ty_str.erase(end_pos, ty_str.end());
  }
#endif
  else {
    llvm::raw_string_ostream rso(sig);
    Ty->print(rso);
    ty_str = rso.str();
    string::iterator end_pos = remove(ty_str.begin(), ty_str.end(), ' ');
    ty_str.erase(end_pos, ty_str.end());
  }
  return str_hash(ty_str);
}

size_t hashIdxHash(size_t Hs, int Idx) {
	std::hash<string> str_hash;
	return Hs + str_hash(to_string(Idx));
}

size_t typeIdxHash(llvm::Type *Ty, int Idx) {
	return hashIdxHash(typeHash(Ty), Idx);
}

size_t strIntHash(string str, int i) {
	std::hash<string> str_hash;
	// FIXME: remove pos
	size_t pos = str.rfind("/");
	return str_hash(str.substr(0, pos) + to_string(i));
}

int64_t getGEPOffset(const llvm::Value *V, const llvm::DataLayout *DL) {

	const llvm::GEPOperator *GEP = llvm::dyn_cast<llvm::GEPOperator>(V);

	int64_t offset = 0;
	const llvm::Value *baseValue = GEP->getPointerOperand()->stripPointerCasts();
	if (const llvm::ConstantExpr *cexp = llvm::dyn_cast<llvm::ConstantExpr>(baseValue))
		if (cexp->getOpcode() == llvm::Instruction::GetElementPtr)
		{
			// FIXME: this looks incorrect
			offset += getGEPOffset(cexp, DL);
		}
    llvm::Type *ptrTy = GEP->getSourceElementType();

    llvm::SmallVector<llvm::Value *, 4> indexOps(GEP->op_begin() + 1, GEP->op_end());
	// Make sure all indices are constants
	for (unsigned i = 0, e = indexOps.size(); i != e; ++i)
	{
		if (!llvm::isa<llvm::ConstantInt>(indexOps[i]))
			indexOps[i] = llvm::ConstantInt::get(llvm::Type::getInt32Ty(ptrTy->getContext()), 0);
	}
	offset += DL->getIndexedOffsetInType(ptrTy, indexOps);
	return offset;
}

