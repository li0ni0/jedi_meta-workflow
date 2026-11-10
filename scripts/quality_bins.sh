#!/usr/bin/env bash

#Optional check of quality from the fastq (add option -c ?)


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
zcat output/fetchngs/PRJEB52329/fastq/ERX16780508_ERR17391060_1.fastq.gz | head -n 16000 | awk 'NR%4==0' | fold -w1 | sort | uniq -c 

#Make one group per nb of bins

#Illumina HiSeq 2500 example
zcat output/fetchngs/PRJEB52329/fastq/ERX4203783_ERR4244989_1.fastq.gz | head -n 16000 | awk 'NR%4==0' | fold -w1 | sort | uniq -c

#Illumina MiSeq
zcat output/fetchngs/PRJEB52329/fastq/ERX9148625_ERR9598321_1.fastq.gz | head -n 16000 | awk 'NR%4==0' | fold -w1 | sort | uniq -c

#Alternatively
zcat output/fetchngs/PRJEB89924/fastq/ERX14487745_ERR15083216_1.fastq.gz | sed -n '4~4p' | fold -w1 | sort -u | tr -d '\n'

#Using vsearch

module load vsearch/2.31.0

vsearch --fastq_chars output/fetchngs/PRJEB52329/fastq/ERX16780508_ERR17391060_1.fastq.gz
vsearch --fastq_chars output/fetchngs/PRJEB52329/fastq/ERX4203783_ERR4244989_1.fastq.gz
vsearch --fastq_chars output/fetchngs/PRJEB52329/fastq/ERX9148625_ERR9598321_1.fastq.gz

module load seqkit/2.13.0
fastq_file="output/fetchngs/PRJEB89924/fastq/ERX14487745_ERR15083216_1.fastq.gz"
seqkit fx2tab -q -H $fastq_file | head -n 100 | cut -f 3

seqkit stats output/fetchngs/PRJEB52329/fastq/ERX4203783_ERR4244989_1.fastq.gz

module load fastp/1.4.0

fastp -i output/fetchngs/PRJEB52329/fastq/ERX4203783_ERR4244989_1.fastq.gz
fastp -i output/fetchngs/PRJEB52329/fastq/ERX9148625_ERR9598321_1.fastq.gz 


#Issue ampliseq quality bins - just removes 33 to ASCII
vsearch --fastq_chars output/fetchngs/PRJEB52329/fastq/ERX4203783_ERR4244989_1.fastq.gz

bin_ERX4203783=$(zcat output/fetchngs/PRJEB52329/fastq/ERX4203783_ERR4244989_1.fastq.gz | head -n 10000 | awk 'NR%4==0' | tr -d '\n' | od -An -t u1 | tr ' ' '\n' | sort -u | awk '{print $1-33}' | awk '$1 >= 0')
zcat output/fetchngs/PRJEB52329/fastq/ERX4203783_ERR4244989_1.fastq.gz | head -n 10000 | awk 'NR%4==0' | tr -d '\n' | od -An -t u1 | tr ' ' '\n' | sort -u | awk '{print $1-33}' | awk '$1 >= 0'
#If there are some values above 40 (or below 0 without last awk), it was Phred+64, change accordingly

#######################
#Once we have the quality scores
#######################
#Separate the samples by type of quality bins

#Check all the samples of all the projects using the agregated output
while IFS= read -r fastq_file; do
    bin=$(zcat $fastq_file | head -n 10000 | awk 'NR%4==0' | tr -d '\n' | od -An -t u1 | tr ' ' '\n' | sort -u | awk '{print $1-33}' | awk '$1 >= 0')
    
done < output/agregated/input_samples.txt
