import subprocess
import os
from datetime import datetime
import time
import sys
import json
import signal


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
        # 'nginx': 'nginx',
        # 'lighttpd': 'light',
        'redis': 'redis'
    }

    cmds = {
        'nginx': '',
        'lighttpd': '-D -f /home/cscf-loan/test.conf',
        'redis': ''
    }

    preloads = {
        # 'tat': ' ',
        'glibc': ' '
    }

    now = datetime.now()
    output_base = '/home/cscf-loan/test/semalloc/output/'
    cur_time = now.strftime("%m-%d-%H-%M-%S")

    try:
        os.makedirs(output_base + cur_time)
    except FileExistsError:
        pass

    for test in binaries.keys():
        exe_name = binaries[test].split('/')[-1]

        for preload in preloads.keys():
            e = os.environ.copy()

            if 'tat' in preload:
                e['LD_LIBRARY_PATH'] = '/home/cscf-loan/test/type-after-type/autosetup.dir/install/tat-heap-inline/lib:/home/cscf-loan/test/type-after-type/autosetup.dir/install/common/lib'
            else:
                e['LD_LIBRARY_PATH'] = '/home/cscf-loan/test/type-after-type/autosetup.dir/install/baseline-lto/lib:/home/cscf-loan/test/type-after-type/autosetup.dir/install/common/lib'

            if preload == 'tat':
                binary_p = 'inline'
            else:
                binary_p = 'regular'

            # run test
            exe_cmd = '/home/cscf-loan/test/tat_input/' + exe_name + '_' + binary_p +  ' ' + cmds[test]
            print(exe_cmd)
            try:
                process = subprocess.Popen(['python3', '/home/cscf-loan/test/semalloc/benchmark/assets/invoker.py', str(
                    exe_cmd), '/home/cscf-loan', json.dumps(e)], stdout=subprocess.PIPE)
                out, _ = process.communicate()
                out = out.decode('utf-8')
            except KeyboardInterrupt:
                process.send_signal(signal.SIGINT)
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
    for i in range(1):
        profile()
