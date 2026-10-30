# jedi_meta-workflow

## Inputs  

### For fetchngs:  
To place in the folder input/fetchngs:  
- **params_fetchngs.yaml** file with parameters for fetchngs:  
    Currently, sample_mapping_fields argument is set to an empty string because fetchngs sens the following error message when let to default:  
    "Invalid option for '--sample_mapping_fields': experiment_accession,run_accession,sample_accession,experiment_alias,run_alias,sample_alias,experiment_title,sample_title,sample_description.  
    Valid options: sample, fastq_1, fastq_2, run, run_accession, experiment_accession, library_layout, fastq_ftp, fastq_md5, submitted_ftp, tax_id, library_name, sample_title"  
    (inconstitent with fetchngs documentation)    
    When both ena_metadata_fields and sample_mapping_fields are set to default, the latter is not a substring of the first.  
- **samplesheet** folder:  
    Contains input files of fetchngs. These files must be named {ID_PROJECT}.csv, with extension .csv .tsv or .txt and must contain one column, without header, listing the IDs of samples we want to download with fetchngs in the project. Only the project ID if you want to download every fastq available in the project. See fetchngs doc for more information [fetchngs: Usage](https://nf-co.re/fetchngs/1.13.0/docs/usage).  

What it does, for each projects separately:  
- download listed fastq or all of them if the name of the project was given in input/{ID_PROJECT}.csv  
- makes a samplesheet ready to use as input for ampliseq  


### For ampliseq:  
To place in the folder input/ampliseq:  
- **params_ampliseq.yaml** file with parameters for ampliseq.  
    - input and outdir are specified in the main and shouldn't be changed  
    - primer sequences are set to the ssu v4v5 (universal primer)  
- **{ID_Project}_metadata.tsv** optional file containing metadata corresponding to a specific project.  
    The first column must have the header "ID" and contain the list of Experiment Accession (from ENA EBI...) corresponding to the IDs given in input/fetchngs/samplesheet/{ID_PROJECT}.csv. This {ID_Project}_metadata.tsv file must be placed in the folder input/ampliseq/metadata.  



## Outputs  
In the folder output/agregated are found tables grouping all the projects together.

- [**cutadapt_dada2_summary.tsv**](https://nf-co.re/ampliseq/3.1.0/docs/output/#preprocessing):    
    Summary of read numbers that passed cutadapt and DADA2 processing steps, for each sample  
- [**overall_summary.tsv**](https://nf-co.re/ampliseq/3.1.0/docs/output/#pipeline-information):  
    "how many reads per sample passed each pipeline step in which a loss can occur"  
- [**all_projects_ampliseq_counts.tsv.gz**](https://nf-co.re/ampliseq/3.1.0/docs/output/#summary-tables):   
    "ASV counts in long format (asv_id, sample, count), zero-count rows dropped. Sourced from DADA2’s raw output, before clustering and any post-processing filters below"   

In the folder output/taxo_per_project, for each project we have the following tables:  
- **pr2_silva_consensus_{ID_PROJECT}.tsv**  
  containing pr2, silva and our consensus taxonomic assignation and confidence for each project.  
  The consensus is either pr2 or silva assignation kept and a column consensus_db clearly indicates which database made consensus.  
- **domain_conflicts_{ID_PROJECT}.tsv**  
  It states the ASVs that silva and pr2 assigned to different domains along with both assignated domains.  


## Options

**-h**  to print the help  
**-a**  Path to a file listing the samplesheets you want to analyse (one per line).  
    Samplesheets must be named ID_PROJECT.csv with extension .csv .tsv or .txt  
        Example:  
        ID_PROJECT1.csv  
        ID_PROJECT2.tsv  
        ...    
    If there are some other projects samplesheets, they will be ignored, even if their outputs have been deleted from the working directory.  
    Can be used when you have already successfully ran ampliseq on some projects and deleted their outputs than added some samplesheet for projects you also  want to run (without running the other ones again).
**-e**   Can take the values joined, conflicts or both. Default is none.  
         "joined" to export the tables with pr2, silva and consensus taxonomies (pr2_silva_consensus.tsv)  
         "conflicts" to export the tables listing domain conflicts (domain_conflicts.tsv)  
         "both" to export taxonomy and conflicts  
         One table per project.   


## Usage

sbatch main.sh -a <tmp/add_new_projects.txt> -e <joined;conflicts;both> [-h for help]  

**Examples:**
sbatch main.sh -a "tmp/add_new_projects.txt" -e both  
sbatch main.sh -e both  


## Main steps

1. Manual writing of input files  
2. Fetchngs: fastq downloading, ampliseq samplesheet(s) creation  
3. Ampliseq: ASVs calculation, taxonomic assignments  
