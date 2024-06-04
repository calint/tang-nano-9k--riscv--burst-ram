#!/bin/sh
# tools:
#   iverilog: Icarus Verilog version 12.0 (stable)
#        vvp: Icarus Verilog runtime version 12.0 (stable)
set -e
cd $(dirname "$0")

SIMPTH="$1"
TB=TestBench.v
SRCPTH=../../src

cd $SIMPTH
echo $SIMPTH

# switch for system verilog
# -g2005-sv 

iverilog -Winfloop -pfileline=1 -o iverilog.vvp \
    $TB \
    $SRCPTH/BurstRAM.v \
    $SRCPTH/CacheInstructions.v \
    $SRCPTH/CacheData.v \
    $SRCPTH/Cache.v \
    $SRCPTH/UartTx.v \
    $SRCPTH/UartRx.v \
    $SRCPTH/RAMIO.v \
    $SRCPTH/Registers.v \
    $SRCPTH/SoC.v

vvp iverilog.vvp
rm iverilog.vvp
