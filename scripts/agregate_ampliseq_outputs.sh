#!/usr/bin/env bash

#Agregation of ampliseq outputs to have tables of data regrouping all the projects
#Every time, one table for all the projects

#Rows are ASVs
#ASV counts per sample (using long format table)
gzip -dc output/ampliseq_2db/*/summary_tables/ampliseq.counts.tsv.gz | awk 'NR==1 || $0 != "asv_id\tsample\tcount"' \
    > output/agregated/all_projects_ampliseq.counts.tsv
gzip output/agregated/all_projects_ampliseq.counts.tsv


#Rows are samples
#Values of cutadapt_summary.tsv: "how many reads per sample passed each pipeline step in which a loss can occur (overall_summary)"
#Values of DADA2_stats.tsv: "read numbers through DADA2 processing steps, for each sample"
#Cutadapt summary
find ./output/ampliseq_2db/*/cutadapt -name "cutadapt_summary.tsv" -exec awk 'NR==1 || FNR!=1' {} + > tmp/cutadapt_summary.tsv
#Dada2 stats
find ./output/ampliseq_2db/*/dada2 -name "DADA2_stats.tsv" -exec awk 'NR==1 || FNR!=1' {} + > tmp/DADA2_stats.tsv
#Cutadapt and dada2 summary statistics in one table
paste tmp/cutadapt_summary.tsv tmp/DADA2_stats.tsv > output/agregated/cutadapt_dada2_summary.tsv
rm tmp/cutadapt_summary.tsv tmp/DADA2_stats.tsv


#Overall summary
#le projet tara pacific PRJEB52329 n'a pas les mêmes colonnes que les autres (??)
cat output/ampliseq_2db/*/overall_summary.tsv > output/agregated/overall_summary.tsv
#If all the tables have the same columns:
#find ./output/ampliseq_2db/* -name "overall_summary.tsv" -exec awk 'NR==1 || FNR!=1' {} + ;



#Taxonomy
#One table containing pr2, silva and consensus taxonomic assignation for each project
#consensus is either pr2 or silva assignation kept
#add a column stating either pr2 or silva in consensus ?

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

#Do we want secondary analysis made with qiime2 ?
#If yes, with dada2 silva only ? or with pr2 only ? Or give the possibility to chose the reference database for these steps? 
#(consolidate_taxonomies="first")