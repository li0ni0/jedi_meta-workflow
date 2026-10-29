#!/usr/bin/env bash

#Agregation of ampliseq outputs to have one of each table generated regrouping all projects

#Make one table containing the ASV counts per sample of every project (using long format table)

gzip -dc output/ampliseq_2db/*/summary_tables/ampliseq.counts.tsv.gz | awk 'NR==1 || $0 != "asv_id\tsample\tcount"' > output/agregated/all_projects_ampliseq.counts.tsv
gzip output/agregated/all_projects_ampliseq.counts.tsv

#One overall_summary.tsv table for all projects
#le projet tara pacific PRJEB52329 n'a pas les mêmes colonnes que les autres
cat output/ampliseq_2db/*/overall_summary.tsv > output/agregated/overall_summary.tsv

#If every table has the same columns:
#find ./output/ampliseq_2db/* -name "overall_summary.tsv" -exec awk 'NR==1 || FNR!=1' {} + ;

#One table for dada2 stats for all projects
find ./output/ampliseq_2db/*/dada2 -name "DADA2_stats.tsv" -exec awk 'NR==1 || FNR!=1' {} + > output/agregated/DADA2_stats.tsv

#Metadata::
#software version:
#output/ampliseq_2db/PRJEB89924/pipeline_info/nf_core_ampliseq_software_mqc_versions.yml
#command used
#inputs, IDs (agregated samplesheet?)
#parameters:
#.yaml and output/ampliseq_2db/PRJEB89924/pipeline_info/params_2026-10-19_10-29-05.json




#Taxonomy
#For taxnomic tables, see R code
#One table containing pr2 and silva taxonomic assignation for each project
#and consensus taxonomic assignation (either pr2 or silva assignation kept)
#add a column stating either pr2 or silva in consensus ?


#Do we want secondary analysis made with qiime2 ?
#If yes, with dada2 silva only ? or with pr2 only ? Or give the possibility to chose the reference database for these steps? 
#(consolidate_taxonomies="first")