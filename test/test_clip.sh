#!/bin/bash

#####
#	SET PATH TO HDEF EXECUTABLE
#####
# Check if clip is set in PATH
if [ "$BIN_DIR" == "" ]
then
    BIN_DIR=$(which clip | xargs dirname)
fi

# Check for clip in same directory as script
if [ "$BIN_DIR" == "" ]
then
    BIN_DIR=$(which $(dirname $0)/clip | xargs dirname)
fi

# Check for clip in relative directory ../bin (assumes script is in Hdef/dir)
if [ "$BIN_DIR" == "" ]
then
    BIN_DIR=$(which $(dirname $0)/../bin/clip | xargs dirname)
fi

# Check for clip in relative directory ../build (assumes script is in Hdef/dir)
if [ "$BIN_DIR" == "" ]
then
    BIN_DIR=$(which $(dirname $0)/../build/clip | xargs dirname)
fi

# Hdef executables are required!
if [ "$BIN_DIR" == "" ]
then
    echo "$0: unable to find Hdef executable clip; exiting" 1>&2
    exit 1
fi


#####
#	SET PATH TO TEST_VALUES SCRIPT
#####
TEST_BIN_DIR=`echo $0 | xargs dirname`


#####
#	RUN TEST
#####
cat > polygon.tmp << EOF
0 0
3 0
4 4
5 6
2 8
0 3
EOF

cat > points.tmp << EOF
  -1.0000000000000000       -1.0000000000000000
  -1.0000000000000000        0.0000000000000000
  -1.0000000000000000        1.0000000000000000
  -1.0000000000000000        2.0000000000000000
  -1.0000000000000000        3.0000000000000000
  -1.0000000000000000        4.0000000000000000
  -1.0000000000000000        5.0000000000000000
  -1.0000000000000000        6.0000000000000000
  -1.0000000000000000        7.0000000000000000
  -1.0000000000000000        8.0000000000000000
  -1.0000000000000000        9.0000000000000000
   0.0000000000000000       -1.0000000000000000
   0.0000000000000000        0.0000000000000000
   0.0000000000000000        1.0000000000000000
   0.0000000000000000        2.0000000000000000
   0.0000000000000000        3.0000000000000000
   0.0000000000000000        4.0000000000000000
   0.0000000000000000        5.0000000000000000
   0.0000000000000000        6.0000000000000000
   0.0000000000000000        7.0000000000000000
   0.0000000000000000        8.0000000000000000
   0.0000000000000000        9.0000000000000000
   1.0000000000000000       -1.0000000000000000
   1.0000000000000000        0.0000000000000000
   1.0000000000000000        1.0000000000000000
   1.0000000000000000        2.0000000000000000
   1.0000000000000000        3.0000000000000000
   1.0000000000000000        4.0000000000000000
   1.0000000000000000        5.0000000000000000
   1.0000000000000000        6.0000000000000000
   1.0000000000000000        7.0000000000000000
   1.0000000000000000        8.0000000000000000
   1.0000000000000000        9.0000000000000000
   2.0000000000000000       -1.0000000000000000
   2.0000000000000000        0.0000000000000000
   2.0000000000000000        1.0000000000000000
   2.0000000000000000        2.0000000000000000
   2.0000000000000000        3.0000000000000000
   2.0000000000000000        4.0000000000000000
   2.0000000000000000        5.0000000000000000
   2.0000000000000000        6.0000000000000000
   2.0000000000000000        7.0000000000000000
   2.0000000000000000        8.0000000000000000
   2.0000000000000000        9.0000000000000000
   3.0000000000000000       -1.0000000000000000
   3.0000000000000000        0.0000000000000000
   3.0000000000000000        1.0000000000000000
   3.0000000000000000        2.0000000000000000
   3.0000000000000000        3.0000000000000000
   3.0000000000000000        4.0000000000000000
   3.0000000000000000        5.0000000000000000
   3.0000000000000000        6.0000000000000000
   3.0000000000000000        7.0000000000000000
   3.0000000000000000        8.0000000000000000
   3.0000000000000000        9.0000000000000000
   4.0000000000000000       -1.0000000000000000
   4.0000000000000000        0.0000000000000000
   4.0000000000000000        1.0000000000000000
   4.0000000000000000        2.0000000000000000
   4.0000000000000000        3.0000000000000000
   4.0000000000000000        4.0000000000000000
   4.0000000000000000        5.0000000000000000
   4.0000000000000000        6.0000000000000000
   4.0000000000000000        7.0000000000000000
   4.0000000000000000        8.0000000000000000
   4.0000000000000000        9.0000000000000000
   5.0000000000000000       -1.0000000000000000
   5.0000000000000000        0.0000000000000000
   5.0000000000000000        1.0000000000000000
   5.0000000000000000        2.0000000000000000
   5.0000000000000000        3.0000000000000000
   5.0000000000000000        4.0000000000000000
   5.0000000000000000        5.0000000000000000
   5.0000000000000000        6.0000000000000000
   5.0000000000000000        7.0000000000000000
   5.0000000000000000        8.0000000000000000
   5.0000000000000000        9.0000000000000000
   6.0000000000000000       -1.0000000000000000
   6.0000000000000000        0.0000000000000000
   6.0000000000000000        1.0000000000000000
   6.0000000000000000        2.0000000000000000
   6.0000000000000000        3.0000000000000000
   6.0000000000000000        4.0000000000000000
   6.0000000000000000        5.0000000000000000
   6.0000000000000000        6.0000000000000000
   6.0000000000000000        7.0000000000000000
   6.0000000000000000        8.0000000000000000
   6.0000000000000000        9.0000000000000000
EOF

$BIN_DIR/clip polygon.tmp -f points.tmp -in -o inside.tmp
cat > answer.tmp << EOF
    1.0000000000000000        1.0000000000000000
    1.0000000000000000        2.0000000000000000
    1.0000000000000000        3.0000000000000000
    1.0000000000000000        4.0000000000000000
    1.0000000000000000        5.0000000000000000
    2.0000000000000000        1.0000000000000000
    2.0000000000000000        2.0000000000000000
    2.0000000000000000        3.0000000000000000
    2.0000000000000000        4.0000000000000000
    2.0000000000000000        5.0000000000000000
    2.0000000000000000        6.0000000000000000
    2.0000000000000000        7.0000000000000000
    3.0000000000000000        1.0000000000000000
    3.0000000000000000        2.0000000000000000
    3.0000000000000000        3.0000000000000000
    3.0000000000000000        4.0000000000000000
    3.0000000000000000        5.0000000000000000
    3.0000000000000000        6.0000000000000000
    3.0000000000000000        7.0000000000000000
    4.0000000000000000        5.0000000000000000
    4.0000000000000000        6.0000000000000000
EOF
$TEST_BIN_DIR/test_values.sh inside.tmp answer.tmp 2 "clip: points inside polygon" || exit 1

$BIN_DIR/clip polygon.tmp -f points.tmp -out -o outside.tmp
cat > answer.tmp << EOF
   -1.0000000000000000       -1.0000000000000000
   -1.0000000000000000        0.0000000000000000
   -1.0000000000000000        1.0000000000000000
   -1.0000000000000000        2.0000000000000000
   -1.0000000000000000        3.0000000000000000
   -1.0000000000000000        4.0000000000000000
   -1.0000000000000000        5.0000000000000000
   -1.0000000000000000        6.0000000000000000
   -1.0000000000000000        7.0000000000000000
   -1.0000000000000000        8.0000000000000000
   -1.0000000000000000        9.0000000000000000
    0.0000000000000000       -1.0000000000000000
    0.0000000000000000        4.0000000000000000
    0.0000000000000000        5.0000000000000000
    0.0000000000000000        6.0000000000000000
    0.0000000000000000        7.0000000000000000
    0.0000000000000000        8.0000000000000000
    0.0000000000000000        9.0000000000000000
    1.0000000000000000       -1.0000000000000000
    1.0000000000000000        6.0000000000000000
    1.0000000000000000        7.0000000000000000
    1.0000000000000000        8.0000000000000000
    1.0000000000000000        9.0000000000000000
    2.0000000000000000       -1.0000000000000000
    2.0000000000000000        9.0000000000000000
    3.0000000000000000       -1.0000000000000000
    3.0000000000000000        8.0000000000000000
    3.0000000000000000        9.0000000000000000
    4.0000000000000000       -1.0000000000000000
    4.0000000000000000        0.0000000000000000
    4.0000000000000000        1.0000000000000000
    4.0000000000000000        2.0000000000000000
    4.0000000000000000        3.0000000000000000
    4.0000000000000000        7.0000000000000000
    4.0000000000000000        8.0000000000000000
    4.0000000000000000        9.0000000000000000
    5.0000000000000000       -1.0000000000000000
    5.0000000000000000        0.0000000000000000
    5.0000000000000000        1.0000000000000000
    5.0000000000000000        2.0000000000000000
    5.0000000000000000        3.0000000000000000
    5.0000000000000000        4.0000000000000000
    5.0000000000000000        5.0000000000000000
    5.0000000000000000        7.0000000000000000
    5.0000000000000000        8.0000000000000000
    5.0000000000000000        9.0000000000000000
    6.0000000000000000       -1.0000000000000000
    6.0000000000000000        0.0000000000000000
    6.0000000000000000        1.0000000000000000
    6.0000000000000000        2.0000000000000000
    6.0000000000000000        3.0000000000000000
    6.0000000000000000        4.0000000000000000
    6.0000000000000000        5.0000000000000000
    6.0000000000000000        6.0000000000000000
    6.0000000000000000        7.0000000000000000
    6.0000000000000000        8.0000000000000000
    6.0000000000000000        9.0000000000000000
EOF
$TEST_BIN_DIR/test_values.sh outside.tmp answer.tmp 2 "clip: points outside polygon" || exit 1

$BIN_DIR/clip polygon.tmp -f points.tmp -on 1.0e-2 -o on.tmp
cat > answer.tmp << EOF
    0.0000000000000000        0.0000000000000000
    0.0000000000000000        1.0000000000000000
    0.0000000000000000        2.0000000000000000
    0.0000000000000000        3.0000000000000000
    1.0000000000000000        0.0000000000000000
    2.0000000000000000        0.0000000000000000
    2.0000000000000000        8.0000000000000000
    3.0000000000000000        0.0000000000000000
    4.0000000000000000        4.0000000000000000
    5.0000000000000000        6.0000000000000000
EOF
$TEST_BIN_DIR/test_values.sh on.tmp answer.tmp 2 "clip: points on polygon" || exit 1

# PSFILE="test_clip.ps"
# PROJ="-Jx0.5i -P"
# LIMS="-R-1.5/6.5/-1.5/9.5"
#
# echo 0 0 | gmt psxy $PROJ $LIMS -K --PS_MEDIA=8.5ix11i > $PSFILE
# gmt psxy points.tmp $PROJ $LIMS -Gblack -Sc0.1i -K -O >> $PSFILE
# gmt psxy polygon.tmp $PROJ $LIMS -W1p -K -O >> $PSFILE
# gmt psxy inside.tmp $PROJ $LIMS -G105/0/0 -Sc0.15i -K -O >> $PSFILE
# gmt psxy outside.tmp $PROJ $LIMS -G185/55/105 -Sc0.15i -K -O >> $PSFILE
# gmt psxy on.tmp $PROJ $LIMS -G185/105/255 -Sc0.25i -K -O >> $PSFILE
# gmt psbasemap $PROJ $LIMS -Bxa1 -Bya1 -K -O >> $PSFILE
# echo 0 0 | gmt psxy $PROJ $LIMS -O >> $PSFILE
#
# ps2pdf $PSFILE
# rm gmt.*
# rm $PSFILE
# rm *.tmp
