#Bash boolean variables to chose what to export
#To implement in main.sh

args <- commandArgs(trailingOnly = TRUE)
export <- args[1] #to export tables with pr2, silva and consensus taxo and/or domain conflicts tables

#Export tables to output/taxo_per_project ----

if (export=="joined"){
  walk2(.x=pr2_silva_consensus,
        .y=projects_list,
        .f= ~ write_tsv(.x,
            file=str_c("output/taxo_per_project/pr2_silva_consensus_",
            .y, ".tsv"), append=FALSE)
  )
} else if (export=="conflicts"){
  walk2(.x=domain_conflicts_per_projects,
        .y=projects_list,
        .f= ~ write_tsv(.x,
            file=str_c("output/taxo_per_project/domain_conflicts_",
            .y, ".tsv"), append=FALSE)
  )
} else if (export=="both"){
  walk2(.x=pr2_silva_consensus,
        .y=projects_list,
        .f= ~ write_tsv(.x,
            file=str_c("output/taxo_per_project/pr2_silva_consensus_",
            .y, ".tsv"), append=FALSE)

  walk2(.x=domain_conflicts_per_projects,
        .y=projects_list,
        .f= ~ write_tsv(.x,
            file=str_c("output/taxo_per_project/domain_conflicts_",
            .y, ".tsv"), append=FALSE)
} else{
  print(export)
  print('Invalid string given for -e argument. Use one of "joined", "conflicts" or "both".')
}
