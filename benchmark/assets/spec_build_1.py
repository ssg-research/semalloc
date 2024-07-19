import subprocess
import os
from datetime import datetime
import time
import sys


def build():
    tests = [
        '600',
        '602',
        '605',
        '619',
        '620',
        '623',
        '625',
        '631',
        '638',
        '641',
        '644',
        '657'
    ]

    for test in tests:
        # build
        process = subprocess.Popen('LLVM_COMPILER=clang LLVM_COMPILER_PATH=/app/llvm15/build/bin/ runcpu --config semalloc --action runsetup --tune base ' +
                                   test, stdout=subprocess.PIPE, stderr=subprocess.PIPE, shell=True)
        out, err = process.communicate()
        out = out.decode('utf-8')
        err = err.decode('utf-8')

        print(err)
        print(out)
    

if __name__ == '__main__':
    build()
