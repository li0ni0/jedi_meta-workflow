# jedi_meta-workflow

## Input  

### For fetchngs:  
To place in the folder input/fetchngs:  
- **params_fetchngs.yaml** file with parameters for fetchngs:  
    Currently, sample_mapping_fields argument is set to an empty string because fetchngs sens the following error message when let to default:  
    "Invalid option for '--sample_mapping_fields': experiment_accession,run_accession,sample_accession,experiment_alias,run_alias,sample_alias,experiment_title,sample_title,sample_description.  
    Valid options: sample, fastq_1, fastq_2, run, run_accession, experiment_accession, library_layout, fastq_ftp, fastq_md5, submitted_ftp, tax_id, library_name, sample_title"  
    (inconstitent with fetchngs documentation)    
    When both ena_metadata_fields and sample_mapping_fields are set to default, the latter is not a substring of the first.  
- **samplesheet** folder:  
    Contains input files of fetchngs. These files must be named {ID_PROJECT}.csv and contain one column, without header, listing the IDs of samples we want to download with fetchngs in the project. Only the project ID if you want to download every fastq available in the project. See fetchngs doc for more information [fetchngs: Usage](https://nf-co.re/fetchngs/1.13.0/docs/usage).  

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
