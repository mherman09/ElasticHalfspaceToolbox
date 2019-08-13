#!/bin/bash

# Single x value
echo 1 > answer.tmp
../bin/grid -x 1 > grid.tmp
./test_values.sh grid.tmp answer.tmp 1 "grid: 1 x value" || exit 1

# Two x values
cat > answer.tmp << EOF
1
5
EOF
../bin/grid -x 1 5 -nx 2 > grid.tmp
./test_values.sh grid.tmp answer.tmp 1 "grid: 2 x values" || exit 1

# Three x values
cat > answer.tmp << EOF
1
3
5
EOF
../bin/grid -x 1 5 -dx 2 > grid.tmp
./test_values.sh grid.tmp answer.tmp 1 "grid: 3 x values" || exit 1

# x range, single y value
cat > answer.tmp << EOF
1 3
2 3
3 3
4 3
5 3
EOF
../bin/grid -x 1 5 -nx 5 -y 3 > grid.tmp
./test_values.sh grid.tmp answer.tmp 2 "grid: 5 x values, 1 y value" || exit 1

# x range, y range
cat > answer.tmp << EOF
1 3
1 4
1 5
5 3
5 4
5 5
EOF
../bin/grid -x 1 5 -nx 2 -y 3 5 -ny 3 > grid.tmp
./test_values.sh grid.tmp answer.tmp 2 "grid: 2 x values, 3 y values" || exit 1

# x range, y range, z range
cat > answer.tmp << EOF
1 9 5
1 9 10
1 8 5
1 8 10
2 9 5
2 9 10
2 8 5
2 8 10
EOF
../bin/grid -x 1 2 -nx 2 -y 9 8 -dy -1 -z 5 10 -dz 5 > grid.tmp
./test_values.sh grid.tmp answer.tmp 3 "grid: 2 x values, 2 y values, 2 z values" || exit 1

# Dipping grid (geographic)
cat > answer.tmp << EOF
 -0.10000000000000001      -0.10000000000000001        1.1975532251043023E-005
 -0.10000000000000001        0.0000000000000000       -7.8626686663908201     
 -0.10000000000000001       0.10000000000000001       -15.725333340931877     
   0.0000000000000000      -0.10000000000000001        7.8626686663908201     
   0.0000000000000000        0.0000000000000000        0.0000000000000000     
   0.0000000000000000       0.10000000000000001       -7.8626686663908192     
  0.10000000000000001      -0.10000000000000001        15.725333340931877     
  0.10000000000000001        0.0000000000000000        7.8626686663908192     
  0.10000000000000001       0.10000000000000001       -1.1975532249477095E-005
EOF
../bin/grid -x -0.1 0.1 -nx 3 -y -0.1 0.1 -ny 3 -dip 0 0 0 45 45 -geo > grid.tmp
./test_values.sh grid.tmp answer.tmp 3 "grid: dipping grid (geo)" || exit 1

# Dipping grid (cartesian)
cat > answer.tmp << EOF
  -1.0000000000000000       -1.0000000000000000       -1.4142135623730949     
  -1.0000000000000000        0.0000000000000000      -0.70710678118654735     
  -1.0000000000000000        1.0000000000000000        0.0000000000000000     
   0.0000000000000000       -1.0000000000000000      -0.70710678118654735     
   0.0000000000000000        0.0000000000000000        0.0000000000000000     
   0.0000000000000000        1.0000000000000000       0.70710678118654735     
   1.0000000000000000       -1.0000000000000000        0
   1.0000000000000000        0.0000000000000000       0.70710678118654746     
   1.0000000000000000        1.0000000000000000        1.4142135623730949
EOF
../bin/grid -x -1 1 -nx 3 -y -1 1 -ny 3 -dip 0 0 0 -45 45 > grid.tmp
./test_values.sh grid.tmp answer.tmp 3 "grid: dipping grid (cartesian)" || exit 1

# Cross-section (cartesian)
cat > answer.tmp << EOF
  -1.4142135623730949       -1.4142135623730951        0.0000000000000000       -2.0000000000000000        0.0000000000000000     
  -1.4142135623730949       -1.4142135623730951        10.000000000000000       -2.0000000000000000        0.0000000000000000     
   0.0000000000000000        0.0000000000000000        0.0000000000000000        0.0000000000000000        0.0000000000000000     
   0.0000000000000000        0.0000000000000000        10.000000000000000        0.0000000000000000        0.0000000000000000     
   1.4142135623730949        1.4142135623730951        0.0000000000000000        2.0000000000000000        0.0000000000000000     
   1.4142135623730949        1.4142135623730951        10.000000000000000        2.0000000000000000        0.0000000000000000 
EOF
../bin/grid -x -2 2 -dx 2 -z 0 10 -dz 10 -xsec 0 0 45 > grid.tmp
./test_values.sh grid.tmp answer.tmp 5 "grid: cross-section grid (cartesian)" || exit 1

# Cross-section (cartesian, with y perpendicular to cross-section)
cat > answer.tmp << EOF
  -1.4142135623730949       -1.4142135623730951        0.0000000000000000       -2.0000000000000000        0.0000000000000000     
  -1.4142135623730949       -1.4142135623730951        10.000000000000000       -2.0000000000000000        0.0000000000000000     
  -2.1213203435596424      -0.70710678118654757        0.0000000000000000       -2.0000000000000000        1.0000000000000000     
  -2.1213203435596424      -0.70710678118654757        10.000000000000000       -2.0000000000000000        1.0000000000000000     
   0.0000000000000000        0.0000000000000000        0.0000000000000000        0.0000000000000000        0.0000000000000000     
   0.0000000000000000        0.0000000000000000        10.000000000000000        0.0000000000000000        0.0000000000000000     
 -0.70710678118654746       0.70710678118654757        0.0000000000000000        0.0000000000000000        1.0000000000000000     
 -0.70710678118654746       0.70710678118654757        10.000000000000000        0.0000000000000000        1.0000000000000000     
   1.4142135623730949        1.4142135623730951        0.0000000000000000        2.0000000000000000        0.0000000000000000     
   1.4142135623730949        1.4142135623730951        10.000000000000000        2.0000000000000000        0.0000000000000000     
  0.70710678118654746        2.1213203435596428        0.0000000000000000        2.0000000000000000        1.0000000000000000     
  0.70710678118654746        2.1213203435596428        10.000000000000000        2.0000000000000000        1.0000000000000000
EOF
../bin/grid -x -2 2 -dx 2 -y 0 1 -ny 2 -z 0 10 -dz 10 -xsec 0 0 45 > grid.tmp
./test_values.sh grid.tmp answer.tmp 5 "grid: cross-section grid (cartesian with y)" || exit 1

# Cross-section (geographic)
cat > answer.tmp << EOF
   1.2720417254486149       -1.2717283475909673        0.0000000000000000       -200.00000000000000        0.0000000000000000     
   1.2720417254486149       -1.2717283475909673        100.00000000000000       -200.00000000000000        0.0000000000000000     
   0.0000000000000000        0.0000000000000000        0.0000000000000000        0.0000000000000000        0.0000000000000000     
   0.0000000000000000        0.0000000000000000        100.00000000000000        0.0000000000000000        0.0000000000000000     
  -1.2720417254486149        1.2717283475909673        0.0000000000000000        200.00000000000000        0.0000000000000000     
  -1.2720417254486149        1.2717283475909673        100.00000000000000        200.00000000000000        0.0000000000000000
EOF
../bin/grid -x -200 200 -nx 3 -z 0 100 -dz 100 -xsec 0 0 -45 -geo > grid.tmp
./test_values.sh grid.tmp answer.tmp 5 "grid: cross-section grid (geographic)" || exit 1

# Exponential spacing
cat > answer.tmp << EOF 
   1.0000000000000000        2.0000000000000000     
   1.0000000000000000        4.0000000000000000     
   1.0000000000000000        8.0000000000000000     
   1.7782794100389230        2.0000000000000000     
   1.7782794100389230        4.0000000000000000     
   1.7782794100389230        8.0000000000000000     
   3.1622776601683800        2.0000000000000000     
   3.1622776601683800        4.0000000000000000     
   3.1622776601683800        8.0000000000000000     
   5.6234132519034921        2.0000000000000000     
   5.6234132519034921        4.0000000000000000     
   5.6234132519034921        8.0000000000000000     
   10.000000000000004        2.0000000000000000     
   10.000000000000004        4.0000000000000000     
   10.000000000000004        8.0000000000000000
EOF
../bin/grid -x 1 10 -nx 5 -y 2 8 -dy 2 -exp > grid.tmp
./test_values.sh grid.tmp answer.tmp 2 "grid: exponential spacing" || exit 1


rm *.tmp
