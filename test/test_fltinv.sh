#!/bin/bash

echo ---------------------------------------------------------
echo Test \#1: 1 strike-slip fault, 4 3-component displacements
echo ----------
# Input fault slip (Cartesian coordinate system)
X=0; Y=0; Z=10
STR=0; DIP=90; RAK=0
SLIP=1; WID=4; LEN=6
echo $X $Y $Z $STR $DIP $RAK $SLIP $WID $LEN > o92_flt.tmp

# Station locations
cat > o92_sta.tmp << EOF
-1 -1  0
 1 -1  0
 1  1  0
-1  1  0
EOF

# Calculate "observed" displacements with no noise
../bin/o92util -flt o92_flt.tmp -sta o92_sta.tmp -disp o92_disp.tmp -xy

# Prepare displacement observation and fault geometry files for fltinv
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$6}' o92_disp.tmp > fltinv_disp.tmp
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$8*1e3,$9*1e3}' o92_flt.tmp > fltinv_flt.tmp

# Actual solution
#echo "Actual solution (strike-slip dip-slip):"
#awk '{printf("%16.8e%16.8e\n"),$7*cos($6*0.0174533),$7*sin($6*0.0174533)}' o92_flt.tmp

# Linear least squares solution
#echo "Least squares solution:"
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -o inversion.tmp
echo 1.00000000E+00 -1.29382228E-16 > answer.tmp
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 1 fault, three-component disp" || exit 1

#echo ----------
#echo Finished Test \#1
#echo ----------
#echo



echo ----------------------------------------------------------
echo Test \#2: 4 strike-slip faults, 9 3-component displacements, inversion constraints
echo ----------
# Input fault slip
#  X  Y  Z STR DIP RAK SLIP WID LEN
cat > o92_flt.tmp << EOF
   4  0  4  90  90 170  2.0   6   8
   4  0 10  90  90 180  1.5   6   8
  -4  0  4  90  90 180  1.5   6   8
  -4  0 10  90  90 190  1.0   6   8
EOF

# Station locations
../bin/grid -x -6 6 -dx 6 -y -6 6 -dy 6 -z 0.0 -o o92_sta.tmp

# Calculate "observed" displacements with no noise
../bin/o92util -flt o92_flt.tmp -sta o92_sta.tmp -disp o92_disp.tmp -xy

# Prepare displacement observation and fault geometry files for fltinv
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$6}' o92_disp.tmp > fltinv_disp.tmp
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$8*1e3,$9*1e3}' o92_flt.tmp > fltinv_flt.tmp

# Actual solution
#echo "Actual solution (strike-slip dip-slip):"
#awk '{printf("%16.8e%16.8e\n"),$7*cos($6*0.0174533),$7*sin($6*0.0174533)}' o92_flt.tmp

# Linear least squares solutions
#echo "Least squares solution:"
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -o inversion.tmp
cat > answer.tmp << EOF
 -1.96961551E+00  3.47296355E-01
 -1.50000000E+00 -4.38361161E-10
 -1.50000000E+00 -1.04931971E-10
 -9.84807752E-01 -1.73648177E-01
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, three-component disp" || exit 1

#echo Least squares solution + only horizontal displacements:
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -disp:components 12 \
    -o inversion.tmp
cat > answer.tmp << EOF
 -1.96961551E+00  3.47296356E-01
 -1.50000000E+00 -7.90254736E-10
 -1.50000000E+00 -4.37814461E-10
 -9.84807753E-01 -1.73648176E-01
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, horizontal disp" || exit 1

#echo Least squares solution + only vertical displacements:
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -disp:components 3 \
    -o inversion.tmp
cat > answer.tmp << EOF
 -5.92420991E+00  5.83424688E-01
  2.05865282E+00 -5.30728300E-01
 -5.45459440E+00 -2.36128333E-01
  2.57384507E+00  3.57080123E-01
EOF
#test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, vertical disp" || exit 1

#echo "Least squares solution + fixed rake (actual rake value):"
cat > rake.tmp << EOF
170
180
180
190
EOF
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -flt:rake rake.tmp \
    -o inversion.tmp
cat > answer.tmp << EOF
 -1.96961551E+00  3.47296355E-01
 -1.50000000E+00  1.83697020E-16
 -1.50000000E+00  1.83697020E-16
 -9.84807753E-01 -1.73648178E-01
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, fixed rake (input value)" || exit 1

#echo "Least squares solution + fixed rake (all 180) + gels:"
cat > rake.tmp << EOF
180
180
180
180
EOF
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -flt:rake rake.tmp \
    -lsqr:mode gels \
    -o inversion.tmp
cat > answer.tmp << EOF
 -2.18179681E+00  2.67193048E-16
 -1.24866911E+00  1.52917863E-16
 -1.72650372E+00  2.11435726E-16
  7.41870420E-01 -9.08529235E-17
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, fixed rake (180)" || exit 1

#echo "Least squares solution + fixed rake (all 180) + nnls:"
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -flt:rake rake.tmp \
    -lsqr:mode nnls \
    -o inversion.tmp
cat > answer.tmp << EOF
 -2.13317688E+00  2.61238824E-16
 -1.37064417E+00  1.67855500E-16
 -1.55525804E+00  1.90464178E-16
 -0.00000000E+00  0.00000000E+00
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, fixed rake (180), nnls" || exit 1

#echo "Least squares solution + rotated rakes (135,225) + nnls:"
cat > rake.tmp << EOF
135 225
135 225
135 225
135 225
EOF
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -flt:rake rake.tmp \
    -lsqr:mode nnls \
    -o inversion.tmp
cat > answer.tmp << EOF
 -1.96961551E+00  3.47296355E-01
 -1.50000000E+00 -4.38365233E-10
 -1.50000000E+00 -1.04934617E-10
 -9.84807752E-01 -1.73648177E-01
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, rotated rakes, nnls" || exit 1

#echo "Least squares solution + 2 fixed slip magnitudes (ss1=-2.0, ss4=-1.0):"
cat > slip.tmp << EOF
 -2.0 99999
99999 99999
99999 99999
 -1.0 99999
EOF
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -flt:slip slip.tmp \
    -o inversion.tmp
cat > answer.tmp << EOF
 -2.00000000E+00  3.58983687E-01
 -1.37153328E+00 -3.08787060E-02
 -1.50516777E+00 -1.59398437E-02
 -1.00000000E+00 -1.17235180E-01
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, 2 fixed slip components" || exit 1

#echo Least squares solution + damping = 0.1:
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -damp 0.1 \
    -o inversion.tmp
cat > answer.tmp << EOF
 -2.08639264E+00  4.00049826E-01
 -1.02316429E+00 -2.02031558E-01
 -1.59822646E+00 -5.72336702E-02
 -6.59136975E-01  5.83208843E-02
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, damping=0.1" || exit 1

#echo Least squares solution + damping = 1.0:
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -damp 1.0 \
    -o inversion.tmp
cat > answer.tmp << EOF
 -9.42434826E-02  3.07720984E-03
 -2.42600753E-02  8.46490929E-03
 -7.77428978E-02  2.83172661E-02
 -1.97073766E-02  7.18457860E-03
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, damping=1.0" || exit 1

#echo Least squares solution + smoothing = 0.1:
cat > smooth.tmp << EOF
1 2 2 3
2 2 1 4
3 2 1 4
4 2 2 3
EOF
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -smooth 0.1 smooth.tmp \
    -o inversion.tmp
cat > answer.tmp << EOF
 -1.91136616E+00  3.24205218E-01
 -1.64903145E+00  1.07798352E-01
 -1.43169386E+00  1.08545384E-02
 -1.30348164E+00 -2.30878153E-01
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, smoothing=1.0" || exit 1

#echo Least squares solution + smoothing = 1.0:
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -smooth 1.0 smooth.tmp \
    -o inversion.tmp
cat > answer.tmp << EOF
 -1.59980137E+00  1.33771124E-01
 -1.59924854E+00  1.33076242E-01
 -1.59821957E+00  1.31165833E-01
 -1.59819277E+00  1.30912070E-01
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, smoothing=1.0" || exit 1

#echo Least squares solution + damping + smoothing:
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -damp 0.05 \
    -smooth 0.05 smooth.tmp \
    -o inversion.tmp
cat > answer.tmp << EOF
 -1.95959393E+00  3.35800676E-01
 -1.51558421E+00  3.94337069E-02
 -1.48264150E+00  9.85831333E-03
 -1.05925719E+00 -2.01563018E-01
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, smoothing=1.0" || exit 1

#echo ----------
#echo Finished Test \#2
#echo ----------
#echo


echo ---------------------------------------------------------
echo Test \#3: 4 strike-slip faults, 16 line-of-sight displacements
echo ----------
# Input fault slip
#  X  Y  Z STR DIP RAK SLIP WID LEN
cat > o92_flt.tmp << EOF
   4  0  4  90  90 170  2.0   6   8
   4  0 10  90  90 180  1.5   6   8
  -4  0  4  90  90 180  1.5   6   8
  -4  0 10  90  90 190  1.0   6   8
EOF

# Station locations
../bin/grid -x -6 6 -dx 4 -y -6 6 -dy 4 -z 0.0 -o o92_sta.tmp

# Calculate "observed" displacements with no noise
../bin/o92util -flt o92_flt.tmp -sta o92_sta.tmp -disp o92_disp.tmp -xy

# Prepare displacement observation and fault geometry files for fltinv
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$6}' o92_disp.tmp > fltinv_disp.tmp
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$8*1e3,$9*1e3}' o92_flt.tmp > fltinv_flt.tmp

# Calculate line-of-sight displacements
AZ="45"
INC="35"
../bin/vec2los -f o92_disp.tmp -o o92_los.tmp -a $AZ -i $INC

# Prepare displacement and fault files for fltinv
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,'"$AZ"','"$INC"'}' o92_los.tmp > fltinv_los.tmp

../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -los fltinv_los.tmp \
    -gf:model okada_rect \
    -o inversion.tmp
cat > answer.tmp << EOF
 -1.96963011E+00  3.47297415E-01
 -1.49967016E+00 -2.69751544E-04
 -1.50042575E+00 -1.21322744E-04
 -9.83059196E-01 -1.73130858E-01
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, 16 los disp" || exit 1

#echo ----------
#echo Finished Test \#3
#echo ----------
#echo


echo ---------------------------------------------------------
echo Test \#4: 4 strike-slip faults, 9 three-component, 16 line-of-sight displacements
echo ----------
# Input fault slip
#  X  Y  Z STR DIP RAK SLIP WID LEN
cat > o92_flt.tmp << EOF
   4  0  4  90  90 170  2.0   6   8
   4  0 10  90  90 180  1.5   6   8
  -4  0  4  90  90 180  1.5   6   8
  -4  0 10  90  90 190  1.0   6   8
EOF
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$8*1e3,$9*1e3}' o92_flt.tmp > fltinv_flt.tmp

# Station locations
../bin/grid -x -6 6 -dx 6 -y -6 6 -dy 6 -z 0.0 -o o92_sta_disp.tmp
../bin/grid -x -6 6 -dx 4 -y -6 6 -dy 4 -z 0.0 -o o92_sta_los.tmp

# Calculate "observed" displacements with no noise
../bin/o92util -flt o92_flt.tmp -sta o92_sta_disp.tmp -disp o92_disp.tmp -xy
../bin/o92util -flt o92_flt.tmp -sta o92_sta_los.tmp -disp o92_disp_los.tmp -xy
AZ="45"
INC="35"
../bin/vec2los -f o92_disp_los.tmp -o o92_los.tmp -a $AZ -i $INC

# Prepare displacement observation and files for fltinv
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$6}' o92_disp.tmp > fltinv_disp.tmp
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,'"$AZ"','"$INC"'}' o92_los.tmp > fltinv_los.tmp

../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -los fltinv_los.tmp \
    -gf:model okada_rect \
    -o inversion.tmp 
cat > answer.tmp << EOF
 -1.96965424E+00  3.47308462E-01
 -1.49992902E+00 -2.38168890E-04
 -1.50029127E+00 -8.30644105E-05
 -9.83739243E-01 -1.73386437E-01
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, 9 3-comp disp, 16 los disp" || exit 1

#echo ----------
#echo Finished Test \#4
#echo ----------
#echo


echo ----------------------------------------------------------
echo Test \#5: 4 dip-slip faults, 25 3-component displacements, covariance
echo ----------
# Input fault slip
#  X  Y  Z STR DIP RAK SLIP WID LEN
cat > o92_flt.tmp << EOF
1.73205  3  1   0  30  65  2.0   4   6
5.19615  3  3   0  30 100  1.5   4   6
1.73205 -3  1   0  30  80  1.5   4   6
5.19615 -3  3   0  30 115  1.0   4   6
EOF
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$8*1e3,$9*1e3}' o92_flt.tmp > fltinv_flt.tmp
#echo "Actual solution (strike-slip dip-slip):"
#awk '{printf("%16.8e%16.8e\n"),$7*cos($6*0.0174533),$7*sin($6*0.0174533)}' o92_flt.tmp
#echo

# Station locations
../bin/grid -x -2 6 -nx 5 -y -7 7 -ny 5 -z 0.0 -o o92_sta.tmp

# Calculate "observed" displacements with small noise
../bin/o92util -flt o92_flt.tmp -sta o92_sta.tmp -disp o92_disp.tmp -xy
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$6}' o92_disp.tmp > fltinv_disp.tmp

# Covariance matrix: iobs jobs icmp jcmp cov
cat > cov.tmp << EOF
0.01 0.01 0.04
0.02 0.01 0.05
0.01 0.02 0.03
0.02 0.02 0.08
0.01 0.02 0.05
0.01 0.01 0.04
0.02 0.01 0.03
0.02 0.01 0.05
0.02 0.02 0.06
0.01 0.01 0.04
0.02 0.01 0.05
0.01 0.02 0.03
0.02 0.02 0.08
0.01 0.02 0.05
0.01 0.01 0.04
0.02 0.01 0.03
0.02 0.01 0.05
0.02 0.02 0.06
0.02 0.01 0.03
0.02 0.01 0.05
0.02 0.02 0.06
0.01 0.01 0.04
0.02 0.01 0.05
0.01 0.02 0.03
0.02 0.02 0.08
EOF
awk '{print NR,NR,1,1,$1;print NR,NR,2,2,$2;print NR,NR,3,3,$3}' cov.tmp > j
mv j cov.tmp

cat > noise.tmp << EOF
-1.4152496444935702E-002 -1.2167028474564456E-003 -3.4635782241821289E-002
-8.4763468832385787E-004 7.5453025650004950E-004 -1.2063829950532134E-003
9.6945130095189933E-003 5.7152114352401430E-003 2.0121647387134782E-002
-2.6528798803991203E-003 1.9361163888658797E-002 2.7268521639765526E-002
-6.6578228558812820E-004 -1.6482822749079494E-002 -3.5189259417203009E-002
-1.0586362712237301E-003 -5.6500325397569303E-003 2.9778957366943363E-002
1.5334482399784789E-003 -2.7342840116851186E-003 -1.5969733802639708E-002
-5.4498953478676936E-003 8.5568838581746940E-004 -2.7436671816572850E-002
-7.9106420886759857E-003 -7.7488142616894788E-003 1.6351620153504973E-002
-3.3051888553463685E-003 6.3877203026596382E-003 8.3482303485578422E-004
-1.4367604742244799E-002 -7.8806167050283788E-004 -4.6090146108549473E-002
-2.3938993714293657E-003 4.3311392014123957E-004 9.2591178052279424E-003
-9.3238487535593460E-003 9.9525214457998473E-003 9.8477113915949465E-004
-9.0432519815406027E-003 1.0101622464705487E-002 4.2777417265639016E-002
-6.9264781718351405E-003 1.2579245530829138E-003 -2.0203347108802016E-002
-1.5681831508266683E-003 -4.1007816183323761E-003 -1.1826992643122770E-002
-8.2280915610644292E-003 2.1531838847666370E-003 5.1082676770735767E-002
-5.6215311799730572E-003 -1.5717176150302499E-003 3.1956130144547443E-002
1.4659825636416067E-002 -3.4483120757706313E-003 -1.6482395176984826E-002
-1.0679529637706523E-002 -3.3939806174258800E-003 -2.6680434844931780E-002
1.5619089408796661E-002 -1.0788891996656147E-002 -2.8875541930295984E-002
2.6976806776864187E-003 -1.3598107865878514E-003 1.4433164985812442E-002
6.9846425737653461E-003 5.9607180253583563E-004 9.9866441926177666E-003
-3.8827776300663854E-003 -9.1281533241271973E-003 6.0975697575783236E-003
9.3867809188609222E-003 -6.6163114139011934E-003 1.8654646922130976E-002
EOF
paste fltinv_disp.tmp noise.tmp |\
    awk '{print $1,$2,$3,$4+$7,$5+$8,$6+$9}' > j
mv j fltinv_disp.tmp

../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -o inversion.tmp
cat > answer.tmp << EOF
  8.54029764E-01  1.82691412E+00
 -3.25610007E-01  1.46402442E+00
  2.56686931E-01  1.46217560E+00
 -3.69135504E-01  1.00378397E+00
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: 4 dip-slip faults, 25 observations, covariance matrix" || exit 1

#echo ----------
#echo Finished Test \#5
#echo ----------
#echo



echo ----------------------------------------------------------------
echo Test \#6: 1 strike-slip fault, pre-stresses from coincident fault
echo ----------
# Fault generating pre-stresses
#    X  Y  Z  STR DIP RAK SLIP WID LEN
echo 0  1 10    0  90   0    1   2   2 > flt.tmp

# Target fault
#  X  Y  Z STR DIP RAK SLIP WID LEN
echo 0  1 10 > sta.tmp

# Elastic half-space properties
echo shearmod 40e9 lame 40e9 > haf.tmp

# Calculate pre-stresses
../bin/o92util -flt flt.tmp -sta sta.tmp -stress stress.tmp -xy -haf haf.tmp

# Prepare fltinv input files
awk '{print $4,$5,$6,$7,$8,$9}' stress.tmp > j; mv j stress.tmp
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$8*1e3,$9*1e3}' flt.tmp > fltinv_flt.tmp

# Actual solution
#echo Actual solution
#echo -1 0

# Linear least squares solution
../bin/fltinv \
    -mode lsqr \
    -lsqr:mode gesv \
    -flt fltinv_flt.tmp \
    -prests stress.tmp \
    -gf:model okada_rect \
    -o inversion.tmp
echo -1.00000000E+00  0.00000000E+00 > answer.tmp
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 1 ss fault, pre-stresses from coincident fault" || exit 1

#echo ----------
#echo Finished Test \#6
#echo ----------
#echo



echo --------------------------------------------------------------
echo Test \#7: 2 strike-slip faults, pre-stresses from central fault
echo ----------
# Fault generating pre-stresses
#    X  Y  Z STR DIP RAK SLIP WID LEN
echo 0  0 10   0  90   0    1   2   2 > flt.tmp

# Target faults
#    X   Y  Z STR DIP RAK SLIP WID LEN
echo 0   2 10   0  90   0    0   2   2 > sta.tmp
echo 0  -2 10   0  90   0    0   2   2 >> sta.tmp

# Elastic half-space properties
echo lame 40e9 shearmod 40e9 > haf.tmp

# Calculate pre-stresses
../bin/o92util -flt flt.tmp -sta sta.tmp -stress stress.tmp -xy -haf haf.tmp

# Prepare fltinv input files
awk '{print $4,$5,$6,$7,$8,$9}' stress.tmp > j; mv j stress.tmp
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$8*1e3,$9*1e3}' sta.tmp > flt.tmp

# Actual solution
#echo Actual solution
#echo 0.173 0.000
#echo 0.173 0.000

# Linear least squares solution
../bin/fltinv \
    -mode lsqr \
    -lsqr:mode gesv \
    -flt flt.tmp \
    -prests stress.tmp \
    -gf:model okada_rect \
    -o inversion.tmp
cat > answer.tmp << EOF
  1.73043144E-01  6.59943338E-05
  1.73043144E-01 -6.59943338E-05
EOF
test_values.sh inversion.tmp answer.tmp 2 "lsqr, minimize shear traction on 2 strike-slip faults" || exit 1

#echo ----------
#echo Finished Test \#7
#echo ----------
#echo

#
#
#
#
#
#
#
#
#
#
#
#
#
#
rm *.tmp
#
#
#
#
#
#
#
#
#
#
#
#
#
#


echo --------------------------------------------------------------
echo Side Test: Are integer and double precision annealing algorithms the same?
echo ----------
awk 'BEGIN{p=0}{
    if (/^subroutine anneal_int_array/) {
        p = 1
    }
    if (p==1) {
        print $0
    }
    if (/^end subroutine anneal_int_array/) {
        p = 0
    }
}' ../src/annealing_module.f90 > anneal_int_array.tmp
awk 'BEGIN{p=0}{
    if (/^subroutine anneal_dp_array/) {
        p = 1
    }
    if (p==1) {
        print $0
    }
    if (/^end subroutine anneal_dp_array/) {
        p = 0
    }
}' ../src/annealing_module.f90 > anneal_dp_array.tmp
diff anneal_int_array.tmp anneal_dp_array.tmp



echo --------------------------------------------------------------
echo Test \#8: 1 strike-slip fault, 4 3-component displacements, simulated annealing
echo ----------
# Input fault slip (Cartesian coordinate system)
X=0; Y=0; Z=10
STR=0; DIP=90; RAK=0
SLIP=1; WID=4; LEN=6
echo $X $Y $Z $STR $DIP $RAK $SLIP $WID $LEN > o92_flt.tmp

# Station locations
cat > o92_sta.tmp << EOF
-1 -1  0
 1 -1  0
 1  1  0
-1  1  0
EOF

# Calculate "observed" displacements with no noise
../bin/o92util -flt o92_flt.tmp -sta o92_sta.tmp -disp o92_disp.tmp -xy

# Prepare displacement observation and fault geometry files for fltinv
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$6}' o92_disp.tmp > fltinv_disp.tmp
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$8*1e3,$9*1e3}' o92_flt.tmp > fltinv_flt.tmp

# Actual solution
#echo "Actual solution (strike-slip dip-slip):"
#awk '{printf("%16.8e%16.8e\n"),$7*cos($6*0.0174533),$7*sin($6*0.0174533)}' o92_flt.tmp

# Slip and rake constraints
echo 0 10 > slip.tmp
echo -30 60 > rake.tmp
echo 0.25 1 > step.tmp

# Linear least squares solution
#echo "Least squares solution:"
../bin/fltinv \
    -mode anneal \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -flt:slip slip.tmp \
    -flt:rake rake.tmp \
    -anneal:init_mode mean \
    -anneal:step step.tmp \
    -anneal:max_it 1000 \
    -anneal:reset_it 500 \
    -anneal:temp_start 0.5 \
    -anneal:temp_min 0.0 \
    -anneal:cool 0.98 \
    -anneal:log_file anneal.log \
    -anneal:seed 1 \
    -o inversion.tmp
echo 1.18729953E+00 -1.69601249E-01 > answer.tmp
test_values.sh inversion.tmp answer.tmp 2 "fltinv: anneal, 1 fault, three-component disp" || exit 1

#echo ----------
#echo Finished Test \#8
#echo ----------
#echo




echo ----------------------------------------------------------
echo Test \#9: 4 dip-slip faults, 25 3-component displacements, covariance, annealing
echo ----------
# Input fault slip
#  X  Y  Z STR DIP RAK SLIP WID LEN
cat > o92_flt.tmp << EOF
1.73205  3  1   0  30  65  2.0   4   6
5.19615  3  3   0  30 100  1.5   4   6
1.73205 -3  1   0  30  80  1.5   4   6
5.19615 -3  3   0  30 115  1.0   4   6
EOF
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$8*1e3,$9*1e3}' o92_flt.tmp > fltinv_flt.tmp
#echo "Actual solution (strike-slip dip-slip):"
#awk '{printf("%16.8e%16.8e\n"),$7*cos($6*0.0174533),$7*sin($6*0.0174533)}' o92_flt.tmp
#echo

# Station locations
../bin/grid -x -2 6 -nx 5 -y -7 7 -ny 5 -z 0.0 -o o92_sta.tmp

# Calculate "observed" displacements with small noise
../bin/o92util -flt o92_flt.tmp -sta o92_sta.tmp -disp o92_disp.tmp -xy
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$6}' o92_disp.tmp > fltinv_disp.tmp

# Covariance matrix: iobs jobs icmp jcmp cov
cat > cov.tmp << EOF
0.01 0.01 0.04
0.02 0.01 0.05
0.01 0.02 0.03
0.02 0.02 0.08
0.01 0.02 0.05
0.01 0.01 0.04
0.02 0.01 0.03
0.02 0.01 0.05
0.02 0.02 0.06
0.01 0.01 0.04
0.02 0.01 0.05
0.01 0.02 0.03
0.02 0.02 0.08
0.01 0.02 0.05
0.01 0.01 0.04
0.02 0.01 0.03
0.02 0.01 0.05
0.02 0.02 0.06
0.02 0.01 0.03
0.02 0.01 0.05
0.02 0.02 0.06
0.01 0.01 0.04
0.02 0.01 0.05
0.01 0.02 0.03
0.02 0.02 0.08
EOF
awk '{print NR,NR,1,1,$1;print NR,NR,2,2,$2;print NR,NR,3,3,$3}' cov.tmp > j
mv j cov.tmp

cat > noise.tmp << EOF
-1.4152496444935702E-002 -1.2167028474564456E-003 -3.4635782241821289E-002
-8.4763468832385787E-004 7.5453025650004950E-004 -1.2063829950532134E-003
9.6945130095189933E-003 5.7152114352401430E-003 2.0121647387134782E-002
-2.6528798803991203E-003 1.9361163888658797E-002 2.7268521639765526E-002
-6.6578228558812820E-004 -1.6482822749079494E-002 -3.5189259417203009E-002
-1.0586362712237301E-003 -5.6500325397569303E-003 2.9778957366943363E-002
1.5334482399784789E-003 -2.7342840116851186E-003 -1.5969733802639708E-002
-5.4498953478676936E-003 8.5568838581746940E-004 -2.7436671816572850E-002
-7.9106420886759857E-003 -7.7488142616894788E-003 1.6351620153504973E-002
-3.3051888553463685E-003 6.3877203026596382E-003 8.3482303485578422E-004
-1.4367604742244799E-002 -7.8806167050283788E-004 -4.6090146108549473E-002
-2.3938993714293657E-003 4.3311392014123957E-004 9.2591178052279424E-003
-9.3238487535593460E-003 9.9525214457998473E-003 9.8477113915949465E-004
-9.0432519815406027E-003 1.0101622464705487E-002 4.2777417265639016E-002
-6.9264781718351405E-003 1.2579245530829138E-003 -2.0203347108802016E-002
-1.5681831508266683E-003 -4.1007816183323761E-003 -1.1826992643122770E-002
-8.2280915610644292E-003 2.1531838847666370E-003 5.1082676770735767E-002
-5.6215311799730572E-003 -1.5717176150302499E-003 3.1956130144547443E-002
1.4659825636416067E-002 -3.4483120757706313E-003 -1.6482395176984826E-002
-1.0679529637706523E-002 -3.3939806174258800E-003 -2.6680434844931780E-002
1.5619089408796661E-002 -1.0788891996656147E-002 -2.8875541930295984E-002
2.6976806776864187E-003 -1.3598107865878514E-003 1.4433164985812442E-002
6.9846425737653461E-003 5.9607180253583563E-004 9.9866441926177666E-003
-3.8827776300663854E-003 -9.1281533241271973E-003 6.0975697575783236E-003
9.3867809188609222E-003 -6.6163114139011934E-003 1.8654646922130976E-002
EOF
paste fltinv_disp.tmp noise.tmp |\
    awk '{print $1,$2,$3,$4+$7,$5+$8,$6+$9}' > j
mv j fltinv_disp.tmp

cat > slip.tmp << EOF
0 5
0 5
0 5
0 5
EOF
cat > rake.tmp << EOF
0 180
0 180
0 180
0 180
EOF
cat > step.tmp << EOF
0.05 2
0.05 2
0.05 2
0.05 2
EOF
../bin/fltinv \
    -mode anneal \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model okada_rect \
    -flt:slip slip.tmp \
    -flt:rake rake.tmp \
    -anneal:init_mode mean \
    -anneal:step step.tmp \
    -anneal:max_it 2000 \
    -anneal:reset_it 1000 \
    -anneal:temp_start 0.5 \
    -anneal:temp_min 0.0 \
    -anneal:cool 0.99 \
    -anneal:log_file anneal.log \
    -anneal:seed 1 \
    -o inversion.tmp
cat > answer.tmp << EOF
  8.66128699E-01  1.81351839E+00
 -3.67871230E-01  1.45673734E+00
  2.47535983E-01  1.45810405E+00
 -3.11359215E-01  1.03791256E+00
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: anneal, 4 dip-slip faults, 25 observations, covariance matrix, annealing" || exit 1

#echo ----------
#echo Finished Test \#9
#echo ----------
#echo



echo ----------------------------------------------------------
echo Test \#10: 9 strike-slip faults, 25 three-component displacements, simulated annealing with pseudo-coupling
echo ----------
# Compute displacements corresponding to pseudo-coupling solution
# Input faults
#  X  Y  Z STR DIP RAK SLIP WID LEN
cat > o92_flt.tmp << EOF
  -3  0  3  90  90 180    0   3   3
   0  0  3  90  90 180    0   3   3
   3  0  3  90  90 180    0   3   3
  -3  0  6  90  90 180    0   3   3
   0  0  6  90  90 180    1   3   3
   3  0  6  90  90 180    0   3   3
  -3  0  9  90  90 180    0   3   3
   0  0  9  90  90 180    0   3   3
   3  0  9  90  90 180    0   3   3
EOF
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$8*1e3,$9*1e3}' o92_flt.tmp > fltinv_flt.tmp

# Slip constraints
#   SS    DS
cat > fltinv_slip.tmp << EOF
 99999 99999
 99999 99999
 99999 99999
 99999 99999
    -1     0
 99999 99999
 99999 99999
 99999 99999
 99999 99999
EOF

# Pre-stresses
awk '{print 0,0,0,0,0,0}' o92_flt.tmp > fltinv_sts.tmp

# Calculate fault slip surrounding central fault
echo vp 6800 vs 3926 dens 3000 > haf.tmp
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -flt:slip fltinv_slip.tmp \
    -haf haf.tmp \
    -prests fltinv_sts.tmp \
    -gf:model okada_rect \
    -lsqr:mode gesv \
    -o inversion.tmp
cat > answer.tmp << EOF
 -9.36179227E-02  2.56503112E-02
 -1.44914261E-01 -2.87180558E-11
 -9.36179227E-02 -2.56503113E-02
 -2.05038774E-01  4.53406569E-03
 -1.00000000E+00  0.00000000E+00
 -2.05038774E-01 -4.53406569E-03
 -8.70859505E-02 -1.45560087E-02
 -1.35046650E-01  2.16526690E-11
 -8.70859505E-02  1.45560087E-02
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, pre-stresses, fix central fault slip, 8 surrounding unlocked faults" || exit 1


# Calculate displacements at grid of stations around faults
paste o92_flt.tmp inversion.tmp |\
    awk '{print $1,$2,$3,$4,$5,atan2($11,$10)/0.0174533,sqrt($10*$10+$11*$11),$8,$9}' > o92_flt_psc.tmp
../bin/grid -x -4.5 5.2 -nx 5 -y -3.6 2.9 -ny 5 -z 0.0 -o o92_sta_psc.tmp
../bin/o92util -flt o92_flt_psc.tmp -sta o92_sta_psc.tmp -haf haf.tmp -disp o92_disp_psc.tmp -xy
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$6}' o92_disp_psc.tmp > fltinv_disp_psc.tmp

# Search for fault slip using simulated annealing with pseudo-coupling
cat > fltinv_slip_psc.tmp << EOF
-1 0
-1 0
-1 0
-1 0
-1 0
-1 0
-1 0
-1 0
-1 0
EOF
rm inversion.tmp
../bin/fltinv \
    -mode anneal-psc \
    -flt fltinv_flt.tmp \
    -flt:slip fltinv_slip_psc.tmp \
    -disp fltinv_disp_psc.tmp \
    -haf haf.tmp \
    -gf:model okada_rect \
    -anneal:max_it 1000 \
    -anneal:temp_start 0.5 \
    -anneal:init_mode rand0.5 \
    -anneal:log_file anneal.log \
    -anneal-psc:min_flip 1 \
    -anneal-psc:max_flip 2 \
    -anneal:seed 12345 \
    -o inversion.tmp
cat > answer.tmp << EOF
 -9.36179227E-02  2.56503112E-02
 -1.44914261E-01 -2.87180558E-11
 -9.36179227E-02 -2.56503113E-02
 -2.05038774E-01  4.53406569E-03
 -1.00000000E+00  0.00000000E+00
 -2.05038774E-01 -4.53406569E-03
 -8.70859505E-02 -1.45560087E-02
 -1.35046650E-01  2.16526690E-11
 -8.70859505E-02  1.45560087E-02
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: simulated annealing + pseudo-coupling" || exit 1

grep Iteration anneal.log | awk '{print $6}' | head -20 > fit.tmp
cat > answer.tmp << EOF
-4.2736531432366512E-002
-5.9343060813405443E-002
-4.9868570712277106E-002
-7.4047685432829843E-002
-4.7958495759038808E-002
-5.4701619915554729E-002
-5.4749118857992350E-002
-5.7047801792104898E-002
-8.3495981770522393E-002
-7.6468065589400114E-002
-5.7047801792104898E-002
-4.7958495759038808E-002
-2.4825797010700944E-002
-4.0353960414947730E-003
-2.7057133608867173E-002
-2.8900615810068201E-002
-2.4102062485012607E-002
-2.2437408725433487E-002
-1.9555864370221204E-002
-4.6156206640372330E-002
EOF
test_values.sh fit.tmp answer.tmp 1 "fltinv: simulated annealing + pseudo-coupling, first 10 fits" || exit 1
rm anneal.log

#echo ----------
#echo Finished Test \#10
#echo ----------
#echo


echo ----------------------------------------------------------
echo Test \#11: 4 triangular strike-slip faults, 9 3-component displacements
echo ----------
# Input fault slip
# x1 y1 z1 x2 y2 z2 x3 y3 z3 ss ds ts
cat > tri_flt.tmp << EOF
76.3 35.8 2.0 76.4 35.7 5.0 72.7 32.5 2.0 1.8 0.6 0.0
76.9 35.3 6.0 76.4 35.7 5.0 72.7 32.5 2.0 1.3 0.4 0.0
76.9 35.3 6.0 72.4 29.1 4.8 72.7 32.5 2.0 0.7 1.1 0.0
71.0 29.9 1.5 72.4 29.1 4.8 72.7 32.5 2.0 0.2 1.4 0.0
EOF

# Station locations
../bin/grid -x 70.0 80.0 -nx 3 -y 30.0 40.0 -ny 3 -z 0.0 -o tri_sta.tmp

# Calculate "observed" displacements with no noise
../bin/triutil -flt tri_flt.tmp -sta tri_sta.tmp -disp tri_disp.tmp -xy

# Prepare displacement observation and fault geometry files for fltinv
awk '{print $1*1e3,$2*1e3,$3*1e3,$4,$5,$6}' tri_disp.tmp > fltinv_disp.tmp
awk '{c=1e3;print $1*c,$2*c,$3*c,$4*c,$5*c,$6*c,$7*c,$8*c,$9*c}' tri_flt.tmp > fltinv_flt.tmp

# Actual solution
#echo "Actual solution (strike-slip dip-slip):"
#awk '{printf("%16.8e%16.8e\n"),$10,$11}' tri_flt.tmp

# Linear least squares solutions
#echo "Least squares solution:"
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -disp fltinv_disp.tmp \
    -gf:model triangle \
    -o inversion.tmp
cat > answer.tmp << EOF
  1.80000000E+00  6.00000000E-01
  1.30000000E+00  4.00000000E-01
  7.00000000E-01  1.10000000E+00
  2.00000000E-01  1.40000000E+00
EOF
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, 4 faults, three-component disp" || exit 1

#echo ----------
#echo Finished Test \#11
#echo ----------
#echo




echo ----------------------------------------------------------
echo Test \#12: 1 triangular dip-slip fault, pre-stresses
echo ----------
# One triangular fault
#
#   *(0,10,0)
#   |   --__
#   |       *(15,0,5)
#   |   --
#   *(0,-10,0)
#
echo 0 -10 0 15 0 5 0 10 0 > tri.tmp

# Triangle center
awk '{print ($1+$4+$7)/3,($2+$5+$8)/3,($3+$6+$9)/3}' tri.tmp > center.tmp

# One meter normal slip
echo 0 -1 0 > slip.tmp

# Compute stress at triangle center
paste tri.tmp slip.tmp > triutil_flt.tmp
cp center.tmp triutil_sta.tmp
echo shearmod 40e9 lame 40e9 > haf.tmp
../bin/triutil \
    -flt triutil_flt.tmp \
    -sta triutil_sta.tmp \
    -strain triutil_stn.tmp \
    -stress triutil_sts.tmp \
    -xy \
    -haf haf.tmp

# Prepare fltinv files
awk '{print $1*1e3,$2*1e3,$3*1e3,$4*1e3,$5*1e3,$6*1e3,$7*1e3,$8*1e3,$9*1e3}' tri.tmp > fltinv_flt.tmp
awk '{print $4,$5,$6,$7,$8,$9}' triutil_sts.tmp > fltinv_sts.tmp
../bin/fltinv \
    -flt fltinv_flt.tmp \
    -mode lsqr \
    -gf:model triangle \
    -prests fltinv_sts.tmp \
    -haf haf.tmp \
    -o inversion.tmp
echo   7.97433674E-17  9.99999930E-01 > answer.tmp
test_values.sh inversion.tmp answer.tmp 2 "fltinv: triangular dip-slip fault with pre-stresses" || exit 1

#echo ----------
#echo Finished Test \#12
#echo ----------
#echo



echo ----------------------------------------------------------
echo Test \#13: 1 triangular dip-slip fault, pre-stresses
echo ----------
# One locked triangular fault, resolved onto adjacent unlocked fault
#
#   *(0,10,0)
#   |   --__
#   |       *(15,0,5)
#   |   --  |
#   *(0,-10,0)
#    -      |
#      --   |
#         --*(15,-20,5)
#
#
echo 0 -10 0 15 0 5 0 10 0 > tri1.tmp
echo 0 -10 0 15 0 5 15 -20 5 > tri2.tmp

# Triangle centers
awk '{print ($1+$4+$7)/3,($2+$5+$8)/3,($3+$6+$9)/3}' tri1.tmp > center1.tmp
awk '{print ($1+$4+$7)/3,($2+$5+$8)/3,($3+$6+$9)/3}' tri2.tmp > center2.tmp

# One meter normal slip on locked fault
echo 0 -1 0 > slip1.tmp

# Compute stress at triangle 2 center
paste tri1.tmp slip1.tmp > triutil_flt1.tmp
echo lame 40e9 shear 40e9 > haf.tmp
cp center2.tmp triutil_sta2.tmp
../bin/triutil \
    -flt triutil_flt1.tmp \
    -sta triutil_sta2.tmp \
    -strain triutil_stn2.tmp \
    -stress triutil_sts2.tmp \
    -haf haf.tmp \
    -xy

# Prepare fltinv files
awk '{print $1*1e3,$2*1e3,$3*1e3,$4*1e3,$5*1e3,$6*1e3,$7*1e3,$8*1e3,$9*1e3}' tri2.tmp > fltinv_flt2.tmp
awk '{print $4,$5,$6,$7,$8,$9}' triutil_sts2.tmp > fltinv_sts2.tmp
echo vp 6800 vs 3926 dens 3000 > haf.tmp
../bin/fltinv \
    -mode lsqr \
    -lsqr:mode gesv \
    -flt fltinv_flt2.tmp \
    -gf:model triangle \
    -prests fltinv_sts2.tmp \
    -haf haf.tmp \
    -o inversion.tmp
echo -4.57250048E-02 -1.53447831E-01 > answer.tmp
test_values.sh inversion.tmp answer.tmp 2 "fltinv: lsqr, minimize shear traction on 1 other triangular fault" || exit 1

#echo ----------
#echo Finished Test \#13
#echo ----------
#echo


echo ----------------------------------------------------------
echo Test \#14: 1 triangular dip-slip fault, pre-stresses on itself, geographic coordinates
echo ----------
# One triangular fault, using geographic coordinates
#
#       *(3.0,42.0,2)
#      /    --__
#     /         *(3.2,41.6,5)
#    /      --
#    *(2.9,41.3,1.8)
#
echo 3.0 42.0 2.0 > pt1.tmp
echo 3.2 41.6 5.0 > pt2.tmp
echo 2.9 41.3 1.8 > pt3.tmp
paste pt1.tmp pt2.tmp pt3.tmp > tri.tmp

# Triangle center
awk '{print ($1+$4+$7)/3,($2+$5+$8)/3,($3+$6+$9)/3}' tri.tmp > center.tmp

# One meter normal slip
echo 0 -1 0 > slip.tmp

# Compute stress at triangle center
paste tri.tmp slip.tmp > triutil_flt.tmp
cp center.tmp triutil_sta.tmp
echo lame 40e9 shear 40e9 > haf.tmp
../bin/triutil \
    -flt triutil_flt.tmp \
    -sta triutil_sta.tmp \
    -strain triutil_stn.tmp \
    -stress triutil_sts.tmp \
    -haf haf.tmp \
    -geo

# Prepare fltinv files
awk '{print $1,$2,$3*1e3,$4,$5,$6*1e3,$7,$8,$9*1e3}' tri.tmp > fltinv_flt.tmp
awk '{print $4,$5,$6,$7,$8,$9}' triutil_sts.tmp > fltinv_sts.tmp
../bin/fltinv \
    -mode lsqr \
    -flt fltinv_flt.tmp \
    -gf:model triangle \
    -prests fltinv_sts.tmp \
    -geo \
    -haf haf.tmp \
    -o inversion.tmp
cat inversion.tmp
echo -1.06105159E-04  1.00004793E+00 > answer.tmp
test_values.sh inversion.tmp answer.tmp 2 "fltinv: triangular fault with self-prestress, geographic coordinates" || exit 1


#echo ----------
#echo Finished Test \#14
#echo ----------
#echo

#####
#	CLEAN UP
#####
rm *.tmp



