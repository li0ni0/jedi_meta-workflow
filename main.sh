#!/usr/bin/env bash

############################################################
# Help                                                     
############################################################
Help() {
   # Display Help
   echo "Help for the pipeline running fetchngs and ampliseq"
   echo "options:"
   echo "-h     Print this Help."
   echo -e "-a  Path to a file listing (one per line) the samplesheets you want to analyse.
                Samplesheets must be named project_id with extension .csv .tsv or .txt
                Example: project_id1.csv\nproject_id2.tsv
                If there are samplesheets for other projects, they will be ignored \neven if their outputs have been deleted from the working directory.
                Can be used when you have already successfully ran ampliseq on some projects and deleted their outputs
                than added some samplesheet for projects you also want to run (without running the other ones again)."
}


############################################################
# Usage function
############################################################
usage() {
  echo "Usage: $0 -a <tmp/add_new_projects.txt> [-h for help]"
}

#########
#Options#
#########

while getopts ":ha" OPTION
do
  case $OPTION in
  h)
    Help
    usage
    exit 0
    ;;
  a) #Added fetchngs project samplesheet(s) and want to run only those
    add_projects=$OPTARG
    ;;
  \?)
    echo "Invalid option: -$OPTARG"
    usage
    exit 1
    ;;
  :)
  	echo "Option -$OPTARG requires an argument."
    usage
    exit 1
    ;;
  esac
done

#Preparation
[ ! -d "tmp" ] && mkdir tmp


########################################################
#Run nf-core-fetchngs
########################################################

if [ -f $add_projects ] ; then #if option -a is used
  echo "Running fetchngs only for the project(s) listed in ${add_projects}:"
  cat $add_projects
  sbatch scripts/run_fetchngs.sh $add_projects

else
  #Gets the list of projects (samplesheet) (can be any type of ID supported by fetchngs) and lists them in a file
  echo "Running fetchngs for every project that has a samplesheet in input/fetchngs/samplesheet"
  ls input/fetchngs/samplesheet | \
    grep -E "^\S+\.(csv|tsv|txt)$" | \
    grep -E "PRJ|SRR|SRX|SRS|SAM|SRP|SRA|ERR|ERX|ERS|ERP|ERA|DRR|DRX|DRS|DRP|DRA|GSM|GSE" | sort \
    > tmp/projects_files_list.txt

  echo "The file tmp/projects_files_list.txt was created."
  cat tmp/projects_files_list.txt
  sbatch scripts/run_fetchngs.sh tmp/projects_files_list.txt

fi



########################################################
# Run ampliseq
########################################################


sbatch scripts/run_ampliseq.sh

#Re-run ampliseq with option -resume for projects that had en error 
FILE=tmp/ampliseq_projectsTOresume.tsv

if [[ -f "$FILE" &&  $(wc -l < "$FILE") -gt 0 ]]; then
  sbatch scripts/resume_ampliseq.sh
fi



########################################################
# Create formatted taxonomy tables (R script)
########################################################

[ ! -d "output/agregated/taxonomy" ] && mkdir output/agregated/taxonomy

module load r/4.5.2

sbatch \
    #--mem 20GB \
    --wrap="Rscript scripts/consensus_taxo.R"

sbatch \
    #--mem 20GB \
    #--output output/agregated/taxonomy \
    --wrap="Rscript scripts/export.R"


