#!/usr/bin/env bash

#SBATCH --partition long
#SBATCH --cpus-per-task 1
#SBATCH --mem 5GB
#SBATCH --output resume_ampliseq.out

module load nextflow/26.04.4
module load singularity


while IFS= read -r line; do
  
  LINE=($line)
  project=${LINE[0]}
  RUN_NAME=${LINE[1]}

  nextflow run nf-core/ampliseq -r 3.0.0 \
    -profile abims \
    -params-file ./input/ampliseq/params_ampliseq.yaml \
    --input ./output/fetchngs/${project}/samplesheet/samplesheet.csv \
    --outdir ./output/ampliseq_2db/${project} \
    -resume $RUN_NAME
    #if successful, delete tmp/ampliseq_projectsTOresume.tsv corresponding line
    if (( $(tail -n 1 .nextflow/history | cut -f4)=="OK" )) && tail -n 1 .nextflow/history | grep -q ${project}  ; then
      RUN_NAME=$(tail -n 1 .nextflow/history | cut -f3)
      echo "ampliseq resumed run on the project ${project} succeeded."
      sed -i "/${RUN_NAME}/d" ./tmp/ampliseq_projectsTOresume.tsv
    fi
done < tmp/ampliseq_projectsTOresume.tsv

