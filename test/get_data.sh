#!/bin/sh

mkdir data

prefix='http://www.biodalliance.org/datasets/'
for f in spermMethylation.bw; do
  echo "Getting $f"
  wget $prefix$f -nd -P data
done
