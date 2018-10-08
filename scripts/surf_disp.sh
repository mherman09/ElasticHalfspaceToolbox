#!/bin/bash

###############################################################################
# Script for automatically computing and plotting surface displacements 
# generated by an earthquake in an elastic half-space.
###############################################################################

gmt set PS_MEDIA letter

if [ ! -f polar_mwh.cpt ]; then
cat > polar_mwh.cpt << EOF
# Simulates the POLAR colormap in Matlab
# Modified to make small values white
-1	blue	-0.1	white
-0.1	white	0.1	white
0.1	white	1	red
EOF
fi

###############################################################################
# The user can specify the following variables:
#  DISP_THR (Horizontal) displacement threshold for plotting as bold vectors
###############################################################################

# Horizontal displacements below DISP_THR will be faded
DISP_THR="0.05" # meters

###############################################################################
#	PARSE COMMAND LINE TO GET SOURCE TYPE AND FILE NAME
###############################################################################

function USAGE() {
echo
echo "Usage: surf_disp.sh SRC_TYPE SRC_FILE [-Rw/e/s/n] [-seg] [-Tvmin/vmax/dv] [-getscript] [-novector] [-o FILENAME] [-gps GPS_FILE] [-vecscale SCALE] [-veclbl LENGTH] [-emprel EMPREL]"
echo "    SRC_TYPE    Either MT (moment tensor), FLT (fault format), FFM (finite fault model), or FSP (SRCMOD format finite fault model)"
echo "    SRC_FILE        Name of input file"
echo "                      MT:  EVLO EVLA EVDP STR DIP RAK MAG"
echo "                      FFM: finite fault model in static subfault format"
echo "                      FSP: finite fault model in SRCMOD FSP format"
echo "    -Rw/e/s/n       Define map limits"
echo "    -nvert          Number of background grid points (1D; default: 100)"
echo "    -nvec           Number of vectors (1D; default: 20)"
echo "    -seg            Plot segmented finite faults"
echo "    -Tvmin/vmax/dv  Define vertical color bar limits"
echo "    -getscript      Copy surf_disp.sh to working directory"
echo "    -novector       Do not plot horizontal vectors"
echo "    -o FILENAME     Define basename for output file (will produce FILENAME.ps and FILENAME.pdf)"
echo "    -gps GPS_FILE   Compare synthetic and observed displacements (GPS_FILE format: lon lat edisp ndisp zdisp)"
echo "    -gpssta STAFILE Compare synthetic and observed displacements (GPS_FILE format: lon lat edisp ndisp zdisp)"
echo "    -vecscale SCALE  Scale vectors by SCALE inches (default tries to define a best scale)"
echo "    -veclbl LENGTH   Vector in legend has length LENGTH (default tries to define best length)"
echo "    -emprel EMPREL   Empirical relation to turn moment tensor into rect source (see man o92util"
echo
exit
}
if [ $# -lt 2 ]
then
    echo "!! Error: SRC_TYPE and SRC_FILE arguments required"
    echo "!!        Map limits (-Rw/e/s/n) optional"
    USAGE
fi
SRC_TYPE="$1"
SRC_FILE="$2"
# Check that source type is correct
if [ $SRC_TYPE != "FFM" -a $SRC_TYPE != "MT" -a $SRC_TYPE != "FSP" -a $SRC_TYPE != "FLT" ]
then
    echo "!! Error: source type must be FFM, FSP, MT, or FLT"
    USAGE
fi
# Check that input file exists
if [ ! -f $SRC_FILE ]
then
    echo "!! Error: no source file $SRC_FILE found"
    USAGE
fi
# Parse optional arguments
LIMS=""
SEG="0"
VERT_CPT_RANGE=""
GETSCRIPT="N"
PLOT_VECT="Y"
OFILE="surf_disp"
GPS_FILE=""
GPS_STA_FILE=""
VEC_SCALE=""
DISP_LBL=""
EMPREL="WC"
NN="100" # Background vertical displacement grid is (NN x NN) points
NN_SAMP="20" # Horizontal vectors grid is (NN_SAMP x NN_SAMP) points
shift;shift
while [ "$1" != "" ]
do
    case $1 in
        -R*) LIMS="$1";;
        -T*) VERT_CPT_RANGE="$1";;
        -seg) SEG="1" ;;
        -novect*) PLOT_VECT="N" ;;
        -getscript) GETSCRIPT="Y" ;;
        -o) shift;OFILE="$1" ;;
        -gps) shift;GPS_FILE="$1" ;;
        -gpssta) shift;GPS_STA_FILE="$1" ;;
        -vecscale) shift;VEC_SCALE="$1" ;;
        -veclbl) shift;DISP_LBL="$1" ;;
        -nvert)shift;NN="$1";;
        -nvec)shift;NN_SAMP="$1";;
        -emprel)shift;EMPREL="$1";;
        *) echo "!! Error: no option \"$1\""; USAGE;;
    esac
    shift
done

PSFILE="$OFILE.ps"

if [ $GETSCRIPT == "Y" ]
then
    cp $0 .
fi

###############################################################################
# The appearance of displacements plotted on the map is controlled by awk
# commands created within this script. To adjust the coloring, scaling and
# labeling on the figure, adjust these awk commands as necessary.
###############################################################################

# Define the value at which the color bar for vertical displacements 
# will saturate, based on maximum vertical displacements.
# IF (MAXIMUM VERTICAL DISPLACEMENT >= THRESHOLD) {USE THIS SATURATION VALUE}
cat > vert_scale_max.awk << EOF
{
  if (\$1>=2) {print 2}
  else if (\$1>=1) {print 1}
  else if (\$1>=0.5) {print 0.5}
  else if (\$1>=0.2) {print 0.2}
  else {print 0.1}
}
EOF

# Define the annotation increment for the vertical displacement scale bar,
# based on the saturation value above.
# IF (MAXIMUM VERTICAL DISPLACEMENT >= THRESHOLD) {USE THIS ANNOTATION INCREMENT}
cat > vert_scale_lbl.awk << EOF
{
  if (\$1>=2) {print 0.5}
  else if (\$1>=1) {print 0.2}
  else if (\$1>=0.5) {print 0.1}
  else if (\$1>=0.2) {print 0.05}
  else {print 0.02}
}
EOF

# Use the maximum horizontal displacement to define the length of the
# vector in the legend.
# IF (MAXIMUM HORIZONTAL DISPLACEMENT >= THRESHOLD) {USE THIS LENGTH IN METERS AS LEGEND VECTOR}
cat > vect_label.awk << EOF
{
  if (\$1>10) {print 5}
  else if (\$1>5) {print 2}
  else if (\$1>1) {print 1}
  else {print 0.5}
}
EOF

# Use the maximum horizontal displacement to define the vector scaling.
# Larger earthquakes should have a smaller scale factor for all of the
# vectors to fit on the map.
# IF (MAXIMUM HORIZONTAL DISPLACEMENT >= THRESHOLD) {USE THIS VECTOR SCALING}
cat > vect_scale.awk << EOF
{
  if (\$1>10) {print 0.3}
  else if (\$1>5) {print 0.8}
  else if (\$1>1) {print 1.6}
  else {print 4}
}
EOF

###############################################################################
###############################################################################
# Everything below this point should be automated. This script requires the
# tools O92UTIL, GRID, and FF2GMT from Matt's codes, and creates the figure
# using GMT 5 commands. All of the work is performed in the same directory
# that the script is run from.
###############################################################################
###############################################################################

#####
#	INPUT FILES FOR DISPLACEMENT CALCULATION
#####
if [ $SRC_TYPE == "FFM" ]
then
    # Copy FFM to new file name
    cp $SRC_FILE ./ffm.dat
elif [ $SRC_TYPE == "FSP" ]
then
    # Copy FSP to new file name
    cp $SRC_FILE ./fsp.dat
elif [ $SRC_TYPE == "MT" ]
then
    # Copy MT to new file name
    cp $SRC_FILE ./mt.dat
elif [ $SRC_TYPE == "FLT" ]
then
    # Copy FLT to new file name
    cp $SRC_FILE ./flt.dat
else
    echo "!! Error: no input source type named $SRC_TYPE"
    USAGE
fi

# Elastic half-space properties
LAMDA="4e10"   # Lame parameter
MU="4e10"      # Shear modulus
echo "Lame $LAMDA $MU" > haf.dat

#####
#	SET UP COMPUTATION GRID
#####
Z="0.0" # Depth is zero on the surface
if [ -z $LIMS ]
then
    # Use "-auto" option in O92UTIL to get rough map limits
    D="10"  # Large initial increment, to get map limits without taking much time
    if [ $SRC_TYPE == "FFM" ]
    then
        o92util -ffm ffm.dat -auto h $Z $D -haf haf.dat -disp disp.out > auto.dat
    elif [ $SRC_TYPE == "FSP" ]
    then
        o92util -fsp fsp.dat -auto h $Z $D -haf haf.dat -disp disp.out > auto.dat
    elif [ $SRC_TYPE == "MT" ]
    then
        o92util -mag mt.dat -auto h $Z $D -haf haf.dat -disp disp.out > auto.dat
    elif [ $SRC_TYPE == "FLT" ]
    then
        o92util -flt flt.dat -auto h $Z $D -haf haf.dat -disp disp.out > auto.dat
    fi
    rm autosta.dat
    W=`grep " W: " auto.dat | awk '{print $2}'`
    E=`grep " E: " auto.dat | awk '{print $2}'`
    S=`grep " S: " auto.dat | awk '{print $2}'`
    N=`grep " N: " auto.dat | awk '{print $2}'`
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
    W=`echo $LIMS | sed -e "s/\// /g" -e "s/-R//" | awk '{print $1}'`
    E=`echo $LIMS | sed -e "s/\// /g" -e "s/-R//" | awk '{print $2}'`
    S=`echo $LIMS | sed -e "s/\// /g" -e "s/-R//" | awk '{print $3}'`
    N=`echo $LIMS | sed -e "s/\// /g" -e "s/-R//" | awk '{print $4}'`
    echo "Using map limits from command line: $W $E $S $N"
fi

# Locations of displacement computations
grid -x $W $E -nx $NN -y $S $N -ny $NN -z $Z -o sta.dat
if [ -z $GPS_FILE ]
then
    # Create (NN x NN) point horizontal grid for vectors
    grid -x $W $E -nx $NN_SAMP -y $S $N -ny $NN_SAMP -z $Z -o sta_samp.dat
else
    # Take points from GPS file for vectors
    awk '{print $1,$2,0}' $GPS_FILE > sta_samp.dat
fi

#####
#	COMPUTE SURFACE DISPLACEMENTS
#####
if [ $SRC_TYPE == "FFM" ]
then
    o92util -ffm ffm.dat -sta sta.dat -haf haf.dat -disp disp.out -prog
    o92util -ffm ffm.dat -sta sta_samp.dat -haf haf.dat -disp disp_samp.out -prog
elif [ $SRC_TYPE == "FSP" ]
then
    o92util -fsp fsp.dat -sta sta.dat -haf haf.dat -disp disp.out -prog
    o92util -fsp fsp.dat -sta sta_samp.dat -haf haf.dat -disp disp_samp.out -prog
elif [ $SRC_TYPE == "MT" ]
then
    o92util -mag mt.dat -sta sta.dat -haf haf.dat -disp disp.out -prog -empirical ${EMPREL}p
    o92util -mag mt.dat -sta sta_samp.dat -haf haf.dat -disp disp_samp.out -prog -empirical $EMPREL -gmt rect.out
elif [ $SRC_TYPE == "FLT" ]
then
    o92util -flt flt.dat -sta sta.dat -haf haf.dat -disp disp.out -prog
    o92util -flt flt.dat -sta sta_samp.dat -haf haf.dat -disp disp_samp.out -prog -gmt rect.out
else
    echo !! Error: no source type named $SRC_TYPE
    USAGE
fi

# Extract maximum vertical displacements and determine scale parameters for gridding
MINMAX=`awk '{print $6}' disp.out | awk 'BEGIN{mn=1e10;mx=-1e10}{if($1<mn){mn=$1};if($1>mx){mx=$1}}END{print mn,mx}'`
V1=`echo $MINMAX | awk '{if($1<0){print $1*(-1)}else{print $1}}'`
V2=`echo $MINMAX | awk '{if($2<0){print $2*(-1)}else{print $2}}'`
T=`echo $V1 $V2 | awk '{if($1>$2){print $1}else{print $2}}' | awk -f vert_scale_max.awk`
DT=`echo $T | awk -f vert_scale_lbl.awk`

#####
#	PLOT RESULTS
#####
PORTRAIT=`echo $X $Y | awk '{if($1<$2){print "-P"}}'`
PROJ="-JM5i $PORTRAIT"
LIMS="-R$W/$E/$S/$N"

# Colored grid of vertical displacements plotted under horizontal displacement vectors
if [ -z $VERT_CPT_RANGE ]
then
    gmt makecpt -T-$T/$T/0.01 -C./polar_mwh.cpt -D > vert.cpt
else
    gmt makecpt $VERT_CPT_RANGE -C./polar_mwh.cpt -D > vert.cpt
fi
awk '{print $1,$2,$6}' disp.out | gmt xyz2grd -Gvert.grd $LIMS -I$NN+/$NN+
gmt grdimage vert.grd $PROJ $LIMS -Cvert.cpt -Y1.5i -K > $PSFILE
gmt psscale -D0i/-0.9i+w5.0i/0.2i+h+ml -Cvert.cpt -Ba$DT -Bg$DT -B+l"Vertical Displacement (m)" -K -O >> $PSFILE

# Map stuff
ANNOT=`echo $W $E | awk '{if($2-$1<=10){print 1}else{print 2}}'`
gmt psbasemap $PROJ $LIMS -Bxa${ANNOT} -Bya1 -BWeSn -K -O --MAP_FRAME_TYPE=plain >> $PSFILE
gmt pscoast $PROJ $LIMS -W1p,105/105/105 -G205/205/205 -N1/0.5p -Dh -K -O -t85 >> $PSFILE

# Plot FFM slip contours
if [ $SRC_TYPE == "FFM" -o $SRC_TYPE == "FSP" ]
then
    case $SRC_TYPE in
        FFM)OPT="-ffm ffm.dat";;
        FSP)OPT="-fsp fsp.dat";;
    esac
    if [ $SEG -eq 0 ]
    then
        ff2gmt $OPT -slip slip.out -clip clip.out -epi epi.out
    else
        ff2gmt $OPT -slip slip.out -clipseg clip.out -epi epi.out
    fi
    MAXSLIP=`awk '{print $3}' slip.out | awk 'BEGIN{mx=0}{if($1>mx){mx=$1}}END{print mx}' | awk '{print $1}'`
    CONT=`echo $MAXSLIP |\
          awk '{
            if ($1>=50) {print 10}
            else if ($1>=20) {print 5}
            else if ($1>=10) {print 2}
            else if ($1>=2) {print 1}
            else {print 0.5}
          }'`
    echo $CONT $MAXSLIP | awk '{for (i=$1;i<=$2;i=i+$1){print i,"C"}}' > junk
    awk '{print $1,$2,$3}' slip.out |\
        gmt surface -Gslip.grd -I0.10/0.10 -Tb1 -Ti0.25 $LIMS
    gmt psclip clip.out $PROJ $LIMS -K -O >> $PSFILE
    gmt grdcontour slip.grd $PROJ $LIMS -W1p,205/205/205 -Cjunk -K -O -t40 >> $PSFILE
    gmt psclip -C -K -O >> $PSFILE
    gmt psxy clip.out $PROJ $LIMS -W1p,205/205/205 -K -O -t40 >> $PSFILE
    rm junk
else
    awk '{print $1,$2,$4,$5,$6}' rect.out |\
        gmt psxy $PROJ $LIMS -SJ -W1p,205/205/205 -K -O -t40 >> $PSFILE
fi

# Plot epicenter
if [ $SRC_TYPE == "FFM" -o $SRC_TYPE == "FSP" ]
then
    LONX=`awk '{print $1}' epi.out`
    LATX=`awk '{print $2}' epi.out`
    #LONX=`sed -n -e "3p" ffm.dat | sed -e "s/.*Lon:/Lon:/" | awk '{print $2}'`
    #LATX=`sed -n -e "3p" ffm.dat | sed -e "s/.*Lon:/Lon:/" | awk '{print $4}'`
    echo $LONX $LATX |\
        gmt psxy $PROJ $LIMS -Sa0.15i -W1p,55/55/55 -K -O -t50 >> $PSFILE
fi

if [ $PLOT_VECT == "Y" ]
then
    if [ -z $GPS_FILE ]
    then
        # If max displacement is much larger than other displacements, don't use it
        MAXLN=`awk '{print sqrt($4*$4+$5*$5)}' disp_samp.out |\
               awk 'BEGIN{m1=0;m2=0}
                    {if($1>m1){m2=m1;m1=$1;ln=NR}}
                    END{if(m1>2*m2){print ln}else{print 0}}'`
    else
        MAXLN=0
    fi
    # Scale vectors differently depending on maximum horizontal displacement
    MAX=`awk '{if(NR!='"$MAXLN"'){print sqrt($4*$4+$5*$5)}}' disp_samp.out |\
         awk 'BEGIN{mx=0}{if($1>mx){mx=$1}}END{print mx}' | awk '{print $1}'`
    if [ -z $DISP_LBL ]
    then
        DISP_LBL=`echo $MAX | awk -f vect_label.awk`
    fi
    if [ -z $VEC_SCALE ]
    then
        VEC_SCALE=`echo $MAX | awk -f vect_scale.awk`
    fi
    MAX=0.5
    # Plot differently depending on whether data are grid or GPS
    if [ -z $GPS_FILE ]
    then
        # Plot displacements smaller than DISP_THR faded
        awk '{
            if (sqrt($4*$4+$5*$5)<'"$DISP_THR"') {
              print $1,$2,atan2($4,$5)/0.01745,'"$VEC_SCALE"'*sqrt($4*$4+$5*$5)
            }
        }' disp_samp.out |\
            gmt psxy $PROJ $LIMS -SV10p+e+a45+n${MAX} -W2p,175/175/175 -K -O >> $PSFILE
        # Plot larger displacements in black
        awk '{
            if (sqrt($4*$4+$5*$5)>='"$DISP_THR"'&&NR!='"$MAXLN"') {
              print $1,$2,atan2($4,$5)/0.01745,'"$VEC_SCALE"'*sqrt($4*$4+$5*$5)
            }
        }' disp_samp.out |\
            gmt psxy $PROJ $LIMS -SV10p+e+a45+n${MAX} -W2p,black -K -O >> $PSFILE
    else
        # Color vertical motions same as background synthetic verticals
        awk '{print $1,$2,$5}' $GPS_FILE | gmt psxy $PROJ $LIMS -Sc0.06i -W0.5p -Cvert.cpt -K -O >> $PSFILE
        awk '{if(NF==6)print $1,$2,"4,0 LM",$6}' $GPS_FILE |\
            gmt pstext $PROJ $LIMS -F+f+j -D0.04i/0 -K -O >> $PSFILE
        # Plot horizontal GPS displacements in black
        awk '{print $1,$2,atan2($3,$4)/0.01745,'"$VEC_SCALE"'*sqrt($3*$3+$4*$4)}' $GPS_FILE |\
            gmt psxy $PROJ $LIMS -SV10p+e+a45+n${MAX} -W2p,black -K -O >> $PSFILE
        # Plot synthetic displacements in another color
        awk '{print $1,$2,atan2($4,$5)/0.01745,'"$VEC_SCALE"'*sqrt($4*$4+$5*$5)}' disp_samp.out |\
            gmt psxy $PROJ $LIMS -SV10p+e+a45+n${MAX} -W2p,orange -K -O >> $PSFILE
    fi
fi
if [ "$GPS_STA_FILE" != "" ]
then
    gmt psxy $GPS_STA_FILE $PROJ $LIMS -Sc0.06i -Ggreen -W0.5p -K -O >> $PSFILE
fi


# Legend (all coordinates are in cm from the bottom left)
if [ $PLOT_VECT == "Y" ]
then
    echo 0.2 0.2 > legend.tmp
    echo 0.2 1.5 >> legend.tmp
    echo $VEC_SCALE $DISP_LBL | awk '{print $1*$2+0.6,1.5}' >> legend.tmp
    echo $VEC_SCALE $DISP_LBL | awk '{print $1*$2+0.6,0.2}' >> legend.tmp
    echo 0.2 0.2 >> legend.tmp
    gmt psxy legend.tmp -JX10c -R0/10/0/10 -W1p -Gwhite -K -O >> $PSFILE
    echo $VEC_SCALE $DISP_LBL |\
        awk '{print 0.4,0.5,0,$1*$2}' |\
        gmt psxy -JX -R -Sv10p+e+a45 -W2p,black -N -K -O >> $PSFILE
    echo $VEC_SCALE $DISP_LBL |\
        awk '{if ($2!=1) {print $1*$2*0.5+0.4,1.0,12","0,"CM",$2,"meters"}
              else{print $1*$2*0.5+0.4,1.0,12","0,"CM",$2,"meter"}}' |\
        gmt pstext -JX -R -F+f+j -N -K -O >> $PSFILE
    if [ -z $GPS_FILE ]
    then
        echo $VEC_SCALE $DISP_LBL |\
            awk '{print $1*$2+0.7,"0.2 10,2 LB Displacements less than '"$DISP_THR"' m are in light grey"}' |\
            gmt pstext -JX -R -F+f+j -Gwhite -N -K -O >> $PSFILE
    else
        echo $VEC_SCALE $DISP_LBL |\
            awk '{print $1*$2+0.7,"0.2 10,2 LB Observed=black; Synthetic=color"}' |\
            gmt pstext -JX -R -F+f+j -Gwhite -N -K -O >> $PSFILE
    fi
else
    VEC_SCALE=0
    DISP_LBL=0
fi

if [ $SRC_TYPE == "FFM" -o $SRC_TYPE == "FSP" ]
then
    echo $VEC_SCALE $DISP_LBL $CONT |\
        awk '{
          if($3==1) {print $1*$2+0.7,0.6,"10,2 LB FFM Slip Contours: "$3" meter"}
          else      {print $1*$2+0.7,0.6,"10,2 LB FFM Slip Contours: "$3" meters"}
        }' |\
        gmt pstext -JX10c -R0/10/0/10 -F+f+j -N -K -O >> $PSFILE
fi

echo 0 0 | gmt psxy $PROJ $LIMS -O >> $PSFILE

#####
#	CLEAN UP
#####
ps2pdf $PSFILE
rm *.awk
rm polar_mwh.cpt



