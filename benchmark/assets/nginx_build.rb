#!/usr/bin/ruby -w

def build_and_convert_nginx(global_prefix='/app/')
    env = {
        "LLVM_COMPILER" => "clang",
        "LLVM_COMPILER_PATH" => "#{global_prefix}llvm15/build/bin/",
        "CC" => "wllvm",
        "CXX" => "wllvm++",
        "CFLAGS" => "-Xclang -no-opaque-pointers -Xclang -mno-constructor-aliases",
        "CXXFLAGS" => "-Xclang -no-opaque-pointers -Xclang -mno-constructor-aliases"
    }
    
    source_path = "#{global_prefix}nginx"
    css_path = "#{global_prefix}semalloc/"
    binary_path = "#{source_path}/objs/nginx"

    Dir.chdir("#{source_path}")
    
    # build nginx
    system(env, "#{source_path}/auto/configure")
    system(env, "make")

    system(env, "extract-bc #{binary_path}")
    system(env, "#{css_path}frontend/build/lib/kanalyzer #{binary_path}.bc")
    system(env, "#{global_prefix}llvm15/build/bin/clang++ #{css_path}test/input/output.bc -L#{global_prefix}/semalloc/frontend/build/lib/ -lBuildSupport -fpermissive -fno-exceptions -std=c++17 -ldl -lpthread -lcrypt -lpcre -lz -DENABLE_THREADS -lpcre2-8 -o  #{css_path}test/input/nginx.out")
    
    system("mv #{global_prefix}nginx/objs/nginx #{global_prefix}nginx/objs/nginx_old")
    system("mv #{css_path}test/input/nginx.out #{global_prefix}nginx/objs/nginx")
    system(env, "make install")
end


def clone_nginx(global_prefix='/app/')
    system("mkdir -p #{global_prefix}nginx")
    system("git clone https://github.com/nginx/nginx #{global_prefix}nginx")
end


def install_ab()
    system("apt-get install apache2-utils")
    system("ab -V")
end

clone_nginx()
build_and_convert_nginx()
install_ab()
