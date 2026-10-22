library(Biostrings)
library(tidyverse)

asv_table <- read_tsv("output/ampliseq/dada2/ASV_table.tsv") %>% 
  rename(asv_id = "ASV_ID")

#####################################################################
# import taxonomic assignment results and add a column with
# concatenation of taxonomic ranks
#####################################################################

asv_taxonomy <- read_tsv("output/ampliseq/dada2/ASV_tax.silva_138_2.tsv", na = "NA") %>% 
  rename_with(tolower) %>% 
  unite(taxonomy, kingdom:species, na.rm = TRUE, sep = ";", remove = FALSE) %>%
  mutate(taxonomy = str_remove(taxonomy, ";+$"))

#####################################################################
# import extra taxonomic assignment results and add a column with
# concatenation of taxonomic ranks
#####################################################################

asv_extra_taxonomy <- read_tsv("output/ampliseq/dada2/ASV_tax.pr2_5_0_0.tsv", na = "NA") %>% 
  rename_with(tolower) %>% 
  unite(taxonomy, domain:species, na.rm = TRUE, sep = ";", remove = FALSE) %>%
  mutate(taxonomy = str_remove(taxonomy, ";+$"))

#####################################################################
# sum orientation 1 and 2 in ASV table and add taxonomic assignment results
#####################################################################

asv_table <- str_subset(names(asv_table), "asv_id", negate = TRUE) %>% 
  str_replace("^([^_]+_[^_]+)_.+$", "\\1") %>% 
  unique() %>%
  map(
    function(x){
      tmp <- select(asv_table, starts_with(x))
      tibble("{x}" := rowSums(tmp))
    }
  ) %>% 
  bind_cols(asv_id = asv_table[["asv_id"]], .)

#####################################################################
# compute asv stats and add taxo + count table
#####################################################################

asv_table_with_taxo <- pivot_longer(asv_table, starts_with("RA")) %>% 
  filter(value > 0) %>%
  group_by(asv_id) %>%
  summarise(total = sum(value), spread = n()) %>%
  left_join(asv_taxonomy, by = "asv_id") %>% 
  left_join(asv_table, by = "asv_id") %>% 
  ungroup() %>% 
  arrange(-total) %>% 
  filter(total > 2 & spread > 1)

#####################################################################
# overall summary
#####################################################################

overall_summary <- read_tsv("output/ampliseq/overall_summary.tsv")

# sum orientations

overall_summary <- overall_summary %>% 
  mutate(sample = str_replace(sample,"^([^_]+_[^_]+)_.+$", "\\1")) %>% 
  group_by(sample) %>% 
  summarise(
    cutadapt_total_processed = unique(cutadapt_total_processed),
    cutadapt_passing_filters = sum(cutadapt_passing_filters),
    cutadapt_passing_filters_percent = (cutadapt_passing_filters / cutadapt_total_processed) * 100,
    cutadapt_passing_filters_percent = paste0(round(cutadapt_passing_filters_percent, digits = 1),"%"),
    DADA2_input = sum(DADA2_input),
    filtered = sum(filtered),
    denoisedF = sum(denoisedF),
    denoisedR = sum(denoisedR),
    merged = sum(merged),
    nonchim = sum(nonchim)
  )

overall_summary <- asv_table_with_taxo %>%
  select(asv_id, starts_with("RA")) %>% 
  pivot_longer(cols = starts_with("RA"), names_to = "sample", values_to = "nreads") %>% 
  group_by(sample) %>% 
  summarise(final_total = sum(nreads)) %>% 
  inner_join(overall_summary, ., by = "sample")

#####################################################################
# export
#####################################################################

# ampliseq table

write_tsv(asv_table_with_taxo,"output/final_tables/somlit-astan_ssuv4v5_ampliseq_table.tsv.gz")

# fasta file

sequences_to_export <- setNames(asv_table_with_taxo$sequence, asv_table_with_taxo$asv_id)
sequences_to_export <- DNAStringSet(sequences_to_export, use.names = TRUE)

writeXStringSet(
  sequences_to_export,
  "output/final_tables/somlit-astan_ssuv4v5_ampliseq.fasta.gz",
  compress = TRUE,
  format = "fasta"
)

# extra taxo

write_tsv(asv_extra_taxonomy, "output/final_tables/somlit-astan_ssuv4v5_ampliseq_taxo_pr2.tsv.gz")

# summary report

write_tsv(overall_summary, "output/final_tables/somlit-astan_ssuv4v5_ampliseq_log.tsv")

# nextflow report

file.copy(
  from = "output/ampliseq/summary_report/summary_report.html",
  to = "output/final_tables/somlit-astan_ssuv4v5_ampliseq_report.html",
  overwrite = TRUE
)

# multiqc report

file.copy(
  from = "output/ampliseq/multiqc/multiqc_report.html",
  to = "output/final_tables/somlit-astan_ssuv4v5_ampliseq_multiqc.html",
  overwrite = TRUE
)
