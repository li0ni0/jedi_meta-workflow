#!/usr/bin/env bash

#    ERX16780508 Illumina NovaSeq 6000
#    ERX16780509 Illumina NovaSeq 6000
#    ERX4203783  Illumina HiSeq 2500
#    ERX4203787  Illumina HiSeq 2500
#    ERX4203789  Illumina HiSeq 2500
#    ERX9148535  Illumina NovaSeq 6000
#    ERX9148625  Illumina MiSeq
#Infer the quality scores from the fastq files (binned or not)

# Samples the 4th line (quality scores) of the first 40,000 lines and counts unique characters
#Illumina NovaSeq 6000 example
zcat output/fetchngs/PRJEB52329/fastq/ERX16780508_ERR17391060_1.fastq.gz | head -n 16000 | awk 'NR%4==0' | fold -w1 | sort | uniq -c | wc -l 

#Make one group per nb of bins

#Illumina HiSeq 2500 example
zcat output/fetchngs/PRJEB52329/fastq/ERX4203783_ERR4244989_1.fastq.gz | head -n 16000 | awk 'NR%4==0' | fold -w1 | sort | uniq -c

#Illumina MiSeq
zcat output/fetchngs/PRJEB52329/fastq/ERX9148625_ERR9598321_1.fastq.gz | head -n 16000 | awk 'NR%4==0' | fold -w1 | sort | uniq -c


#Using vsearch

module load vsearch/2.31.0

vsearch --fastq_chars output/fetchngs/PRJEB52329/fastq/ERX16780508_ERR17391060_1.fastq.gz
vsearch --fastq_chars output/fetchngs/PRJEB52329/fastq/ERX4203783_ERR4244989_1.fastq.gz
vsearch --fastq_chars output/fetchngs/PRJEB52329/fastq/ERX9148625_ERR9598321_1.fastq.gz
