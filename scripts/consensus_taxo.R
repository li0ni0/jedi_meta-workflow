#Make consensus taxonomy from pr2 and silva results


library(tidyverse)

refdbs <- c("pr2_5_1_0", "silva_138_2")


# Read files ----
projects_list <- readLines("tmp/projects_list.txt")

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


all_taxonomic_tables <- taxo_files |>  
  set_names(taxo_names) |> 
  map(read_tsv)

pr2_taxonomic_tables <- taxo_files_pr2 |>  
  set_names(taxo_names_pr2) |> 
  map(read_tsv)

silva_taxonomic_tables <- taxo_files_silva |>  
  set_names(taxo_names_silva) |> 
  map(read_tsv)

#list2env(all_taxonomic_tables, envir = .GlobalEnv)


#Table formatting

source("scripts/functions_taxo.R")

#Formatted tables for each projects for silva and pr2
pr2_taxonomic_tables_formatted <- map(pr2_taxonomic_tables, format_taxo_table_pr2)
silva_taxonomic_tables_formatted <- map(silva_taxonomic_tables, format_taxo_table_silva)


#Create the list of merged taxonomies for each projects and rename them
pr2_silva_joined <-  map2(.x= pr2_taxonomic_tables_formatted, 
                          .y= silva_taxonomic_tables_formatted,
                          .f= ~ full_join(.x, .y, by="ASV_ID"))

merged_taxo_names <- taxo_files_pr2 %>% 
  map_chr(~ { project <- str_split(.x, "/")[[1]][3] 
  paste0("merged_", project)
  })

pr2_silva_merged <- set_names(pr2_silva_joined, merged_taxo_names)


# Apply make_consensus_taxo on the merged taxonomic tables
pr2_silva_consensus <- map(pr2_silva_merged, .f=make_consensus_taxo)

