#First make one taxo table per project regrouping "the best" of silva and pr2 (defined (arbitrary) rules).

##Test
#Regrouping PRJEB89924 and PRJEB107922 and PRJNA579489 (just using pr2 table)

library(tidyverse)

taxo_PRJEB89924=read_tsv("output/ampliseq_2db/PRJEB89924/dada2/ASV_tax.pr2_5_1_0.tsv")
taxo_PRJEB107922=read_tsv("output/ampliseq_2db/PRJEB107922/dada2/ASV_tax.pr2_5_1_0.tsv")
taxo_PRJNA579489=read_tsv("output/ampliseq_2db/PRJNA579489/dada2/ASV_tax.pr2_5_1_0.tsv")


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

