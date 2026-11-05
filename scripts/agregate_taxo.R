#Taxonomy agregation for all the projects

####
#Columns of the final table:
#ASV_ID
#Projects: column listing all the projects where the ASV is found
#consensus_taxo: consensus of all consensus_dada2_taxonomy for the ASV (shortest)
#consensus_conf: consensus of all consensus_dada2_confidence for the ASV (smallest)
#consensus_db: corresponding to consensus_dada2_taxonomy kept (silva or pr2)


####Clean
l=ls()
l <- l[!l %in% "pr2_silva_consensus"]
rm(list=l)
rm(l)
####

#Input: pr2_silva_consensus list of tables from consensus_taxo.R script
#Output: agregated consensus taxonomic table (one, for all the projects)

#The rows are ASVs. When an ASV has different taxonomies in different projects, keep the shortest similar part.
#If everything is different, keep both ?

#Transform the list of tables in one big table
binded_tables <- bind_rows(pr2_silva_consensus, .id="project") |> 
  mutate(project=str_replace(project, "joined_", "")) |> 
  select(ASV_ID, project, consensus_dada2_taxonomy, consensus_dada2_confidence, consensus_db) |>
  group_by(ASV_ID) |> 
  mutate(project = str_c(project, collapse="-")) |> 
  rename(Projects=project) |> 
  ungroup()

#Vector of all duplicated ASVs
dup <- unique(binded_tables$ASV_ID[duplicated(binded_tables$ASV_ID)])

#Add columns of boolean
#Add column duplicate indicating whether the ASV is present in more than one project (TRUE) or unique to a project (FALSE)
#same_consensus_taxo: FALSE if difference between the pr2 and silva consensus taxo of the same ASV
#same_consensus_confidence: FALSE if difference between pr2 and silva consensus confidence of the same ASV
binded_tables <- binded_tables |>
  mutate(duplicate = ifelse(ASV_ID %in% dup, "TRUE", "FALSE" )) |>
  mutate(same_consensus_taxo = n_distinct(
    ASV_ID, consensus_dada2_taxonomy) == 1, .by = "ASV_ID") |> 
  mutate(same_consensus_confidence = n_distinct(
    ASV_ID, consensus_dada2_confidence) == 1, .by = "ASV_ID") |> 
  distinct() #3304 - 312 = 2992


#Different consensus taxonomies, keep the shortest one
taxo_conflicts_solved <- binded_tables |> 
  filter(same_consensus_taxo=="FALSE") |> 
  mutate(nb_NA = str_count(consensus_dada2_taxonomy, "NA")) |> 
  group_by(ASV_ID) |> 
  slice_max(nb_NA, with_ties = FALSE) |> 
  select(! nb_NA)

#Same consensus taxo but different confidences, keep the smallest confidence
confidence_conflicts_solved <- binded_tables |> 
  filter(same_consensus_taxo=="TRUE" & same_consensus_confidence=="FALSE") |> 
  group_by(ASV_ID) |> 
  slice_min(consensus_dada2_confidence)


duplicate_without_conflict <- binded_tables |> 
  filter(duplicate=="TRUE" & same_consensus_taxo=="TRUE" & same_consensus_confidence=="TRUE")

not_duplicated <- filter(binded_tables, duplicate=="FALSE")

#Taxonomy table with the consensustaxonomy for all the projects
agregated_consensus_taxonomy <- rbind(not_duplicated, confidence_conflicts_solved, taxo_conflicts_solved, duplicate_without_conflict)


##Export agregated consensus taxonomy table
write_tsv(agregated_consensus_taxonomy,
          file="output/agregated/agregated_consensus_taxonomy.tsv",
          append=FALSE)
