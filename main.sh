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

#Check fetchngs ran well before running ampliseq ?
#grep --quiet "Execution complete -- Goodbye" .nextflow.log
#grep $project $FILE #instead so we check that the project is indeed in the samplesheet ?

sbatch scripts/run_ampliseq.sh

#Re-run ampliseq with option -resume for what needs to
FILE=tmp/ampliseq_projectsTOresume.tsv

if [[ -f "$FILE" &&  $(wc -l < "$FILE") -gt 1 ]]; then
  sbatch scripts/resume_ampliseq.sh
fi




########################################################
# Format ampliseq ASV table for export using R
########################################################

#Keep this part ?

#module load r/4.3.1

#sbatch --mem 10GB \
#  --output "prepare_final_table.out" \
#  --wrap="Rscript scripts/prepare_final_tables.R"
