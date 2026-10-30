#!/usr/bin/env bash

#SBATCH --partition long
#SBATCH --cpus-per-task 1
#SBATCH --mem 5GB
#SBATCH --output run_fetchngs.out

module load nextflow/26.04.4
module load singularity


#Check if output/fetchngs/$project exists and run fetchngs if not
#for all projects listed automatically in tmp/projects_files_list.txt or manually in $add_projects
while IFS= read -r project_file; do
  project="${project_file%.*}"
  DIR=output/fetchngs/$project

  if [ -d "$DIR" ]; then
    echo "$DIR exists."
  else
    echo "$DIR directory does not exist. Running fetchngs for ${project} project."
    nextflow run nf-core/fetchngs -r 1.13.0 \
      -profile abims \
      -params-file ./input/fetchngs/params_fetchngs.yaml \
      --input ./input/fetchngs/samplesheet/${project_file} \
      --outdir ./output/fetchngs/${project}

    last_line=$(tail -n 1 .nextflow/history)
    status=$(echo ${last_line} | cut -f4)
    if [[ $status == "ERR" ]] && echo "$last_line" | grep -q "${project}"; then
      RUN_NAME=$(echo ${last_line} | cut -f3)
      echo "fetchngs run on the project ${project} failed. Correct the script and run again with -resume ${RUN_NAME} (run name)."
    fi
  fi

done < $1
