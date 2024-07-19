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
    tests = [
        '600.perlbench_s',
        '602.gcc_s',
        '605.mcf_s',
        '619.lbm_s',
        '620.omnetpp_s',
        '623.xalancbmk_s',
 #       '625.x264_s',
        '631.deepsjeng_s',
        '638.imagick_s',
        '641.leela_s',
        '644.nab_s',
        '657.xz_s',
    ]

    exe_names = {
        '600': 'perlbench_s_base.mytest',
        '602': 'sgcc_base.mytest',
        '605': 'mcf_s_base.mytest',
        '619': 'lbm_s_base.mytest',
        '620': 'omnetpp_s_base.mytest',
        '623': 'xalancbmk_s_base.mytest',
        '625': 'x264_s_base.mytest',
        '631': 'deepsjeng_s_base.mytest',
        '638': 'imagick_s_base.mytest',
        '641': 'leela_s_base.mytest',
        '644': 'nab_s_base.mytest',
        '657': 'xz_s_base.mytest'
    }

    cmds = {
        '600': [
            '-I./lib ./checkspam.pl 2500 5 25 11 150 1 1 1 1',
            '-I./lib ./diffmail.pl 4 800 10 17 19 300',
            '-I./lib ./splitmail.pl 6400 12 26 16 100 0'
            ],
        '602': [
            'gcc-pp.c -O5 -fipa-pta -o gcc-pp.opts-O5_-fipa-pta.s',
            'gcc-pp.c -O5 -finline-limit=1000 -fselective-scheduling -fselective-scheduling2 -o gcc-pp.opts-O5_-finline-limit_1000_-fselective-scheduling_-fselective-scheduling2.s',
            'gcc-pp.c -O5 -finline-limit=24000 -fgcse -fgcse-las -fgcse-lm -fgcse-sm -o gcc-pp.opts-O5_-finline-limit_24000_-fgcse_-fgcse-las_-fgcse-lm_-fgcse-sm.s'
            ],
        '605': ['inp.in'],
        '619': ['2000 reference.dat 0 0 200_200_260_ldc.of'],
        '620': ['-c General -r 0'],
        '623': ['-v t5.xml xalanc.xsl'],
        '625': [
            '--pass 1 --stats x264_stats.log --bitrate 1000 --frames 1000 -o BuckBunny_New.264 BuckBunny.yuv 1280x720',
            '--pass 2 --stats x264_stats.log --bitrate 1000 --dumpyuv 200 --frames 1000 -o BuckBunny_New.264 BuckBunny.yuv 1280x720',
            '--seek 500 --dumpyuv 200 --frames 1250 -o BuckBunny_New.264 BuckBunny.yuv 1280x720'
            ],
        '631': ['ref.txt'],
        '638': ['-limit disk 0 refspeed_input.tga -resize 817% -rotate -2.76 -shave 540x375 -alpha remove -auto-level -contrast-stretch 1x1% -colorspace Lab -channel R -equalize +channel -colorspace sRGB -define histogram:unique-colors=false -adaptive-blur 0x5 -despeckle -auto-gamma -adaptive-sharpen 55 -enhance -brightness-contrast 10x10 -resize 30% refspeed_output.tga'],
        '641': ['ref.sgf'],
        '644': ['3j1n 20140317 220'],
        '657': [
            'cpu2006docs.tar.xz 6643 055ce243071129412e9dd0b3b69a21654033a9b723d874b2015c774fac1553d9713be561ca86f74e4f16f22e664fc17a79f30caa5ad2c04fbc447549c2810fae 1036078272 1111795472 4',
            'cld.tar.xz 1400 19cf30ae51eddcbefda78dd06014b4b96281456e078ca7c13e1c0c9e6aaea8dff3efb4ad6b0456697718cede6bd5454852652806a657bb56e07d61128434b474 536995164 539938872 8'
            ]
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

    for test in tests:
        test_id = test.split('.')[0]
        exe = exe_names[test_id]

        for preload in preloads.keys():
            # move exes
            if 'semalloc' in preload:
                target = '/app/semalloc/test/input/' + exe + '.out'
            else:
                target = '/app/semalloc/test/input/' + exe + '.regular'

            run_dir = '/app/spec/benchspec/CPU/' + test + '/run/run_base_refspeed_mytest.0000/'

            max_rss = 0
            sum_utime = 0
            sum_stime = 0

            for cur_cmd in cmds[test_id]:
                exe_cmd = 'LD_PRELOAD=' + preloads[preload] + ' ' + target + ' ' + cur_cmd 
                print(exe_cmd)

                process = subprocess.Popen(['python3', '/app/semalloc/benchmark/assets/invoker.py', str(
                    exe_cmd), str(run_dir), json.dumps({'OMP_NUM_THREADS': '4'})], stdout=subprocess.PIPE)

                out, _ = process.communicate()
                out = out.decode('utf-8')

                output = out + '\n\n*****************************\n\n'
                print(output)

                filename = test_id + '-' + preload + '.log'
                with open(output_base + cur_time + '/' + filename, 'a') as file:
                    file.write(output)

                time.sleep(1)
                make_curl(output_base + cur_time + '/' +
                        filename, cur_time + filename)


if __name__ == '__main__':
    for i in range(5):
        profile()
