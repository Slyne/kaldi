#!/bin/bash

# Copyright 2012 Karel Vesely

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
# WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
# MERCHANTABLITY OR NON-INFRINGEMENT.
# See the Apache 2 License for the specific language governing permissions and
# limitations under the License.

# Decoding script using pure-hybrid acoustic model, 
# using fbank features with cepstral mean normalization 
# and hamming-dct transform

numjobs=1
jobid=0
while [ 1 ]; do
  case $1 in
    -j)
      shift; numjobs=$1; jobid=$2;
      shift; shift;
      ;;
    --acoustic-scale)
      shift; acousticscale=$1; shift;
      ;;
    --prior-scale)
      shift; priorscale=$1; shift;
      ;;
    *)
      break
      ;;
  esac
done


# steps/decode_nnet.sh --acoustic-scale 0.176275 -j 10 2 exp/mono1a/graph_tgpr data/test_dev93 /mnt/matylda5/iveselyk/DEVEL/kaldi/sandbox/karel/egs/wsj/s2_based_s3.run/exp/mono1a_nnet/decode_tgpr_dev93

if [ $# != 3 ]; then
   echo "Usage: steps/decode_deltas.sh [-j num-jobs job-number] <graph-dir> <data-dir> <decode-dir>"
   echo " e.g.: steps/decode_deltas.sh -j 8 0 exp/mono/graph_tgpr data/test_feb89 exp/mono/decode_feb89"
   exit 1;
fi

graphdir=$1
data=$2
#lang=$4
dir=$3
srcdir=`dirname $dir`; # Assume model directory one level up from decoding directory.

######## CONFIGURATION
beam=30
norm_vars=false #false:CMN, true:CMVN on fbanks
splice_lr=15   #left- and right-splice value
transf=$srcdir/hamm_dct.mat
cmvn_g=$srcdir/cmvn_glob.mat
priors=$srcdir/cur.counts
nnet=$srcdir/final.nnet
########

mkdir -p $dir

if [ -f path.sh ]; then . path.sh; fi

if [ $numjobs -gt 1 ]; then
  mydata=$data/split$numjobs/$jobid
else
  mydata=$data
fi

requirements="$mydata/feats.scp $srcdir/final.nnet $srcdir/final.mdl $graphdir/HCLG.fst"
for f in $requirements; do
  if [ ! -s $f ]; then
     echo "decode_deltas.sh: no such file $f";
     exit 1;
  fi
done


# prepare features
# We only do one decoding pass, so there is no point caching the
# CMVN stats-- we make them part of a pipe.
feats="ark:compute-cmvn-stats --spk2utt=ark:$mydata/spk2utt scp:$mydata/feats.scp ark:- | apply-cmvn --norm-vars=$norm_vars --utt2spk=ark:$mydata/utt2spk ark:- scp:$mydata/feats.scp ark:- |"
# Splice+Hamming+DCT
feats="$feats splice-feats --print-args=false --left-context=$splice_lr --right-context=$splice_lr ark:- ark:- | transform-feats --print-args=false $transf ark:- ark:- |"
# Norm+MLP
feats="$feats apply-cmvn --print-args=false --norm-vars=true $cmvn_g ark:- ark:- | nnet-forward --silent=true --print-args=false --apply-log=true --class-frame-counts=$priors ${priorscale:+--prior-scale=$priorscale} $nnet ark:- ark:- |"

latgen-faster-mapped --max-active=7000 --beam=13.0 --lattice-beam=6.0 --acoustic-scale=${acousticscale:-0.1429} \
  --allow-partial=true --word-symbol-table=$graphdir/words.txt \
  $srcdir/final.mdl $graphdir/HCLG.fst "$feats" "ark:|gzip -c > $dir/lat.$jobid.gz" \
     2> $dir/decode$jobid.log || exit 1;


