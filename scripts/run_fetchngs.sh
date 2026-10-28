#!/usr/bin/env bash

date

#SBATCH --partition long
#SBATCH --cpus-per-task 1
#SBATCH --mem 5GB
#SBATCH --output run_fetchngs.out

module load nextflow/26.04.4
module load singularity


#Gets the list of projects (can be any type of ID supported by fetchngs)
#and lists them in a file
#to run fetchngs for each of them.

ls input/fetchngs/samplesheet | \
    grep -E "^\S+\.(csv|tsv|txt)$" | \
    sed -E 's/(\.csv|\.tsv|\.txt)//' | \
    grep -E "PRJ|SRR|SRX|SRS|SAM|SRP|SRA|ERR|ERX|ERS|ERP|ERA|DRR|DRX|DRS|DRP|DRA|GSM|GSE" \
    > tmp/projects_list.txt

echo "The file tmp/projects_list.txt was created."
echo "The projects' IDs are:"
cat tmp/projects_list.txt


#Check if output/fetchngs/$project exists and run fetchngs if not
#for all projects listed in tmp/projects_list.txt
while IFS= read -r project; do

  DIR=output/fetchngs/$project

  if [ -d "$DIR" ]; then
    echo "$DIR exists."
  else
    echo "$DIR directory does not exist. Running fetchngs for ${project} project."
    nextflow run nf-core/fetchngs -r 1.13.0 \
      -profile abims \
      -params-file ./input/fetchngs/params_fetchngs.yaml \
      --input ./input/fetchngs/samplesheet/${project}.csv \
      --outdir ./output/fetchngs/${project}
    if (( $(tail -n 1 .nextflow/history | cut -f4)=="ERR" )); then
      RUN_NAME=$(tail -n 1 .nextflow/history | cut -f3)
      echo "fetchngs run on the project ${project} failed. Correct the script and run again with -resume ${RUN_NAME} (run name)."
      #nextflow ... -resume ${RUN_NAME}
      echo -e "${project}\t${RUN_NAME}" >> input/fetchngs/projectsTOresume.tsv
    fi
  fi

done < tmp/projects_list.txt

date
