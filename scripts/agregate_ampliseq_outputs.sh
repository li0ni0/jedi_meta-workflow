#!/usr/bin/env bash

#Agregation of ampliseq outputs to have one of each table generated regrouping all projects

#Make one table containing the ASV counts per sample of every project (using long format table)

gzip -dc output/ampliseq_2db/*/summary_tables/ampliseq.counts.tsv.gz | awk 'NR==1 || $0 != "asv_id\tsample\tcount"' > output/agregated/all_projects_ampliseq.counts.tsv



#Taxonomy
#For taxnomic tables, see R code
#One table containing pr2 and silva taxonomic assignation for every project ?
#One table containing consensus taxonomic assignation for every project ???

#Do we want secondary analysis made with qiime2 ?
#If yes, with dada2 silva only ? Or give the possibility to chose the reference database for these steps? 


