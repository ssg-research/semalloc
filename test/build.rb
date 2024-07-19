#!/usr/bin/ruby -w

def build(global_prefix='/app/', build_cmd)
    env = {
        "LLVM_COMPILER" => "clang",
        "LLVM_COMPILER_PATH" => "#{global_prefix}llvm15/build/bin/",
        "CC" => "wllvm",
        "CXX" => "wllvm++",
        "CLAGS" => " -Xclang -no-opaque-pointers -Xclang -mno-constructor-aliases",
        "CXXFLAGS" => " -Xclang -no-opaque-pointers -Xclang -mno-constructor-aliases"
    }

    system(env, "echo '' && #{build_cmd}")
end

build(build_cmd=ARGV[0])
