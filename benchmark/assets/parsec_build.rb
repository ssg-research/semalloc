#!/usr/bin/ruby -w

def build_and_convert(global_prefix='/app/', arch_prefix, parsec_test, build_cmd)
    test_arr = parsec_test.split('/')
    test_dir = test_arr[0]
    test_name = test_arr[1]

    env = {"LLVM_COMPILER" => "clang", "LLVM_COMPILER_PATH" => "#{global_prefix}llvm15/build/bin/"}
    source_path = "#{global_prefix}parsec/pkgs/#{test_dir}/#{test_name}/inst/#{arch_prefix}-linux.gcc/bin/#{test_name}"
    css_path = "#{global_prefix}semalloc/"

    puts "Converting #{test_name} at #{source_path}"
    system(env, "extract-bc #{source_path}")
    system(env, "#{css_path}frontend/build/lib/kanalyzer #{source_path}.bc", :out => ["#{css_path}/output/build/#{test_name}.log", "a"], :err => ["#{css_path}/output/build/#{test_name}.log", "a"])

    puts "Building #{test_name} regular and converted"
    system(env, "#{global_prefix}llvm15/build/bin/clang++ #{source_path}.bc -L#{global_prefix}/semalloc/frontend/build/lib/ -lBuildSupport #{build_cmd} -o  #{css_path}test/input/#{test_name}.regular")
    system(env, "#{global_prefix}llvm15/build/bin/clang++ #{css_path}test/input/output.bc -L#{global_prefix}/semalloc/frontend/build/lib/ -lBuildSupport #{build_cmd} -o  #{css_path}test/input/#{test_name}.out")
end


arch = `arch`
if arch == "x86_64\n"
    tests = [
        'apps/blackscholes',
        'apps/bodytrack',
        'kernels/canneal',
        'kernels/dedup',
        # 'apps/facesim',
        'apps/ferret',
        'apps/fluidanimate',
        'apps/freqmine',
        # 'apps/raytrace',
        'kernels/streamcluster',
        'apps/swaptions',
        'apps/vips'
    ]

    build_cmds = {
        'apps/blackscholes' => '-fpermissive -fno-exceptions -std=c++17 -lpthread -DENABLE_THREADS -DNCO=4',
        'apps/bodytrack' => '-fpermissive -fno-exceptions -std=c++17 -fexceptions -Wall -Wno-unknown-pragmas -lm -lpthread',
        'kernels/canneal' => '-fpermissive -fno-exceptions -std=c++17 -DENABLE_THREADS -pthread -lm',
        'kernels/dedup' => '-Wall -fno-strict-aliasing -D_XOPEN_SOURCE=600 -DENABLE_GZIP_COMPRESSION -DENABLE_PTHREADS -pthread -lm -lz',
        # 'apps/facesim' => '',
        'apps/ferret' => '-lrt -lm -lstdc++ -lpthread',
        'apps/fluidanimate' => '-fpermissive -fno-exceptions -std=c++17 -Wno-invalid-offsetof -pthread -D_GNU_SOURCE -D__XOPEN_SOURCE=600',
        'apps/freqmine' => '-fpermissive -fno-exceptions -std=c++17 -fopenmp -Wno-deprecated -O2',
        # 'apps/raytrace' => '',
        'kernels/streamcluster' => '-fpermissive -fno-exceptions -std=c++17 -DENABLE_THREADS -pthread',
        'apps/swaptions' => '-fpermissive -fno-exceptions -std=c++17 -pthread   -DENABLE_THREADS',
        'apps/vips' => '-pthread -ldl'
    }

    ARCH_PREFIX = "amd64"
else
    tests = [
        'apps/blackscholes',
        'apps/bodytrack',
        'kernels/canneal',
        'kernels/dedup',
        # 'apps/facesim',
        'apps/ferret',
        'apps/fluidanimate',
        'apps/freqmine',
        'kernels/streamcluster',
        'apps/swaptions',
        'apps/vips'
    ]

    build_cmds = {
        'apps/blackscholes' => '-fpermissive -fno-exceptions -std=c++17 -lpthread -DENABLE_THREADS -DNCO=4',
        'apps/bodytrack' => '-fpermissive -fno-exceptions -std=c++17 -fexceptions -Wall -Wno-unknown-pragmas -lm -lpthread',
        'kernels/canneal' => '-fpermissive -fno-exceptions -std=c++17 -DENABLE_THREADS -pthread -lm',
        'kernels/dedup' => '-Wall -fno-strict-aliasing -D_XOPEN_SOURCE=600 -DENABLE_GZIP_COMPRESSION -DENABLE_PTHREADS -pthread -lm -lz',
        # 'apps/facesim' => '',
        'apps/ferret' => '',
        'apps/fluidanimate' => '-fpermissive -fno-exceptions -std=c++17 -Wno-invalid-offsetof -pthread -D_GNU_SOURCE -D__XOPEN_SOURCE=600',
        'apps/freqmine' => '-fpermissive -fno-exceptions -std=c++17 -fopenmp -Wno-deprecated -O2',
        'kernels/streamcluster' => '-fpermissive -fno-exceptions -std=c++17 -DENABLE_THREADS -pthread',
        'apps/swaptions' => '-fpermissive -fno-exceptions -std=c++17 -pthread   -DENABLE_THREADS',
        'apps/vips' => ''
    }

    ARCH_PREFIX = "aarch64"
end

for parsec_test in tests
    build_and_convert(ARCH_PREFIX, parsec_test, build_cmds[parsec_test])
end

