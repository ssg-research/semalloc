#!/usr/bin/ruby -w

def extract_and_convert(global_prefix='/app/', mimalloc_test, build_cmd)
    test_arr = mimalloc_test.split('/')
    test_dir = test_arr[0]
    test_name = test_arr[-1]

    env = {"LLVM_COMPILER" => "clang", "LLVM_COMPILER_PATH" => "#{global_prefix}llvm15/build/bin/"}
    source_path = "#{global_prefix}mimalloc-bench/#{mimalloc_test}"
    css_path = "#{global_prefix}semalloc/"

    puts "Converting #{test_name} at #{source_path}"
    system(env, "extract-bc #{source_path}")
    system(env, "#{css_path}frontend/build/lib/kanalyzer #{source_path}.bc")

    puts "Building #{test_name} regular and converted"
    system(env, "#{global_prefix}llvm15/build/bin/clang++ #{source_path}.bc -L#{global_prefix}/semalloc/frontend/build/lib/ -lBuildSupport #{build_cmd} -o  #{css_path}test/input/#{test_name}.regular")
    system(env, "#{global_prefix}llvm15/build/bin/clang++ #{css_path}test/input/output.bc -L#{global_prefix}/semalloc/frontend/build/lib/ -lBuildSupport #{build_cmd} -o  #{css_path}test/input/#{test_name}.out")
    puts "Done"
end

def build(global_prefix='/app/', mimalloc_test)
    env = {
        "LLVM_COMPILER" => "clang",
        "LLVM_COMPILER_PATH" => "#{global_prefix}llvm15/build/bin/",
        "CC" => "wllvm",
        "CXX" => "wllvm++",
        "CFLAGS" => "-Xclang -no-opaque-pointers -Xclang -mno-constructor-aliases",
        "CXXFLAGS" => "-Xclang -no-opaque-pointers -Xclang -mno-constructor-aliases"
    }

    puts "Building #{mimalloc_test} original ..."
    system(env, "#{global_prefix}mimalloc-bench/build-bench-env.sh #{mimalloc_test}")
end


def build_ruby(global_prefix='/app/')
    ext_addr = "#{global_prefix}mimalloc-bench/extern"
    ruby_addr = "#{ext_addr}/ruby-3.3.0"
    bin_addr = "#{ruby_addr}/release/bin"
    bench_option = "-Wl,-export-dynamic -Wl,-rpath,#{ruby_addr}/release/lib -L#{ruby_addr}/release/lib -lruby-static -lz -lrt -lrt -lgmp -ldl -lcrypt -lm -lpthread  -lz -lrt -lrt -lgmp -ldl -lcrypt -lm -lpthread"

    env = {
        "LLVM_COMPILER" => "clang", 
        "LLVM_COMPILER_PATH" => "#{global_prefix}llvm15/build/bin/",
        "CFLAGS" => "-Xclang -no-opaque-pointers -Xclang -mno-constructor-aliases",
        "CXXFLAGS" => "-Xclang -no-opaque-pointers -Xclang -mno-constructor-aliases",
        "CC" => "wllvm",
        "CXX" => "wllvm++"
    }
    css_path = "#{global_prefix}semalloc/"

    puts "Obtaining ruby"
    Dir.chdir("#{ext_addr}")
    system ("wget https://cache.ruby-lang.org/pub/ruby/3.3/ruby-3.3.0.tar.gz")
    system ("tar -xvzf ruby-3.3.0.tar.gz")
    Dir.chdir("#{ruby_addr}")

    puts "Building ruby"
    system (env, "./autogen.sh")
    system ("mkdir -p build")
    system ("mkdir -p release")

    Dir.chdir("#{ruby_addr}/build")
    system (env, "../configure --prefix=#{ruby_addr}/release")
    system (env, "make install")

    puts "Converting ruby"
    system(env, "extract-bc #{bin_addr}/ruby")
    system(env, "#{css_path}frontend/build/lib/kanalyzer #{bin_addr}/ruby.bc -output=#{css_path}test/input/ruby.out.bc")

    puts "Building ruby regular"
    system(env, "#{global_prefix}llvm15/build/bin/clang++ #{bin_addr}/ruby.bc -L#{global_prefix}/semalloc/frontend/build/lib/ -lBuildSupport #{bench_option} -o  #{css_path}test/input/ruby.regular")
    
    puts "Building ruby converted"
    system(env, "#{global_prefix}llvm15/build/bin/clang++ #{css_path}test/input/ruby.out.bc -L#{global_prefix}/semalloc/frontend/build/lib/ -lBuildSupport #{bench_option} -o  #{css_path}test/input/ruby.out")

    puts "Done"
end

build_tests = [
    'bench'
]

build_binaries = {
    'alloc-test' => [{'binary' => 'out/bench/alloc-test', 'option' => '-w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -O3 -DNDEBUG -rdynamic -lpthread'}],
    'cscratch' => [{'binary' => 'out/bench/cache-scratch', 'option' => '-w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -O3 -DNDEBUG -rdynamic -lpthread'}],
    'cthrash' => [{'binary' => 'out/bench/cache-thrash', 'option' => '-w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -O3 -DNDEBUG -rdynamic -lpthread'}],
    'glibc-simple' => [{'binary' => 'out/bench/glibc-simple', 'option' => '-march=native -w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -O3 -DNDEBUG -rdynamic -lpthread'}],
    'malloc-large' => [{'binary' => 'out/bench/malloc-large', 'option' => '-w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -O3 -DNDEBUG -rdynamic -lpthread'}],
    'rptest' => [{'binary' => 'out/bench/rptest', 'option' => '-march=native -w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -O3 -DNDEBUG -rdynamic -lpthread -lm'}],
    'mstress' => [{'binary' => 'out/bench/mstress', 'option' => '-march=native -w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -O3 -DNDEBUG -rdynamic -lpthread'}],
    'sh6bench' => [{'binary' => 'out/bench/sh6bench', 'option' => '-march=native -w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -O3 -DNDEBUG -rdynamic -lpthread'}],
    'sh8bench' => [{'binary' => 'out/bench/sh8bench', 'option' => '-march=native -w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -O3 -DNDEBUG -rdynamic -lpthread'}],
    'xmalloc-test' => [{'binary' => 'out/bench/xmalloc-test', 'option' => '-march=native -w -Wno-implicit-function-declaration -Wno-implicit-int -Wno-int-conversion -O3 -DNDEBUG -rdynamic -lpthread'}],
}

for mimalloc_test in build_tests
    build('/app/', mimalloc_test)
end

build_binaries.each do | test, binaries|
    binaries.each do |binary|
        extract_and_convert('/app/', binary['binary'], binary['option'])
    end
end

build_ruby()
