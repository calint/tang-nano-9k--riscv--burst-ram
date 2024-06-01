#!/bin/sh
set -e
cd $(dirname "$0")

NUM_TESTS=9

for i in $(seq 1 $NUM_TESTS); do
    ./test-bench.sh sim_$i | grep -v -E "passed|readmemh|VCD|finish"
done
