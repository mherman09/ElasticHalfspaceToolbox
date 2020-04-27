#!/bin/bash

###############################################################################
# Script for computing and plotting Coulomb stress changes on a dipping
# surface generated by an earthquake in an elastic half-space.
###############################################################################

###############################################################################
#	PARSE COMMAND LINE
###############################################################################
function usage() {
    echo "Usage: coul_dip.sh SRC_TYPE SRC_FILE [...options...]" 1>&2
    echo 1>&2
    echo "Required arguments" 1>&2
    echo "SRC_TYPE            Either MT (moment tensor) or FFM (finite fault model)"
    echo "SRC_FILE            Name of input fault file"
    echo "                      MT:  evlo evla evdp str dip rak mag"
    echo "                      FFM: finite fault model in subfault format"
    echo 1>&2
    echo "Optional arguments (many of these defined automatically)" 1>&2
    echo "-Rw/e/s/n           Map limits" 1>&2
    echo "-trg S/D/R          Target fault strike/dip/rake" 1>&2
    echo "-fric FRIC          Effective fault friction (default: 0.4)" 1>&2
    echo "-ref lo/la/dep      Reference point for dipping plane"
    echo "-plane str/dip      Dipping plane strike and dip"
    echo "-slipthr THR        FFM slip threshold (fraction of max)" 1>&2
    echo "-n NN               Number of stress contour grid points (default: 100/dimension)" 1>&2
    echo "-seg                Plot segmented finite faults" 1>&2
    echo "-emprel EMPREL      Empirical relation for rect source" 1>&2
    echo "-o FILENAME         Basename for output file" 1>&2
    echo "-noclean            Keep all temporary files (useful for debugging)"
    echo 1>&2
    exit 1
}
# Source type and source file are required
if [ $# -eq 0 ]
then
    usage
elif [ $# -lt 2 ]
then
    echo "coul_dip.sh: SRC_TYPE and SRC_FILE arguments required" 1>&2
    usage
fi
SRC_TYPE="$1"
SRC_FILE="$2"
shift
shift

# Check that the source type is an available option
if [ $SRC_TYPE != "FFM" -a $SRC_TYPE != "MT" -a $SRC_TYPE != "FSP" -a $SRC_TYPE != "FLT" ]
then
    echo "coul_dip.sh: source type must be FFM, FSP, MT, or FLT" 1>&2
    usage
fi

# Check that input file exists
if [ ! -f $SRC_FILE ]
then
    echo "coul_dip.sh: no source file $SRC_FILE found" 1>&2
    usage
fi


# Parse optional arguments
LIMS=""
NN="100"
TSTR=""
TDIP=""
TRAK=""
FRIC="0.4"
LON0=""
LAT0=""
Z0=""
STR0=""
DIP0=""
SEG="0"
EMPREL="WC"
OFILE="coul_dip"
THR="0.15"
CLEAN="Y"
while [ "$1" != "" ]
do
    case $1 in
        -R*) LIMS="$1";;
        -trg) shift
              TSTR=`echo $1 | awk -F"/" '{print $1}'`
              TDIP=`echo $1 | awk -F"/" '{print $2}'`
              TRAK=`echo $1 | awk -F"/" '{print $3}'`;;
        -fric) shift; FRIC=$1;;
        -ref) shift
              LON0=`echo $1 | awk -F"/" '{print $1}'`
              LAT0=`echo $1 | awk -F"/" '{print $2}'`
              Z0=`echo $1 | awk -F"/" '{print $3}'`;;
        -plane) shift
                STR0=`echo $1 | awk -F"/" '{print $1}'`
                DIP0=`echo $1 | awk -F"/" '{print $2}'`;;
        -slipthr) shift; THR=$1;;
        -seg) SEG="1" ;;
        -n) shift;NN=$1;NN=$(echo $NN | awk '{printf("%d"),$1}');;
        -emprel) shift;EMPREL="$1";;
        -o) shift;OFILE="$1" ;;
        -noclean) CLEAN="N";;
        *) echo "coul_dip.sh: no option \"$1\"" 1>&2; usage;;
    esac
    shift
done

PSFILE="$OFILE.ps"



###############################################################################
#	CHECK FOR REQUIRED EXECUTABLES
###############################################################################

# Check for executables in user-specified directory, if defined
if [ "$HDEF_BIN_DIR" != "" ]
then
    BIN_DIR=$(which $HDEF_BIN_DIR/o92util | xargs dirname)
    if [ "$BIN_DIR" == "" ]
    then
        echo "coul_dip.sh: executables not found in user-specified HDEF_BIN_DIR=$HDEF_BIN_DIR" 1>&2
        echo "Searching in other locations..." 1>&2
    fi
fi

# Check if o92util is set in PATH
if [ "$BIN_DIR" == "" ]
then
    BIN_DIR=$(which o92util | xargs dirname)
fi

# Check for o92util in same directory as script
if [ "$BIN_DIR" == "" ]
then
    BIN_DIR=$(which $(dirname $0)/o92util | xargs dirname)
fi

# Check for o92util in relative directory ../bin (assumes script is in Hdef/dir)
if [ "$BIN_DIR" == "" ]
then
    BIN_DIR=$(which $(dirname $0)/../bin/o92util | xargs dirname)
fi

# Check for o92util in relative directory ../build (assumes script is in Hdef/dir)
if [ "$BIN_DIR" == "" ]
then
    BIN_DIR=$(which $(dirname $0)/../build/o92util | xargs dirname)
fi

# Hdef executables are required for this script!
if [ "$BIN_DIR" == "" ]
then
    echo "coul_dip.sh: unable to find Hdef executables; exiting" 1>&2
    exit 1
fi

# GMT executables are required for this script!
GMT_DIR=$(which gmt | xargs dirname)
if [ "$GMT_DIR" == "" ]
then
    echo "coul_dip.sh: unable to find GMT executables; exiting" 1>&2
    exit 1
fi


###############################################################################
#	CLEAN UP FUNCTION
###############################################################################
function cleanup () {
    rm -f no_green_mwh.cpt
    rm -f coul.cpt
    rm -f coul_mpa.cpt
    rm -f coul.grd
    rm -f gmt.*
    rm -f *.tmp
}
if [ "$CLEAN" == "Y" ]
then
    trap "cleanup" 0 1 2 3 8 9
fi


###############################################################################
###############################################################################
# Everything below this point *should* be automated. This script requires the
# tools O92UTIL, GRID, FF2GMT, MTUTIL, and COLORTOOL from Hdef, and creates
# the figure using GMT 5 commands. All of the work is performed in the same
# directory that the script is run from.
###############################################################################
###############################################################################

###############################################################################
#	DEFINE APPEARANCE OF STRESS CONTOURS
###############################################################################
# Coulomb stress color palette
# cat > no_green_mwh.cpt << EOF
# # Color table using in Lab for Satellite Altimetry
# # For folks who hate green in their color tables
# # Designed by W.H.F. Smith, NOAA
# # Modified to make small values white
# -32	32/96/255	-28	32/96/255
# -28	32/159/255	-24	32/159/255
# -24	32/191/255	-20	32/191/255
# -20	0/207/255	-16	0/207/255
# -16	42/255/255	-12	42/255/255
# -12	85/255/255	-8	85/255/255
# -8	127/255/255	-3.2	127/255/255
# -3.2	255/255/255	0	255/255/255
# 0	255/255/255	3.2	255/255/255
# 3.2	255/240/0	8	255/240/0
# 8	255/191/0	12	255/191/0
# 12	255/168/0	16	255/168/0
# 16	255/138/0	20	255/138/0
# 20	255/112/0	24	255/112/0
# 24	255/77/0	28	255/77/0
# 28	255/0/0		32	255/0/0
# B	32/96/255
# F	255/0/0
# EOF
$BIN_DIR/colortool -hue 270,180 -chroma 40,0 -lightness 40,100 -gmt -T-1e6/0/1e5 > no_green_mwh.cpt
$BIN_DIR/colortool -hue 100,10 -chroma 100,30 -lightness 100,50 -gmt -T0/1e6/1e5 >> no_green_mwh.cpt


#####
#	INPUT FILES FOR DISPLACEMENT CALCULATION
#####
# Copy source file to temporary file
cp $SRC_FILE ./source.tmp || { echo "coul_dip.sh: error copying EQ source file" 1>&2; exit 1; }

# Elastic half-space properties
LAMDA="4e10"   # Lame parameter
MU="4e10"      # Shear modulus
echo "lame $LAMDA shearmod $MU" > haf.tmp


# If kinematics or target fault depth are given on the command line, use them for stress calculation
# Otherwise, use the slip*area-weighted average values from the source
if [ "$TRAK" == "" -o "$Z0" == "" -o "$DIP0" == "" ]
then
    if [ $SRC_TYPE == "FFM" ]
    then
        $BIN_DIR/ff2gmt -ffm source.tmp -flt flt.tmp || exit 1
    elif [ $SRC_TYPE == "FSP" ]
    then
        $BIN_DIR/ff2gmt -fsp source.tmp -flt flt.tmp || exit 1
    elif [ $SRC_TYPE == "MT" ]
    then
        awk '{print $7}' source.tmp | $BIN_DIR/mtutil -mag -mom mom.tmp || exit 1
        paste source.tmp mom.tmp | awk '{print $1,$2,$3,$4,$5,$6,$8,1,1}' > flt.tmp
    elif [ $SRC_TYPE == "FLT" ]
    then
        cp source.tmp flt.tmp
    fi
fi

# Calculate target strike/dip/rake from FFM if needed
if [ "$TRAK" != "" ]
then
    echo "Using target kinematics from the command line: str=$TSTR dip=$TDIP rak=$TRAK"
else
    if [ ! -f flt.tmp ]; then echo "$0: flt.tmp is required, but not created; this is a problem in the script" 1>&2; exit 1; fi

    # Calculate slip*area
    awk '{print $7*$8*$9}' flt.tmp > mom.tmp

    # Convert strike/dip/rake to moment tensor components
    awk '{print $4,$5,$6}' flt.tmp | $BIN_DIR/mtutil -sdr -mij mij.tmp || exit 1

    # Weight moment tensor components by slip*area and compute weighted mean strike/dip/rake
    paste mij.tmp mom.tmp |\
        awk '{print $1*$7,$2*$7,$3*$7,$4*$7,$5*$7,$6*$7}' |\
        awk 'BEGIN{rr=0;tt=0;pp=0;rt=0;rp=0;tp=0}{
            rr += $1
            tt += $2
            pp += $3
            rt += $4
            rp += $5
            tp += $6
        }END{print rr,tt,pp,rt,rp,tp}' |\
        $BIN_DIR/mtutil -mij -sdr sdr.tmp || exit 1

     # Finally, compute the average FFM strike to determine which target nodal plane to select
     MEAN_STR=$(awk 'BEGIN{sx=0;sy=0;d2r=3.14159265/180}{
                    sx+=sin($4*d2r)
                    sy+=cos($4*d2r)
                }END{print atan2(sx,sy)/d2r}' flt.tmp)
     awk 'BEGIN{d2r=3.14159265/180}{
         ffm_strx_1 = sin($1*d2r)
         ffm_stry_1 = cos($1*d2r)
         ffm_strx_2 = sin($4*d2r)
         ffm_stry_2 = cos($4*d2r)
         mean_strx = sin('"$MEAN_STR"'*d2r)
         mean_stry = cos('"$MEAN_STR"'*d2r)
         dp1 = ffm_strx_1*mean_strx + ffm_stry_1*mean_stry
         dp2 = ffm_strx_2*mean_strx + ffm_stry_2*mean_stry
         if (dp1>dp2) {
             print $1,$2,$3
         } else {
             print $4,$5,$6
         }
     }' sdr.tmp > j; mv j sdr.tmp

     # Save new strike, dip, and rake
     TSTR=$(awk '{printf("%.0f"),$1}' sdr.tmp)
     TDIP=$(awk '{printf("%.0f"),$2}' sdr.tmp)
     TRAK=$(awk '{printf("%.0f"),$3}' sdr.tmp)

    echo "Calculated target kinematics from the source fault: str=$TSTR dip=$TDIP rak=$TRAK"
fi
echo $TSTR $TDIP $TRAK $FRIC > trg.tmp

# Calculate target strike/dip/rake from FFM if needed
if [ "$Z0" != "" ]
then
    echo "Using reference point from command line: lon=$LON0 lat=$LAT0 dep=$Z0"

else
    if [ ! -f flt.tmp ]; then echo "$0: flt.tmp is required, but not created; this is a problem in the script" 1>&2; exit 1; fi

    # Calculate slip*area
    awk '{print $7*$8*$9}' flt.tmp > mom.tmp

    # Weight lon, lat, and depth by slip*area and compute weighted mean values
    LON0=$(paste flt.tmp mom.tmp | awk 'BEGIN{lo=0;m=0}{lo+=$1*$8;m+=$8}END{printf("%.1f"),lo/m}')
    LAT0=$(paste flt.tmp mom.tmp | awk 'BEGIN{la=0;m=0}{la+=$2*$8;m+=$8}END{printf("%.1f"),la/m}')
    Z0=$(paste flt.tmp mom.tmp | awk 'BEGIN{z=0;m=0}{z+=$3*$8;m+=$8}END{printf("%.1f"),z/m}')

    echo "Calculated reference point from the source fault: lon=$LON0 lat=$LAT0 dep=$Z0"
fi

# Calculate plane strike/dip from FFM if needed
if [ "$DIP0" != "" ]
then
    echo "Using plane geometry from the command line: str0=$STR0 dip0=$DIP0"
else
    STR0=$TSTR
    DIP0=$TDIP
    echo "Using plane from the source fault: str0=$STR0 dip0=$DIP0"
fi


#####
#       SET UP COMPUTATION GRID
#####
if [ -z $LIMS ]
then
    # Use "-auto" option in O92UTIL to get rough map limits
    D="10"  # Large initial increment, to get map limits without taking much time
    if [ $SRC_TYPE == "FFM" ]
    then
        ${BIN_DIR}/o92util -ffm source.tmp -auto $Z0 $D -haf haf.tmp -disp disp.tmp || \
            { echo "coul_dip.sh: error running o92util with FFM source" 1>&2; exit 1; }
    elif [ $SRC_TYPE == "FSP" ]
    then
        ${BIN_DIR}/o92util -fsp source.tmp -auto $Z0 $D -haf haf.tmp -disp disp.tmp  || \
            { echo "coul_dip.sh: error running o92util with FSP source" 1>&2; exit 1; }
    elif [ $SRC_TYPE == "MT" ]
    then
        ${BIN_DIR}/o92util -mag source.tmp -auto $Z0 $D -haf haf.tmp -disp disp.tmp  || \
            { echo "coul_dip.sh: error running o92util with MT source" 1>&2; exit 1; }
    elif [ $SRC_TYPE == "FLT" ]
    then
        ${BIN_DIR}/o92util -flt source.tmp -auto $Z0 $D -haf haf.tmp -disp disp.tmp  || \
            { echo "coul_dip.sh: error running o92util with FLT source" 1>&2; exit 1; }
    else
        echo "coul_dip.sh: no source type named \"$SRC_TYPE\"" 1>&2
        usage
    fi

    gmt gmtinfo -C disp.tmp > lims.tmp || { echo "coul_dip.sh: error determining disp.tmp limits" 1>&2; exit 1; }
    W=`awk '{print $1}' lims.tmp`
    E=`awk '{print $2}' lims.tmp`
    S=`awk '{print $3}' lims.tmp`
    N=`awk '{print $4}' lims.tmp`
    echo "Starting map limits: $W $E $S $N"

    # Determine if map has decent aspect ratio and correct as necessary
    # Mercator projection x and y lengths
    X=`echo $W $E | awk '{print $2-$1}'`
    Y=`echo $S $N |\
       awk '{
         v2 = log(sin(3.14159/4+$2/2*0.01745)/cos(3.14159/4+$2/2*0.01745))
         v1 = log(sin(3.14159/4+$1/2*0.01745)/cos(3.14159/4+$1/2*0.01745))
         print v2-v1
       }' |\
       awk '{print $1/0.017}'`

    # Check map aspect ratio (no skinnier than 1.4:1)
    FIX=`echo $X $Y |\
         awk '{
           if ($1>1.4*$2) {print "fixx"}
           else if ($2>1.4*$1) {print "fixy"}
           else {print 1}
         }'`

    # Reduce map limits in long dimension
    if [ $FIX == "fixx" ]
    then
        NEW=`echo $W $E $Y | awk '{print 0.5*($1+$2)-$3*0.70,0.5*($1+$2)+$3*0.70}'`
        W=`echo $NEW | awk '{print $1}'`
        E=`echo $NEW | awk '{print $2}'`
    elif [ $FIX == "fixy" ]
    then
        NEW=`echo $S $N $X $Y |\
             awk '{print 0.5*($1+$2)-0.7*$3/$4*($2-$1),0.5*($1+$2)+0.7*$3/$4*($2-$1)}'`
        S=`echo $NEW | awk '{print $1}'`
        N=`echo $NEW | awk '{print $2}'`
    fi
    # Round map limits to nearest 0.1
    W=`echo "$W $E" | awk '{printf("%.1f"),$1}'`
    E=`echo "$W $E" | awk '{printf("%.1f"),$2}'`
    S=`echo "$S $N" | awk '{printf("%.1f"),$1}'`
    N=`echo "$S $N" | awk '{printf("%.1f"),$2}'`
    echo "Final map limits:    $W $E $S $N"

else
    # Use map limits specified on command line
    W=`echo $LIMS | sed -e "s/\// /g" -e "s/-R//" | awk '{print $1}'`
    E=`echo $LIMS | sed -e "s/\// /g" -e "s/-R//" | awk '{print $2}'`
    S=`echo $LIMS | sed -e "s/\// /g" -e "s/-R//" | awk '{print $3}'`
    N=`echo $LIMS | sed -e "s/\// /g" -e "s/-R//" | awk '{print $4}'`
    echo "Using map limits from command line: $W $E $S $N"
fi


# Create (NN x NN) point dipping grid
$BIN_DIR/grid -x $W $E -nx $NN -y $S $N -ny $NN -dip $LON0 $LAT0 $Z0 $STR0 $DIP0 -o sta.tmp -geo || exit 1


#####
#	COMPUTE COULOMB STRESS CHANGE
#####
if [ $SRC_TYPE == "FFM" ]
then
    ${BIN_DIR}/o92util -ffm source.tmp -sta sta.tmp -haf haf.tmp -trg trg.tmp -coul coul.tmp -thr $THR -prog || \
        { echo "coul_dip.sh: error running o92util with FFM source" 1>&2; exit 1; }
elif [ $SRC_TYPE == "FSP" ]
then
    ${BIN_DIR}/o92util -fsp source.tmp -sta sta.tmp -haf haf.tmp -trg trg.tmp -coul coul.tmp -thr $THR -prog || \
        { echo "coul_dip.sh: error running o92util with FSP source" 1>&2; exit 1; }
elif [ $SRC_TYPE == "MT" ]
then
    ${BIN_DIR}/o92util -mag source.tmp -sta sta.tmp -haf haf.tmp -trg trg.tmp -coul coul.tmp -thr $THR -prog -empirical ${EMPREL} || \
        { echo "coul_dip.sh: error running o92util with MT source" 1>&2; exit 1; }
elif [ $SRC_TYPE == "FLT" ]
then
    ${BIN_DIR}/o92util -flt source.tmp -sta sta.tmp -haf haf.tmp -trg trg.tmp -coul coul.tmp -thr $THR -prog || \
        { echo "coul_dip.sh: error running o92util with FLT source" 1>&2; exit 1; }
else
    echo "coul_dip.sh: no source type named $SRC_TYPE" 1>&2
    usage
fi


#####
#	PLOT RESULTS
#####
gmt set PS_MEDIA 8.5ix11i

PORTRAIT=`echo $X $Y | awk '{if($1<$2){print "-P"}}'`
PROJ="-JM5i $PORTRAIT"
LIMS="-R$W/$E/$S/$N"

echo 0 0 | gmt psxy $PROJ $LIMS -K -X1i -Y1.5i > $PSFILE

# Colored grid of Coulomb stress changes
gmt makecpt -T-1e5/1e5/1e4 -C./no_green_mwh.cpt -D > coul.cpt || exit 1
gmt makecpt -T-1e-1/1e-1/1e-2 -C./no_green_mwh.cpt -D > coul_mpa.cpt || exit 1
awk '{print $1,$2,$4}' coul.tmp | gmt xyz2grd -Gcoul.grd $LIMS -I${NN}+/${NN}+ || exit 1
gmt grdimage coul.grd $PROJ $LIMS -Ccoul.cpt -K -O >> $PSFILE || exit 1
gmt psscale -D0/-0.9i+w5.0i/0.2ih+ml -Ccoul_mpa.cpt -Ba0.05 -Bg0.01 \
    -B+l"Coulomb Stress Change (MPa)" -K -O >> $PSFILE || exit 1

# Map stuff
ANNOT=`echo $W $E | awk '{if($2-$1<=10){print 1}else{print 2}}'`
gmt psbasemap $PROJ $LIMS -Bxa${ANNOT} -Bya1 -BWeSn -K -O --MAP_FRAME_TYPE=plain >> $PSFILE

echo "Just a heads up - Ghostscript 9.24 no longer supports however GMT defines transparency" 1>&2
echo "Ghostscript 9.23-1 still works fine for me with transparency" 1>&2
gmt pscoast $PROJ $LIMS -W1p,55 -G205@95 -N1/0.5p -Dh -K -O -t80 >> $PSFILE || exit 1

# Plot FFM slip contours
if [ $SRC_TYPE == "FFM" -o $SRC_TYPE == "FSP" ]
then
    case $SRC_TYPE in
        FFM) OPT="-ffm source.tmp";;
        FSP) OPT="-fsp source.tmp";;
    esac
    if [ $SEG -eq 0 ]
    then
        ${BIN_DIR}/ff2gmt $OPT -slip slip.tmp -clip clip.tmp -epi epi.tmp || \
            { echo "coul_hor.sh: ff2gmt error" 1>&2; exit 1; }
    else
        ${BIN_DIR}/ff2gmt $OPT -slip slip.tmp -clipseg clip.tmp -epi epi.tmp || \
            { echo "coul_hor.sh: ff2gmt error" 1>&2; exit 1; }
    fi
    MAXSLIP=`awk '{print $3}' slip.tmp |\
             awk 'BEGIN{mx=0}{if($1>mx){mx=$1}}END{print mx}' |\
             awk '{print $1}'`
    CONT=`echo $MAXSLIP |\
          awk '{
            if ($1>=50) {print 10}
            else if ($1>=20) {print 5}
            else if ($1>=10) {print 2}
            else if ($1>=2) {print 1}
            else {print 0.5}
          }'`
    echo $CONT $MAXSLIP | awk '{for (i=$1;i<=$2;i=i+$1){print i,"C"}}' > junk || \
        { echo "coul_hor.sh: error making contour definition file" 1>&2; exit 1; }
    awk '{print $1,$2,$3}' slip.tmp |\
        gmt surface -Gslip.grd -I0.10/0.10 -Tb1 -Ti0.25 $LIMS || \
        { echo "coul_hor.sh: GMT surface error" 1>&2; exit 1; }
    gmt psclip clip.tmp $PROJ $LIMS -K -O >> $PSFILE || \
        { echo "coul_hor.sh: psclip error" 1>&2; exit 1; }
    gmt grdcontour slip.grd $PROJ $LIMS -W1p,205/205/205 -Cjunk -K -O -t40 >> $PSFILE || \
        { echo "coul_hor.sh: grdcontour error" 1>&2; exit 1; }
    gmt psclip -C -K -O >> $PSFILE || \
        { echo "coul_hor.sh: psclip error" 1>&2; exit 1; }
    gmt psxy clip.tmp $PROJ $LIMS -W1p,205/205/205 -K -O -t40 >> $PSFILE || \
        { echo "coul_hor.sh: psxy error" 1>&2; exit 1; }
    rm junk
else
    echo
    # awk '{print $1,$2,$4,$5,$6}' rect.out |\
    #     gmt psxy $PROJ $LIMS -SJ -W1p,205/205/205 -K -O -t40 >> $PSFILE
fi


# Plot epicenter
if [ $SRC_TYPE == "FFM" -o $SRC_TYPE == "FSP" ]
then
    LONX=`awk '{print $1}' epi.tmp`
    LATX=`awk '{print $2}' epi.tmp`
    echo $LONX $LATX |\
        gmt psxy $PROJ $LIMS -Sa0.15i -W1p,55/55/55 -K -O -t50 >> $PSFILE || \
        { echo "coul_hor.sh: psxy error plotting epicenter" 1>&2; exit 1; }
fi


# Legend (all coordinates are in cm from the bottom left)
X1="0.2"
X2="3.0"
Y1="0.2"
Y2="3.5"
XM=`echo $X1 $X2 | awk '{print 0.5*($1+$2)}'`
gmt psxy -JX10c -R0/10/0/10 -W1p -Gwhite -K -O >> $PSFILE << EOF || exit 1
$X1 $Y1
$X1 $Y2
$X2 $Y2
$X2 $Y1
$X1 $Y1
EOF
gmt pstext -JX10c -R0/10/0/10 -F+f+j -N -K -O >> $PSFILE << EOF
$XM 3.2 12,1 CM @_Target Faults@_
$XM 2.7 10,0 CM Strike/Dip/Rake
$XM 2.3 10,0 CM $TSTR\260/$TDIP\260/$TRAK\260
$XM 1.8 10,0 CM Depth: $Z km
EOF
if [ $SRC_TYPE == "FFM" -o $SRC_TYPE == "FSP" ]
then
    echo $X2 $Y1 $CONT |\
        awk '{
          if($3==1) {print $1+0.2,$2,"10,2 LB FFM Slip Contours: "$3" meter"}
          else      {print $1+0.2,$2,"10,2 LB FFM Slip Contours: "$3" meters"}
        }' |\
        gmt pstext -JX10c -R0/10/0/10 -F+f+j -N -K -O >> $PSFILE || exit 1
fi
# Schematic of target faults
XF="1.0"  # center of fault in x direction
YF="0.8"  # center of fault in y direction
LEN="1.0" # length of slip vector arrows
D="0.2"   # offset of slip vector arrows
FLT="0.8" # side length of square fault
SV=`echo $TSTR $TDIP $TRAK |\
    awk '{
      pi = 4*atan2(1,1)
      d2r = pi/180
      coss = cos((90-$1)*d2r)
      sins = sin((90-$1)*d2r)
      cosd = cos($2*d2r)
      sind = sin($2*d2r)
      cosr = cos($3*d2r)
      sinr = sin($3*d2r)
      x =  cosr*coss - sinr*cosd*sins
      y =  cosr*sins + sinr*cosd*coss
      z = sinr*sind
      print atan2(y,x)/d2r
    }'`
DX=`echo $TSTR $D | awk '{print $2*sin(($1+90)*0.01745)}'`
DY=`echo $TSTR $D | awk '{print $2*cos(($1+90)*0.01745)}'`
# Footwall slip vector
echo $DX $DY $SV $XF $YF $LEN |\
    awk '{print (-1)*$1+$4,(-1)*$2+$5,$3+180,$6}' |\
    gmt psxy -JX10c -R0/10/0/10 -Sv8p+e+jc+a45 -W1p -Gblack -K -O >> $PSFILE || exit 1
# Fault square projected onto horizontal surface
echo $XF $YF $TSTR $FLT `echo $TDIP | awk '{print 0.7*cos($1*0.01745)}'` |\
    gmt psxy -JX10c -R0/10/0/10 -SJ -W1p,55/55/55 -Gwhite -K -O -t25 >> $PSFILE || exit 1
# highlight updip edge of fault
echo $TSTR $TDIP $FLT $XF $YF |\
    awk '{
      d = $3*0.5
      print d*sin(($1-90)*0.01745)*cos($2*0.01745)+$4,
              d*cos(($1-90)*0.01745)*cos($2*0.01745)+$5,
                      $1,$3}' |\
    gmt psxy -JX10c -R0/10/0/10 -SV10p+jc -W2p,darkgreen -K -O -t25 >> $PSFILE || exit 1
# Hanging wall slip vector
echo $DX $DY $SV $XF $YF $LEN |\
    awk '{print $1+$4,$2+$5,$3,$6}' |\
    gmt psxy -JX10c -R0/10/0/10 -Sv8p+e+jc+a45 -W1p -Gblack -K -O >> $PSFILE || exit 1

# Beachball
XF="2.3"
TRAK=`echo $TRAK | awk '{if($1==0){print 0.1}else{print $1}}'`
echo $XF $YF 5 $TSTR $TDIP $TRAK 5 |\
    gmt psmeca -JX10c -R0/10/0/10 -Sa${FLT}c -G155/155/155 -K -O >> $PSFILE || exit 1

echo 0 0 | gmt psxy $PROJ $LIMS -O >> $PSFILE


#####
#	CLEAN UP
#####
ps2pdf $PSFILE
rm no_green_mwh.cpt
