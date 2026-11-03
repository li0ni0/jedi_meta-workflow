#Taxonomy agregation for all the projects

#Input: pr2_silva_consensus list of tables from consensus_taxo.R script
#Output: agregated taxonomic table (for all the projects)


#Make one table with pr2, silva and consensus taxonomy for all the projects together
#The rows are ASVs. When an ASV has different taxonomies in different projects, keep the shortest similar part.
#If everything is different, keep both ?

#table(table(binded_tables$ASV_ID))
#ASVs: 2489 + 262*2 + 97*3 = 2489 + 815 = 3304

#Transform the list in one big table
binded_tables <- bind_rows(pr2_silva_consensus, .id="project")
#All duplicated ASVs
dup <- unique(binded_tables$ASV_ID[duplicated(binded_tables$ASV_ID)])
#All unique ASVs
#unique_ASV <- binded_tables$ASV_ID[! binded_tables$ASV_ID %in% dup ]

#Agregated table for ASVs unique to a project
#binded_uniq <- binded_tables |>  
#  filter(ASV_ID %in% unique_ASV)
binded_uniq <- binded_tables |>  
  filter(!ASV_ID %in% dup) |> 
  mutate(duplicate="FALSE")

#Agregated table for ASVs found in 2 or more projects
binded_dup <- binded_tables |>  
  filter(ASV_ID %in% dup) |> 
  mutate(duplicate="TRUE")

binded_tables <- rbind(binded_uniq, binded_dup)


#
binded_tables |> 
  filter(duplicate=="TRUE") |> 
  group_by(ASV_ID) |> 
  select(project)



###Add to binded tables
dup_wo_conflict <- binded_dup |> 
  arrange(ASV_ID) |> 
  summarise(same_consensus = n_distinct(
    ASV_ID, consensus_dada2_taxonomy, consensus_dada2_confidence, consensus_db) == 1,
    .by = "ASV_ID") |> 
  filter(same_consensus=="TRUE")





#What to do ?
dup_with_conflicts <- binded_dup |> 
  arrange(ASV_ID) |> 
  summarise(same_consensus = n_distinct(
    ASV_ID, consensus_dada2_taxonomy, consensus_dada2_confidence, consensus_db) == 1,
    .by = "ASV_ID") |> 
  filter(same_consensus=="FALSE")


to_unite <- left_join(dup_with_conflicts, binded_tables, by="ASV_ID")

#function to unite columns to have project1,project2,project3 values for the ASV when they differ
#this way we store all the info without more columns

to_unite_clean <- to_unite %>%
  group_by(ASV_ID) %>%
  summarise(across(everything(), ~ paste(unique(as.character(.x)), collapse = "-")))
