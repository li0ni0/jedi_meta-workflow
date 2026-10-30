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
  echo "-e    Chose whether to export pr2, silva and consensus taxonomies (pr2_silva_consensus.tsv) and domain conflicts
              (domain_conflicts) tables (one per project). Either joined, conflicts or both. Default is none."
}


############################################################
# Usage function
############################################################
usage() {
  echo "Usage: $0 -a <tmp/add_new_projects.txt> -e <joined;conflicts;both> [-h for help]"
}


#########
#Options#
#########

#Default values
export="none"

while getopts ":ha:e:" OPTION
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
  e) #Export taxonomy and/or domain conflicts tables
    export=$OPTARG
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

if [ -f $add_projects ] ; then #if an existing file is given to option -a
  echo "Running fetchngs only for the project(s) listed in the given file ${add_projects}:"
else
  #Gets the list of projects (samplesheet) (can be any type of ID supported by fetchngs) and lists them in a file
  echo "Running fetchngs for every project that has a samplesheet in input/fetchngs/samplesheet"
  ls input/fetchngs/samplesheet | \
    grep -E "^\S+\.(csv|tsv|txt)$" | \
    grep -E "PRJ|SRR|SRX|SRS|SAM|SRP|SRA|ERR|ERX|ERS|ERP|ERA|DRR|DRX|DRS|DRP|DRA|GSM|GSE" | sort \
    > tmp/projects_files_list.txt

  echo "The file tmp/projects_files_list.txt was created."
  add_projects="tmp/projects_files_list.txt"
fi
cat $add_projects
sbatch scripts/run_fetchngs.sh $add_projects

########################################################
# Run ampliseq
########################################################

sbatch scripts/run_ampliseq.sh $add_projects

#Re-run ampliseq with option -resume for projects that had en error 
FILE=tmp/ampliseq_projectsTOresume.tsv

if [[ -f "$FILE" &&  $(wc -l < "$FILE") -gt 0 ]]; then
  sbatch scripts/resume_ampliseq.sh 
fi

########################################################
# Agregate ampliseq outputs per projects
########################################################
[ ! -d "output/agregated" ] && mkdir output/agregated

sbatch scripts/agregate_ampliseq_outputs.sh
