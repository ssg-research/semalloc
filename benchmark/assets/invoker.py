import subprocess
import resource
import json
import sys
import time

def invoke(cmd, path, env):
    time1 = time.time()
    process = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=path, env=env, shell=True)
    out, err = process.communicate()
    time2 = time.time()
    t = time2 - time1
    out = out.decode('utf-8')
    err = err.decode('utf-8')

    max_rss_children = resource.getrusage(
        resource.RUSAGE_CHILDREN).ru_maxrss
    utime = resource.getrusage(resource.RUSAGE_CHILDREN).ru_utime
    stime = resource.getrusage(resource.RUSAGE_CHILDREN).ru_stime

    print(max_rss_children, utime, stime, t)


if __name__ == '__main__':
    invoke(sys.argv[1], sys.argv[2], json.loads(sys.argv[3]))
