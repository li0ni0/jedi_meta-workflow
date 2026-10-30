#!/usr/bin/env bash

############################################################
# Help                                                     
############################################################
Help()
{
   # Display Help
   echo "Help for the pipeline running fetchngs and ampliseq"
   echo "options:"
   echo "-h     Print this Help."
   echo "-m     Name of the metadata.tsv file for ampliseq. OPTIONAL "
}


#########
#Options#
#########

while getopts ":hm:" OPTION
do
  case $OPTION in
  h)
    Help
    ;;
  m) #Optional
    metadata_ampliseq=$OPTARG
    ;;
  \?)
    echo "Invalid option"
    exit 1
    ;;
  esac
done

#Preparation
[ ! -d "tmp" ] && mkdir tmp


########################################################
#Run nf-core-fetchngs
########################################################

sbatch scripts/run_fetchngs.sh


########################################################
# Run ampliseq
########################################################


sbatch scripts/run_ampliseq.sh

#Re-run ampliseq with option -resume for projects that had en error 
FILE=tmp/ampliseq_projectsTOresume.tsv

if [[ -f "$FILE" &&  $(wc -l < "$FILE") -gt 1 ]]; then
  sbatch scripts/resume_ampliseq.sh
fi

########################################################
# Agregate ampliseq outputs per projects
########################################################
[ ! -d "output/agregated" ] && mkdir output/agregated

sbatch scripts/agregate_ampliseq_outputs.sh
