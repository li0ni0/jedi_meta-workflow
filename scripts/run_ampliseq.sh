#!/usr/bin/env bash

#SBATCH --partition long
#SBATCH --cpus-per-task 1
#SBATCH --mem 5GB
#SBATCH --output run_ampliseq.out

module load nextflow/26.04.4
module load singularity


#Check that fetchngs samplesheet output was created and is not empty for each project
#Better than not empty, check if
#nb_line(output/fetchngs/${project}/samplesheet/samplesheet.csv) -1 == nb_line(input/fetchngs/samplesheet/${project}.csv)
#If yes, run ampliseq

while IFS= read -r project_file; do
  project="${project_file%.*}"
  FILE=./output/fetchngs/${project}/samplesheet/samplesheet.csv

  if [[ -f "$FILE" &&  $(wc -l < "$FILE") -gt 1 ]]; then
    echo "$FILE exists and is not empty."
    # run ampliseq
    DIR=output/ampliseq_2db/$project
    if [ -d "$DIR" ]; then
      echo "$DIR exists."
    else
      echo "$DIR directory does not exist. Running ampliseq for ${project} project."
      
      nextflow run nf-core/ampliseq -r 3.0.0 \
        -profile abims \
        -params-file ./input/ampliseq/params_ampliseq.yaml \
        --input ./output/fetchngs/${project}/samplesheet/samplesheet.csv \
        --outdir ./output/ampliseq_2db/${project}
    fi

    last_line=$(tail -n 1 .nextflow/history)
    status=$(echo ${last_line} | cut -f4)
    if [[ $status == "ERR" ]] && echo "$last_line" | grep -q "${project}"; then
      RUN_NAME=$(echo ${last_line} | cut -f3)
      echo "ampliseq run on the project ${project} failed. It will be resumed -resume ${RUN_NAME} (run name)."

      echo -e "${project}\t${RUN_NAME}" >> tmp/ampliseq_projectsTOresume.tsv
    fi

  else
    echo "$FILE does not exist or is empty. Run fetchngs for ${project} first. "
  fi

done < tmp/projects_files_list.txt

#Displays failed run in run_ampliseq.out
if [[ -f "tmp/ampliseq_projectsTOresume.tsv" &&  $(wc -l < "tmp/ampliseq_projectsTOresume.tsv") -gt 0 ]]; then
  echo "The file tmp/ampliseq_projectsTOresume.tsv was created."
  echo "It lists the project(s) for which an error occurred when running ampliseq and their associated run name."
  cat tmp/ampliseq_projectsTOresume.tsv
fi
