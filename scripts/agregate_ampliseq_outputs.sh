#!/usr/bin/env bash

#Agregation of ampliseq outputs to have tables of data regrouping all the projects
#Every time, one table for all the projects


########################################################
# ASV counts per sample
########################################################
#Rows are ASVs (long format table)
gzip -dc output/ampliseq_2db/*/summary_tables/ampliseq.counts.tsv.gz | awk 'NR==1 || $0 != "asv_id\tsample\tcount"' \
    > output/agregated/all_projects_ampliseq.counts.tsv
gzip output/agregated/all_projects_ampliseq.counts.tsv

########################################################
# Read counts per sample
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
#le projet tara pacific PRJEB52329 n'a pas les mêmes colonnes que les autres (??)
cat output/ampliseq_2db/*/overall_summary.tsv > output/agregated/overall_summary.tsv
#If all the tables have the same columns:
#find ./output/ampliseq_2db/* -name "overall_summary.tsv" -exec awk 'NR==1 || FNR!=1' {} + ;


########################################################
# Taxonomy (R script)
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
