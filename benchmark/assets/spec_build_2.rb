#!/usr/bin/ruby -w
def convert_spec(global_prefix='/app/', spec_test, build_cmd, exe_name)
    test_arr = spec_test.split('.')
    test_id = test_arr[0]
    
    env = {"LLVM_COMPILER" => "clang", "LLVM_COMPILER_PATH" => "#{global_prefix}/llvm15/build/bin/"}

    puts "##################### Converting #{test_id} #####################"
    for exe in exe_name
        source_path = "#{global_prefix}spec/benchspec/CPU/#{spec_test}/exe/#{exe}"
        css_path = "#{global_prefix}semalloc/"

        puts "##################### Converting #{exe} #####################"
        system(env, "extract-bc #{source_path}")
        system(env, "#{css_path}frontend/build/lib/kanalyzer #{source_path}.bc", :out => ["#{css_path}/output/build/#{test_id}.log", "a"], :err => ["#{css_path}/output/build/#{test_id}.log", "a"])

        puts "###################### Building #{exe} ######################"
        system(env, "#{global_prefix}llvm15/build/bin/clang++ #{source_path}.bc -L#{global_prefix}/semalloc/frontend/build/lib/ -lBuildSupport #{build_cmd} -o #{css_path}test/input/#{exe}.regular")
        system(env, "#{global_prefix}llvm15/build/bin/clang++ #{css_path}test/input/output.bc -L#{global_prefix}/semalloc/frontend/build/lib/ -lBuildSupport  #{build_cmd} -o #{css_path}test/input/#{exe}.out")
    end
end


tests = [
    '600.perlbench_s',
    '602.gcc_s',
    '605.mcf_s',
    '619.lbm_s',
    '620.omnetpp_s',
    '623.xalancbmk_s',
    '625.x264_s',
    '631.deepsjeng_s',
    '638.imagick_s',
    '641.leela_s',
    '644.nab_s',
    '657.xz_s',
]

exe_names = {
    '600' => ['perlbench_s_base.mytest'],
    '602' => ['sgcc_base.mytest'],
    '605' => ['mcf_s_base.mytest'],
    '619' => ['lbm_s_base.mytest'],
    '620' => ['omnetpp_s_base.mytest'],
    '623' => ['xalancbmk_s_base.mytest'],
    '625' => ['x264_s_base.mytest'],
    '631' => ['deepsjeng_s_base.mytest'],
    '638' => ['imagick_s_base.mytest'],
    '641' => ['leela_s_base.mytest'],
    '644' => ['nab_s_base.mytest'],
    '657' => ['xz_s_base.mytest']
}

arch = `arch`
if arch == "x86_64\n"
    build_cmds = {
        '600' => '-std=c99 -g -O3 -DSPEC_LINUX_X64 -lm',
        '602' => '-std=c99 -gdwarf-4 -fgnu89-inline -g -O3 -lm',
        '605' => '-std=c99 -g -O3 -lm',
        '619' => '-std=c99 -g -O3 -lm',
        '620' => '-std=c99 -gdwarf-4 -g -O3',
        '623' => '-std=c++03 -g -O3 -DSPEC_LINUX',
        '625' => '-std=c99 -gdwarf-4 -g -O3 -lm',
        '631' => '-std=c++03 -g -O3',
        '638' => '-std=c99 -g -O3 -lm',
        '641' => '-std=c99 -g -O3',
        '644' => '-std=c99 -g -O3 -lm',
        '657' => '-std=c99 -g -O3',
    }
else
    build_cmds = {
        '600' => '',
        '602' => '',
        '605' => '',
        '619' => '',
        '620' => '',
        '623' => '',
        '625' => '',
        '631' => '',
        '638' => '',
        '641' => '',
        '644' => '',
        '657' => '',
    }
end

for spec_test in tests
    test_arr = spec_test.split('.')
    test_id = test_arr[0]
    convert_spec(spec_test, build_cmds[test_id], exe_names[test_id])
end

