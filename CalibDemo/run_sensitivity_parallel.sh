#!/bin/bash


#---------- Setup ----------#

soilfile='soil_properties.nc'
gwfile='GWBUCKPARM.nc'
fulldomfile='Fulldom.nc'

baserundir=`grep -m 1 -F runDir namelist.calib | cut -d "<" -f2 | cut -d "-" -f2`
echo $baserundir
baserundir=`echo $baserundir | sed 's/\"//g'`
echo $baserundir

paramfile=`echo ${baserundir}/params_new.txt`

#declare -a soilp_mult_list=('bexp' 'smcmax' 'dksat')
declare -a soilp_mult_list=('bexp' 'smcmax' 'dksat' 'CWPVT' 'VCMX25' 'MP' 'HVT' 'MFSNO')
declare -a soilp_abs_list=('slope' 'refkdt')
declare -a fulldom_mult_list=()
declare -a fulldom_abs_list=('RETDEPRTFAC' 'LKSATFAC' 'OVROUGHRTFAC')
declare -a hydrotab_mult_list=('smcmax' 'dksat')
declare -a hydrotab_abs_list=()
declare -a gw_mult_list=()
declare -a gw_abs_list=('Zmax' 'Expon')
#declare -a mptab_mult_list=('CWPVT' 'VCMX25' 'MP' 'HVT')
#declare -a mptab_abs_list=('MFSNO')
declare -a mptab_mult_list=()
declare -a mptab_abs_list=()

pausetime='10s'
waittime='1m'


#------ Local functions ------#

array_contains () { 
    local array="$1[@]"
    local seeking=$2
    local in=1
    for element in "${!array}"; do
        if [[ "$element" == "$seeking" ]]; then
            in=0
            break
        fi
    done
    return $in
}

round () {
    echo $(printf %.$2f $(echo "scale=$2;(((10^$2)*$1)+0.5)/(10^$2)" | bc))
}

minval () {
    if (( $(echo "$1 < $2" | bc -l) )); then
      echo "$1"
    else
      echo "$2"
    fi
}

maxval () {
    if (( $(echo "$1 > $2" | bc -l) )); then 
      echo "$1"
    else
      echo "$2"
    fi
}

update_hydro () {
    myline=$1
    myslot=$2
    myval=$3
    myformat=$4
    mytyp=$5
    unset IFS
    IFS=', ' read -r -a inarray <<< `sed "${myline}q;d" HYDRO.TBL`
    outarray=("${inarray[@]}")
    updateval=${inarray[${myslot}]}
    echo ${updateval}
    if [ ! -z ${updateval} ]; then
       if [[ "${updateval}" == *"E"* ]]; then
          updateval=`echo ${updateval} | sed -e 's/[eE]+*/\\*10\\^/'`
          echo "E format" ${updateval}
       fi
       if [ "${mytyp}" == "mult" ]; then
           updateval=`echo ${updateval}*${myval} | bc -l`
           echo "Mult" ${updateval}
       elif [ "${mytyp}" == "abs" ]; then
           updateval=`echo ${myval} | bc -l`
       else
           break
       fi
    fi
    outarray[${myslot}]=`printf "${myformat}" ${updateval}`
    IFS=', '
    newline=`echo "${outarray[*]}"`
    unset IFS
    echo $newline
    sed -i.bak "${myline}s/.*/${newline}/" HYDRO.TBL
}

update_mp () {
    myvar=$1
    myval=$2
    myline=$3
    myformat=$4
    mytyp=$5
    unset IFS
    IFS=', ' read -r -a inarray <<< `sed "${myline}q;d" MPTABLE.TBL | cut -d "=" -f2`
    outarray=("${inarray[@]}")
    for i in $(seq 0 $((${#inarray[@]}-1))); do
        if [ ! -z ${inarray[i]} ]; then
            if [ "${mytyp}" == "mult" ]; then
                outarray[i]=`echo ${inarray[i]}*${myval} | bc -l`
            elif [ "${mytyp}" == "abs" ]; then
                outarray[i]=`echo ${myval} | bc -l`
            else
                break
            fi
        fi
    done
    newline=`printf "${myformat},  " "${outarray[@]:0:${#outarray[@]}}"; echo`
    newline=`echo " ${myvar} =  ${newline}"`
    sed -i.bak "${myline}s/.*/${newline}/" MPTABLE.TBL
}

#-----------------------------#

startdir=`pwd`
cd $baserundir

if [ ! -d "SENS_RESULTS" ]; then
   mkdir SENS_RESULTS
fi
if [ ! -d "SENS_RUNS" ]; then
   mkdir SENS_RUNS
fi

counter=1

# Initialize param set
R CMD BATCH --no-save --no-restore sens_workflow_pre.R

# Loop through param lines
echo "Reading parameter set"
pcount=0
while read line; do
   if [ ${pcount} -eq 0 ]; then
      echo "Reading header..."
      IFS=' ' read -r -a varnames <<< "${line}"
      varcnt=${#varnames[@]}
      pcount=$((pcount+1))
   else
      echo "Reading line" ${pcount} with ${varcnt} params
      IFS=' ' read -r -a varvals <<< "${line}"

      runid=${varvals[0]}
      echo "Starting run $runid"

      cp -r RUN.TEMPLATE RUN.CALTMP${runid}
      cd RUN.CALTMP${runid}
      for n in $(seq 1 $((varcnt))); do
         varnm=${varnames[$n]}
         varnm=`echo $varnm | sed -e 's/\"//g'`
         varval=${varvals[$n]}
         echo ${varnm} ${varval}
         # Spatial soil properties file
         if array_contains soilp_mult_list ${varnm}; then
            echo "Updating soil file..."
            ncap2 -O -s "${varnm}=${varnm}*${varval}" DOMAIN/${soilfile} DOMAIN/${soilfile} 
         fi
         if array_contains soilp_abs_list ${varnm}; then
            echo "Updating soil file..."
            ncap2 -O -s "${varnm}=${varnm}*0.0+${varval}" DOMAIN/${soilfile} DOMAIN/${soilfile} 
         fi
         # Fulldom file
         if array_contains fulldom_mult_list ${varnm}; then
            echo "Updating fulldom file..."
            ncap2 -O -s "${varnm}=${varnm}*${varval}" DOMAIN/${fulldomfile} DOMAIN/${fulldomfile} 
         fi
         if array_contains fulldom_abs_list ${varnm}; then
            echo "Updating fulldom file..."
            ncap2 -O -s "${varnm}=${varnm}*0.0+${varval}" DOMAIN/${fulldomfile} DOMAIN/${fulldomfile} 
         fi
         # GW bucket parameter file
         if array_contains gw_mult_list ${varnm}; then
            echo "Updating GW file..."
            ncap2 -O -s "${varnm}=${varnm}*${varval}" DOMAIN/${gwfile} DOMAIN/${gwfile} 
         fi
         if array_contains gw_abs_list ${varnm}; then
            echo "Updating GW file..."
            ncap2 -O -s "${varnm}=${varnm}*0.0+${varval}" DOMAIN/${gwfile} DOMAIN/${gwfile} 
         fi
         # HYDRO.TBL
         if array_contains hydrotab_mult_list ${varnm}; then
            echo "Updating HYDRO.TBL file..."
            i=0
            start=0
            while IFS='' read -r line; do
               i=$((i+1))
               if [[ $line == SATDK* ]]; then
                  start=1
               elif [ $start -eq 1 ]; then
                  if [ "${varnm}" == "dksat" ]; then
                     update_hydro $i 0 ${varval} "%.10f" "mult" 
                  fi
                  if [ "${varnm}" == "smcmax" ]; then
                     update_hydro $i 1 ${varval} "%.3f" "mult"
                  fi
               fi
            done < HYDRO.TBL
         fi
         # MPTABLE.TBL
         if array_contains mptab_mult_list ${varnm} || array_contains mptab_abs_list ${varnm}; then
            typflag=""
            echo "Updating MPTABLE.TBL file..."
            if [ "${varnm}" == "MFSNO" ]; then
               chline=51
               chformat="%.2f"
            fi
            if [ "${varnm}" == "CWPVT" ]; then
                chline=74
                chformat="%.2f"
            fi
            if [ "${varnm}" == "VCMX25" ]; then
                chline=90
                chformat="%.2f"
            fi
            if [ "${varnm}" == "MP" ]; then
                chline=93
                chformat="%.2f"
            fi
            if [ "${varnm}" == "HVT" ]; then
                chline=47
                chformat="%.2f"
            fi
            if array_contains mptab_mult_list ${varnm}; then
               typflag="mult"
            elif array_contains mptab_abs_list ${varnm}; then
               typflag="abs"
            fi
            update_mp ${varnm} ${varval} ${chline} ${chformat} ${typflag}
         fi
      done # done param list

      # Edit run script
      sed -i.bak "9s/.*/#BSUB -J calib${runid}      # job name/" run.csh
      sed -i.bak "22s/.*/set outFolder=..\/SENS_RESULTS\/OUTPUT${runid}/" run.csh

      # Run
      bsub -K < run.csh &
      cd ..

  fi

done < $paramfile

wait
rundone=0
while [ $rundone -eq 0 ]; do
      outcnt=`ls -d SENS_RESULTS/OUTPUT* | wc -l`
      if [ "${outcnt}" -eq "29" ]; then
         echo "Run complete!"
         sleep $pausetime
         rundone=1
         exe="R CMD BATCH --no-restore --no-save sens_workflow_post.R"
         jobName=`date +%Y-%m-%d-%H-%M-%S`-$USER
         bsub -Is -q geyser -W 2:00 -n 16 -P NRAL0017 -J $jobName $exe ; bkill -J $jobName
         mv RUN.CALTMP* SENS_RUNS/.
         cd $startdir
         exit 0
      else
         echo "Waiting on run..."
         sleep $waittime
      fi
done


