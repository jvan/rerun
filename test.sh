#!/bin/bash
#
# Run some tests on rerun.
#

# Helper to check output from macros
check() {
   local cmd=$1; shift
   echo -n '***' $cmd 'result: ' >&2
   while read; do
      (($#==0)) && { echo "failed (extra output)." >&2; return 1; } 
      (($1==$REPLY)) || { echo "failed ($1 != $REPLY)." >&2; return 1; }
      shift
   done <<<"$($cmd)"
   (($#==0)) || { echo "failed (more output expected)." >&2; return 1; }
   echo "okay." >&2
}

# Establish some history
set -o history
echo 1
echo 2
echo 3
echo 4
echo 5
set +o history

# Bring in rerun
PS1=" " # Fake out rerun into thinking we're interactive
source rerun.sh

# Creation from list
t=create_from_list
rerun create $t 1 4 3 2 5
check $t 1 4 3 2 5

# Creation from range
t=create_from_range
rerun create $t 1-5
check $t 1 2 3 4 5

# Creation from start:count
t=create_from_start_and_count
rerun create $t 1:5
check $t 1 2 3 4 5

# Creation from include spec
t=create_from_include_spec
rerun create $t 1.--.
check $t 1 2 5
