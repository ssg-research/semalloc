import subprocess
import os
from datetime import datetime
import time
import sys
import json


def make_curl(file, filename):
    cmd = ''
    process = subprocess.Popen(cmd, shell=True)
    out, err = process.communicate()
    try:
        print(out.decode('utf-8'))
        print(err.decode('utf-8'))
    except Exception:
        pass


def profile():
    binaries = {
        'alloc-test': 'out/bench/alloc-test',
        'cscratch': 'out/bench/cache-scratch',
        'cthrash': 'out/bench/cache-thrash',
        'glibc-simple': 'out/bench/glibc-simple',
        'malloc-large': 'out/bench/malloc-large',
        'rptest': 'out/bench/rptest',
        'mstress': 'out/bench/mstress',
        'rbstress': 'ruby',
        'sh6bench': 'out/bench/sh6bench',
        'sh8bench': 'out/bench/sh8bench',
        'xmalloc-test': 'out/bench/xmalloc-test',
    }

    cmds = {
        'alloc-test': '1',
        'cscratch': '1 1000 1 2000000 1',
        'cthrash': '1 1000 1 2000000 1',
        'glibc-simple': '',
        'malloc-large': '',
        'rptest': '1 0 1 2 500 1000 100 8 16000',
        'mstress': '1 50 20',
        'rbstress': '/app/mimalloc-bench/bench/rbstress/stress_mem.rb 1',
        'sh6bench': '2',
        'sh8bench': '2',
        'xmalloc-test': '-w 1 -t 5 -s 64',
    }

    preloads = {
        'semalloc': '/app/semalloc/backend/build/lib/libsemalloc.so ',
        'glibc': ' ',
        'markus': '"/app/markus/lib/libgc.so /app/markus/lib/libgccpp.so" ',
        'ffmalloc': '/app/ffmalloc/libffmallocnpmt.so '
    }

    now = datetime.now()
    output_base = '/app/semalloc/output/'
    cur_time = now.strftime("%m-%d-%H-%M-%S")

    try:
        os.makedirs(output_base + cur_time)
    except FileExistsError:
        pass

    for test in binaries.keys():
        exe_name = binaries[test].split('/')[-1]

        for preload in preloads.keys():
            if preload == 'semalloc':
                binary_su = '.out'
            else:
                binary_su = '.regular'

            if preload == 'markus' and test == 'sh8bench':
                continue

            # run test
            exe_cmd = 'LD_PRELOAD=' + preloads[preload] + ' /app/semalloc/test/input/' + exe_name + binary_su + ' ' + cmds[test]
            print(exe_cmd)

            process = subprocess.Popen(['python3', '/app/semalloc/benchmark/assets/invoker.py', str(
                exe_cmd), '/app', json.dumps({})], stdout=subprocess.PIPE)
            out, _ = process.communicate()
            out = out.decode('utf-8')

            output = out + '\n\n*****************************\n\n'
            print(output)

            filename = test + '-' + preload + '.log'
            with open(output_base + cur_time + '/' + filename, 'w+') as file:
                file.write(output)

            time.sleep(1)
            make_curl(output_base + cur_time + '/' +
                        filename, cur_time + filename)


if __name__ == '__main__':
    for i in range(5):
        profile()
