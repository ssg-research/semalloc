#!/usr/bin/ruby -w

def convert(global_prefix='/app/', input_file, cmd)
    env = {
        "LLVM_COMPILER" => "clang",
        "LLVM_COMPILER_PATH" => "#{global_prefix}llvm15/build/bin/",
        "CC" => "wllvm",
        "CXX" => "wllvm++",
        "CLAGS" => " -Xclang -no-opaque-pointers -Xclang -mno-constructor-aliases",
        "CXXFLAGS" => " -Xclang -no-opaque-pointers -Xclang -mno-constructor-aliases"
    }
    
    css_path = "#{global_prefix}semalloc/frontend"

    system(env, "extract-bc #{input_file}")
    system(env, "#{css_path}/build/lib/kanalyzer #{input_file}.bc -output=#{input_file}.out.bc")
    system(env, "#{global_prefix}llvm15/build/bin/clang++ -L#{global_prefix}/semalloc/frontend/build/lib/ -lBuildSupport #{input_file}.out.bc -o #{cmd} #{input_file}.out")
    system(env, "#{global_prefix}llvm15/build/bin/clang++ -L#{global_prefix}/semalloc/frontend/build/lib/ -lBuildSupport #{input_file}.bc -o #{cmd} #{input_file}.regular")
end

convert(input_file=ARGV[0], cmd=ARGV[1])
