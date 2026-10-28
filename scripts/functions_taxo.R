##Functions for the taxonomic tables


# SILVA confidence scores ----
# Set to NA when it's not a real value
manage_silva_confidences <- function(silva_taxonomy_table, taxo_ranks){
  for (r in taxo_ranks) {
    col_taxo <- r
    col_conf <- paste0(tolower(r), "_confidence")
    silva_taxonomy_table <- silva_taxonomy_table |> 
      mutate(
        !!sym(col_conf) := ifelse(
          is.na(.data[[col_taxo]]) & .data[[col_conf]] > 0.5, 
          NA, 
          .data[[col_conf]]
        )
      )
  }
  return(silva_taxonomy_table)
}

#Table formatting ----
format_taxo_table <- function(refDB_project_taxo) {
  if (str_detect(deparse(substitute(refDB_project_taxo)), "pr2")){
    refDB_project_taxo |> 
      unite(col=pr2_dada2_taxonomy, Domain:Species, sep=";") |> 
      select(ASV_ID, pr2_dada2_taxonomy, confidence) |> 
      rename(pr2_dada2_confidence=confidence)
  } else if (str_detect(deparse(substitute(refDB_project_taxo)), "silva")) {
    refDB_project_taxo |> 
      unite(col=silva_dada2_taxonomy, Domain:Species, sep=";") |> 
      select(ASV_ID, silva_dada2_taxonomy, confidence) |> 
      rename(silva_dada2_confidence=confidence)
  } else {
    print("Reference database is not pr2 and not silva.")
  }
}

format_taxo_table_pr2 <- function(refDB_project_taxo) {
    refDB_project_taxo |> 
    unite(col=pr2_dada2_taxonomy, Domain:Species, sep=";") |>
    unite(col=pr2_dada2_allConfidences, domain_confidence:species_confidence, sep=";") |> 
    select(ASV_ID, pr2_dada2_taxonomy, confidence, pr2_dada2_allConfidences) |> 
    rename(pr2_dada2_confidence=confidence)
}

format_taxo_table_silva <- function(refDB_project_taxo) {
    refDB_project_taxo |> 
    unite(col=silva_dada2_taxonomy, Domain:Species, sep=";") |>
    unite(col=silva_dada2_allConfidences, domain_confidence:species_confidence, sep=";") |> 
    select(ASV_ID, silva_dada2_taxonomy, confidence, silva_dada2_allConfidences) |> 
    rename(silva_dada2_confidence=confidence)
}





## Get conflict info on the domain level ----

domain_conflict <- function(pr2_silva_joined_taxonomy_table){
  pr2_silva_joined_taxonomy_table |> 
    mutate(across(.cols=c(pr2_dada2_taxonomy, silva_dada2_taxonomy),
                  ~ str_extract(.x, "[^;]+"),
                  .names="{.col}_domain")) |>
    filter(pr2_dada2_taxonomy_domain != silva_dada2_taxonomy_domain) |> 
    select(ASV_ID, pr2_dada2_taxonomy_domain, silva_dada2_taxonomy_domain)
}



### Make consesus taxonomy ----

make_consensus_taxo <- function(taxonomy) {
  taxonomy |> 
    mutate(
      consensus_dada2_taxonomy = case_when(
        str_detect(pr2_dada2_taxonomy, "^Eukaryota") ~ pr2_dada2_taxonomy,
        str_detect(silva_dada2_taxonomy, "Mitochondria") ~ "Eukaryota:mito",
        str_detect(silva_dada2_taxonomy, "^Eukaryota|Chloroplast") ~ "conflict",
        str_detect(silva_dada2_taxonomy, "^Bacteria|^Archaea") ~ silva_dada2_taxonomy,
        pr2_dada2_taxonomy == "" | silva_dada2_taxonomy == "" ~ "unassigned",
        .default = NA
      ),
      consensus_dada2_confidence = case_when(
        str_detect(pr2_dada2_taxonomy, "^Eukaryota") ~ pr2_dada2_confidence,
        str_detect(silva_dada2_taxonomy, "Mitochondria") ~ silva_dada2_confidence,
        str_detect(silva_dada2_taxonomy, "^Eukaryota|Chloroplast") ~ NA,
        str_detect(silva_dada2_taxonomy, "^Bacteria|^Archaea") ~ silva_dada2_confidence,
        pr2_dada2_taxonomy == "" | silva_dada2_taxonomy == "" ~ NA,
        .default = NA
      )
    )
}





