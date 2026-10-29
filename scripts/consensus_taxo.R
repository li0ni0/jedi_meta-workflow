#Make consensus taxonomy from pr2 and silva results

#setwd("/shared/projects/jedi_meta/workflow")

library(tidyverse)
library(stringmagic)
library(stringr)

source("scripts/functions_taxo.R")

#Reference databases and their version as written in ampliseq/dada2 output
refdbs <- c("pr2_5_1_0", "silva_138_2") #replace with silva_144


# Read files ----
projects_list <- readLines("tmp/projects_files_list.txt")
projects_list <- str_remove(projects_list, "\\.(csv|tsv|txt)$")

#projects_list <- c("PRJEB107922", "PRJEB89924", "PRJNA579489")

#List of dada2 ASV taxonomy filenames (ampliseq/dada2 output)
taxo_files=c()
for (db in refdbs){
  for (project in projects_list){
    taxo_files <- c(taxo_files, paste0("output/ampliseq_2db/", project, "/dada2/ASV_tax.", db, ".tsv")) 
  }
}
rm(project)
rm(db)

taxo_files_pr2 <- string_get(taxo_files, "pr2")
taxo_files_silva <- string_get(taxo_files, "silva")


taxo_names <- taxo_files %>% 
  map_chr(~ { project <- str_split(.x, "/")[[1]][3] 
    refdb <- ifelse(str_detect(.x, "pr2"), "pr2", "silva")
    paste0(refdb, "_", project)
  })

taxo_names_pr2 <- string_get(taxo_names, "pr2")
taxo_names_silva <- string_get(taxo_names, "silva")


pr2_taxonomic_tables <- taxo_files_pr2 |>  
  set_names(taxo_names_pr2) |> 
  map(read_tsv)

silva_taxonomic_tables <- taxo_files_silva |>  
  set_names(taxo_names_silva) |> 
  map(read_tsv)


#Handle the confidence scores ----
#For silva, cut confidence string so we have as many confidence score as we have taxonomic levels
#(silva repeats last value instead of giving values below 0.5, we replace the repeats by NA)
taxo_ranks <- c("Domain", "Phylum", "Class", "Order", "Family", "Genus", "Species")
silva_taxonomic_tables <- map(silva_taxonomic_tables, .f=manage_silva_confidences, taxo_ranks)



# Regroup pr2 and silva taxonomies in one table for each project ----

#Formatted tables for each projects for silva and pr2
pr2_taxonomic_tables_formatted <- map(pr2_taxonomic_tables, format_taxo_table_pr2)
silva_taxonomic_tables_formatted <- map(silva_taxonomic_tables, format_taxo_table_silva)


#Create the list of merged taxonomies for each projects and rename them
pr2_silva_joined <-  map2(.x= pr2_taxonomic_tables_formatted, 
                          .y= silva_taxonomic_tables_formatted,
                          .f= ~ full_join(.x, .y, by="ASV_ID")) |>
                     set_names( paste0("joined_", projects_list))

#Above:
#pr2_silva_joined is a list where
#each element is a table where lines are ASV_ID and columns are pr2 and silva taxonomy and confidence
##############################


## Get conflict info on the domain level ----
#Table listing the ASVs for which pr2 and silva gave different domains
#and the domain assignated with pr2 and silva
domain_conflicts_per_projects <- map(pr2_silva_joined, domain_conflict) |> 
  set_names(paste0("domain_conflicts_", projects_list))


# Add the consensus taxonomy on the joined taxonomic tables ----
#We now have pr2, silva and consensus (confidence consensus only for the most precise taxonomic level kept)
pr2_silva_consensus <- map(pr2_silva_joined, .f=make_consensus_taxo)



#Export the tables to output/agregated/taxonomy ----
walk2(.x=pr2_silva_consensus,
     .y=projects_list,
     .f= ~ write_tsv(.x,
        file=str_c("output/agregated/taxonomy/pr2_silva_consensus_",
        .y, ".tsv"), append=FALSE)
  )

walk2(.x=domain_conflicts_per_projects,
     .y=projects_list,
     .f= ~ write_tsv(.x,
     file=str_c("output/agregated/taxonomy/domain_conflicts_",
     .y, ".tsv"), append=FALSE)
     )
