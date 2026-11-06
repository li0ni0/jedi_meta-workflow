#!/usr/bin/env bash

#Agregation of ampliseq outputs to have tables of data regrouping all the projects
#Every time, one table for all the projects


########################################################
# ASVs sequences
########################################################

#Concatenate fasta and remove duplicate sequences
find ./output/ampliseq_2db_old/*/dada2 -name "ASV_seqs.fasta" -exec awk '/^>/ {if (seen[$0]++) {f=0} else {f=1}} f' {} + \
  > output/agregated/ASV_seqs_clean.fasta


#Instead of awk, use seqkit (https://bioinf.shenwei.me/seqkit/usage/) ?
#or gt sequniq (https://genometools.org/tools/gt_sequniq.html) to remove duplicate sequences ?
#Maybe faster with a large volume of data ?
#seqkit rmdup -n output/agregated/ASV_seqs.fasta > output/agregated/ASV_seqs_clean.fasta
#gt sequniq -o output/agregated/ASV_seqs_clean.fasta output/agregated/ASV_seqs.fasta

########################################################
# ASV counts per sample
########################################################
#Rows are ASVs (long format table)
gzip -dc output/ampliseq_2db_old/*/summary_tables/ampliseq.counts.tsv.gz | awk 'NR==1 || $0 != "asv_id\tsample\tcount"' \
    > output/agregated/all_projects_ampliseq.counts.tsv

########################################################
# Sample ID input
########################################################
#Use output/ampliseq_2db_old/PRJEB89924/input/samplesheet.csv
find ./output/ampliseq_2db_old/*/input -name "samplesheet.csv" -exec awk 'NR==1 || FNR!=1' {} + | \
  cut -f1 -d ',' | cut -d '"' -f2 \
  > output/agregated/input_samples.txt

########################################################
# Read counts per sample (summary stats)
########################################################
#Rows are samples

#Cutadapt summary
find ./output/ampliseq_2db/*/cutadapt -name "cutadapt_summary.tsv" -exec awk 'NR==1 || FNR!=1' {} + > tmp/cutadapt_summary.tsv
#Dada2 stats
find ./output/ampliseq_2db/*/dada2 -name "DADA2_stats.tsv" -exec awk 'NR==1 || FNR!=1' {} + > tmp/DADA2_stats.tsv
#Cutadapt and dada2 summary statistics in one table
paste tmp/cutadapt_summary.tsv tmp/DADA2_stats.tsv > output/agregated/cutadapt_dada2_summary.tsv
rm tmp/cutadapt_summary.tsv tmp/DADA2_stats.tsv

#Overall summary "how many reads per sample passed each pipeline step in which a loss can occur"
find ./output/ampliseq_2db_old/* -name "overall_summary.tsv" -exec awk 'NR==1 || FNR!=1' {} + ;
#If all the tables don't have the same columns, keep the headers:
#cat output/ampliseq_2db/*/overall_summary.tsv > output/agregated/overall_summary.tsv



########################################################
# Metadata
########################################################
#Ampliseq input parameters
cat input/ampliseq/params_ampliseq.yaml > output/agregated/params_ampliseq.yaml

#Ampliseq version
ampliseq_version="v3.0.0"
#R version for scripts outside of ampliseq - change between users
#R_version="v4.5.2"

#Metaworkflow information
COMMIT_HASH=$(git rev-parse HEAD) #last commit hash (possible to specify a branch)
VERSION=$(git describe --always --long | cut -d '-' -f1) #Shows the nearest tag, the number of commits since the tag, and the abbreviated commit hash.

echo "# Metaworkflow info" > output/agregated/metaworkflow_params.yaml
echo -e "\n#Versions\nmetaworkflow_version: ${VERSION}
git_commit_hash: ${COMMIT_HASH}
ampliseq_version: ${ampliseq_version}\n
#Parameters
#Export options:\nexport: ${export}
#File listing the projects to compute:\nadd_projects: \"${add_projects}\"" \
 >> output/agregated/metaworkflow_params.yaml
