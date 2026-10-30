#!/usr/bin/env bash


#Metadata::
#Parameters

#If there are many params_trace_date_time.json for the same project (in same folder), 
#take the most recent one before comparing to other projects ?
#These files changes with the input parameters and the versions

#output/ampliseq_2db/PRJEB89924/pipeline_info/params_2026-10-19_10-29-05.json
#output/ampliseq_2db/PRJEB89924/pipeline_info/nf_core_ampliseq_software_mqc_versions.yml


#version of the software used - depends on the steps skipped in parameters_ampliseq.yaml:
#output/ampliseq_2db/PRJEB89924/pipeline_info/nf_core_ampliseq_software_mqc_versions.yml
diff output/ampliseq_2db/PRJEB89924/pipeline_info/nf_core_ampliseq_software_mqc_versions.yml output/ampliseq_2db/PRJEB52329/pipeline_info/nf_core_ampliseq_software_mqc_versions.yml

#command used
#inputs, IDs (agregated samplesheet?)
#parameters:
#.yaml and output/ampliseq_2db/PRJEB89924/pipeline_info/params_2026-10-19_10-29-05.json

