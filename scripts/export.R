#Bash boolean variables to chose what to export
#To implement in main.sh

args <- commandArgs(trailingOnly = TRUE)
export_taxo <- args[1] #to export table with pr2, silva and consensus taxo
export_conflicts <- args[2] #to export domain conflicts between pr2 and silva

#Export tables to output/agregated/taxonomy ----

if (export_taxo){
  walk2(.x=pr2_silva_consensus,
        .y=projects_list,
        .f= ~ write_tsv(.x,
                        file=str_c("output/agregated/taxonomy/pr2_silva_consensus_",
                                   .y, ".tsv"), append=FALSE)
  )
}


if (export_conflicts){
  walk2(.x=domain_conflicts_per_projects,
        .y=projects_list,
        .f= ~ write_tsv(.x,
                        file=str_c("output/agregated/taxonomy/domain_conflicts_",
                                   .y, ".tsv"), append=FALSE)
  )
}