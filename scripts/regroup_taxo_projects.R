#First make one taxo table per project regrouping "the best" of silva and pr2 (defined (arbitrary) rules).

# After consensus_taxo.R
#Use consensus_taxo_PROJECT tables

library(tidyverse)


#Using purrr

all <- list(taxo_PRJEB89924$ASV_ID,taxo_PRJEB107922$ASV_ID,taxo_PRJNA579489$ASV_ID) |>
  list_c() |>
  tibble(ASV_ID= _ ) |>
  count(ASV_ID) 

#List of asv_id only in 1 project
#NO ambiguity on the taxonomy we will chose, keep like that
inOnly1 <- all |>
  filter(n==1)

uniq_1 <- inOnly1 |> 
  inner_join(taxo_PRJEB89924, by="ASV_ID") 
uniq_2 <- inOnly1 |> 
  inner_join(taxo_PRJEB107922, by="ASV_ID")
uniq_3 <- inOnly1 |> 
  inner_join(taxo_PRJNA579489, by="ASV_ID")
#Taxonomy table for ASVs only in 1 project
uniq_tot <- rbind(uniq_1,uniq_2,uniq_3)



####

inMany <- all |>
  filter(n > 1) |> 
  pull(ASV_ID)

many_1 <- inMany |> 
  inner_join(taxo_PRJEB89924, by="ASV_ID")
many_2 <- inMany |> 
  inner_join(taxo_PRJEB107922, by="ASV_ID")
many_1 <- inMany |> 
  inner_join(taxo_PRJNA579489, by="ASV_ID")


many_taxo <- rbind(many_1, many_2, many_3)

