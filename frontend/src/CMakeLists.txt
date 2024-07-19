include_directories(../include/)

set (AnalyzerSourceCodes
		../include/Config.h
		../include/Common.h
		../include/Analyzer.h
		../include/CallGraph.h
		../include/ConstructCG.hh
		../include/MLTA.h
		../include/InstrumentIR.hh
		../include/CallPath.hh
		../include/RecursiveHelper.h
		../include/PreMLTA.hh
		../include/PostMLTA.hh
		../include/debug.hh
		../include/ReduceLibraryIndirectCall.hh
		Config.cc
		Common.cc
		Analyzer.cc
		CallGraph.cc
		ConstructCG.cc
		MLTA.cc
		InstrumentIR.cc
		RecursiveHelper.cc
		PreMLTA.cc
		PostMLTA.cc
		ReduceLibraryIndirectCall.cc
	)

set(CMAKE_MACOSX_RPATH 0)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

# Build libraries.
add_library (AnalyzerObj OBJECT ${AnalyzerSourceCodes})
add_library (Analyzer SHARED $<TARGET_OBJECTS:AnalyzerObj>)
add_library (AnalyzerStatic STATIC $<TARGET_OBJECTS:AnalyzerObj>)

add_library (BuildSupport STATIC helper.cc ../include/Config.h)

# Build executable.
set (EXECUTABLE_OUTPUT_PATH ${ANALYZER_BINARY_DIR})
link_directories (${ANALYZER_BINARY_DIR}/lib)
add_executable(kanalyzer ${AnalyzerSourceCodes})
target_link_libraries(kanalyzer
	LLVMTransformUtils
	LLVMAsmParser 
	LLVMSupport 
	LLVMCore 
	LLVMAnalysis
	LLVMIRReader
	AnalyzerStatic
	)

target_link_libraries(Analyzer
  "$<$<PLATFORM_ID:Darwin>:-undefined dynamic_lookup>")