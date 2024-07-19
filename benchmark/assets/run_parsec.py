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


def profile(nthreads):

    tests = [
        'blackscholes',
        'bodytrack',
        'canneal',
        'dedup',
        'ferret',
        'fluidanimate',
        'freqmine',
        'streamcluster',
        'swaptions',
        'vips'
    ]

    cmds = {
        'blackscholes': '/app/semalloc/test/input/blackscholes.out {nthreads} in_10M.txt prices.txt'.format(nthreads=nthreads),
        'bodytrack': '/app/semalloc/test/input/bodytrack.out sequenceB_261 4 261 4000 5 0 {nthreads}'.format(nthreads=nthreads),
        'canneal': '/app/semalloc/test/input/canneal.out {nthreads} 15000 2000 2500000.nets 6000'.format(nthreads=nthreads),
        'dedup': '/app/semalloc/test/input/dedup.out -c -p -v -t {nthreads} -i FC-6-x86_64-disc1.iso -o output.dat.ddp'.format(nthreads=nthreads),
        'ferret': '/app/semalloc/test/input/ferret.out corel lsh queries 50 20 {nthreads} output.txt'.format(nthreads=nthreads),
        'fluidanimate': '/app/semalloc/test/input/fluidanimate.out {nthreads} 500 in_500K.fluid out.fluid'.format(nthreads=nthreads),
        'freqmine': '/app/semalloc/test/input/freqmine.out webdocs_250k.dat 11000',
        'streamcluster': '/app/semalloc/test/input/streamcluster.out 10 20 128 1000000 200000 5000 none output.txt {nthreads}'.format(nthreads=nthreads),
        'swaptions': '/app/semalloc/test/input/swaptions.out -ns 128 -sm 1000000 -nt {nthreads}'.format(nthreads=nthreads),
        'vips': '/app/semalloc/test/input/vips.out im_benchmark orion_18000x18000.v output.v',
    }

    cmds_regular = {
        'blackscholes': '/app/semalloc/test/input/blackscholes.regular {nthreads} in_10M.txt prices.txt'.format(nthreads=nthreads),
        'bodytrack': '/app/semalloc/test/input/bodytrack.regular sequenceB_261 4 261 4000 5 0 {nthreads}'.format(nthreads=nthreads),
        'canneal': '/app/semalloc/test/input/canneal.regular {nthreads} 15000 2000 2500000.nets 6000'.format(nthreads=nthreads),
        'dedup': '/app/semalloc/test/input/dedup.regular -c -p -v -t {nthreads} -i FC-6-x86_64-disc1.iso -o output.dat.ddp'.format(nthreads=nthreads),
        'ferret': '/app/semalloc/test/input/ferret.regular corel lsh queries 50 20 {nthreads} output.txt'.format(nthreads=nthreads),
        'fluidanimate': '/app/semalloc/test/input/fluidanimate.regular {nthreads} 500 in_500K.fluid out.fluid'.format(nthreads=nthreads),
        'freqmine': '/app/semalloc/test/input/freqmine.regular webdocs_250k.dat 11000',
        'streamcluster': '/app/semalloc/test/input/streamcluster.regular 10 20 128 1000000 200000 5000 none output.txt {nthreads}'.format(nthreads=nthreads),
        'swaptions': '/app/semalloc/test/input/swaptions.regular -ns 128 -sm 1000000 -nt {nthreads}'.format(nthreads=nthreads),
        'vips': '/app/semalloc/test/input/vips.regular im_benchmark orion_18000x18000.v output.v',
    }

    env_base = os.environ.copy()

    env_freqmine = env_base.copy()
    env_freqmine['OMP_NUM_THREADS'] = nthreads

    env_vips = env_base.copy()
    env_vips['IM_CONCURRENCY'] = nthreads

    envs = {
        'blackscholes': env_base,
        'bodytrack': env_base,
        'canneal': env_base,
        'dedup': env_base,
        'ferret': env_base,
        'fluidanimate': env_base,
        'freqmine': env_freqmine,
        'streamcluster': env_base,
        'swaptions': env_base,
        'vips': env_vips,
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

    run_dir = '/app/semalloc/benchmark/parsecio/'

    try:
        os.makedirs(output_base + cur_time)
    except FileExistsError:
        pass

    for test in tests:
        for preload in preloads.keys():
            if 'semalloc' in preload:
                cmd = 'LD_PRELOAD=' + preloads[preload] + cmds[test]
            else:
                cmd = 'LD_PRELOAD=' + preloads[preload] + cmds_regular[test]
                
            print(cmd)
            process = subprocess.Popen(['python3', '/app/semalloc/benchmark/assets/invoker.py', str(
                cmd), str(run_dir + test), json.dumps(envs[test])], stdout=subprocess.PIPE)
            out, _ = process.communicate()
            out = out.decode('utf-8')

            output = out + '\n\n*****************************\n\n'
            print(output)

            filename = test + '-' + preload + '.log'
            with open(output_base + cur_time + '/' + filename, 'a') as file:
                file.write(output)

            time.sleep(1)
            make_curl(output_base + cur_time + '/' +
                      filename, cur_time + filename)


if __name__ == '__main__':
    if len(sys.argv) == 1:
        nthreads = '1'
    else:
        nthreads = sys.argv[1]
    for i in range(5):
        profile(nthreads)
