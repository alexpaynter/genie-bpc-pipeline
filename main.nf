#!/usr/bin/env nextflow

params.cohort = 'NSCLC'
params.comment = 'NSCLC public release update'
params.synapse_config = '.synapseConfig'

ch_cohort = Channel.value(params.cohort)
ch_comment = Channel.value(params.comment)
ch_synapse_config = Channel.value(file(params.synapse_config))

/*
Check cohort code is one of the valid values.
*/
process checkCohortCode {
    input:
    val cohort from ch_cohort

    output:
    stdout into status

    script:
    """
    echo $cohorts | tr ' ' '\n' | grep -c ^$cohort\$
    """
}

/*
Run quality asssurance checklist for the upload report at error level.  
Stop the workflow if any errors are detected.
*/
process quacUploadReportError {

   container 'hhunterzinck/genie-bpc-quac'

   input:
   file syn_config   from ch_synapse_config
   val cohort        from ch_cohort

   output:
   stdout into outUploadReportError

   script:
   """
   R -e 'renv::restore(lockfile = "/usr/local/src/myscripts/renv.lock")'
   Rscript /usr/local/src/myscripts/genie-bpc-quac.R -a $syn_config -c $cohort -s all -r upload -l error -v
   """
}

outUploadReportError.view()

/*
Run quality asssurance checklist for the upload report at warning level.  
Do not stop the workflow if any issues are detected.
*/
process quacUploadReportWarning {

   container 'hhunterzinck/genie-bpc-quac'
   errorStrategy 'ignore'

   input:
   file syn_config   from ch_synapse_config
   val cohort        from ch_cohort

   output:
   stdout into outUploadReportWarning

   script:
   """
   R -e 'renv::restore(lockfile = "/usr/local/src/myscripts/renv.lock")'
   Rscript /usr/local/src/myscripts/genie-bpc-quac.R -a $syn_config -c $cohort -s all -r upload -l warning -v -u
   """
}

outUploadReportWarning.view()

/*
Merge and uncode REDcap export data files.   
*/
process mergeAndUncodeRcaUploads {

   container 'hhunterzinck/merge-and-uncode-rca-uploads'

   input:
   file syn_config   from ch_synapse_config
   val cohort        from ch_cohort

   output:
   stdout into outMergeAndUncodeRcaUploads

   script:
   """
   R -e 'renv::restore(lockfile = "/usr/local/src/myscripts/renv.lock")'
   Rscript /usr/local/src/myscripts/merge_and_uncode_rca_uploads.R -a $syn_config -c $cohort -s -v
   """
}

outMergeAndUncodeRcaUploads.view()

/*
Update Synapse tables with merged and uncoded data.
*/
process updateDataTable {

   container 'hhunterzinck/update-data-table'

   input:
   file syn_config   from ch_synapse_config
   val comment       from ch_comment

   script:
   """
   pip install -r /root/scripts/requirements.txt
   python /root/scripts/update_data_table.py -s $syn_config -m $comment primary
   """
}

/*
Update reference table storing the date of current and previous Synapse table updates
for later quality assurance checklist reports.s
*/
process updateDateTrackingTable {

   container 'hhunterzinck/update-date-tracking-table'

   input:
   file syn_config   from ch_synapse_config
   val cohort        from ch_cohort

   script:
   """
   R -e 'renv::restore(lockfile = "/usr/local/src/myscripts/renv.lock")'
   date_today=$(date +'%Y-%m-%d')
   Rscript /usr/local/src/myscripts/update_date_tracking_table.R -a $syn_config -c $cohort -d $date_today -s
   """
}

/*
Run quality asssurance checklist for the table report at error and warning level.  
Do not stop the workflow if any issues are detected.
*/
process quacTableReport {

   container 'hhunterzinck/genie-bpc-quac'
   errorStrategy 'ignore'

   input:
   file syn_config   from ch_synapse_config
   val cohort        from ch_cohort

   output:
   stdout into outTableReport

   script:
   """
   R -e 'renv::restore(lockfile = "/usr/local/src/myscripts/renv.lock")'
   Rscript /usr/local/src/myscripts/genie-bpc-quac.R -a $syn_config -c $cohort -s all -r table -l error -v -u
   Rscript /usr/local/src/myscripts/genie-bpc-quac.R -a $syn_config -c $cohort -s all -r table -l warning -v -u
   """
}

outTableReport.view()

/*
Run quality asssurance checklist for the comparison report at error and warning level.  
Do not stop the workflow if any issues are detected.
*/
process quacComparisonReport {

   container 'hhunterzinck/genie-bpc-quac'
   errorStrategy 'ignore'

   input:
   file syn_config   from ch_synapse_config
   val cohort        from ch_cohort

   output:
   stdout into outComparisonReport

   script:
   """
   R -e 'renv::restore(lockfile = "/usr/local/src/myscripts/renv.lock")'
   Rscript /usr/local/src/myscripts/genie-bpc-quac.R -a $syn_config -c $cohort -s all -r comparison -l error -v -u
   Rscript /usr/local/src/myscripts/genie-bpc-quac.R -a $syn_config -c $cohort -s all -r comparison -l warning -v -u
   """
}

outComparisonReport.view()

/*
Create drug masking report files on most recent Synapse table data.  
*/
process maskingReport {

   container 'hhunterzinck/masking-report'

   input:
   file syn_config   from ch_synapse_config
   val cohort        from ch_cohort

   output:
   stdout into outMaskingReport

   script:
   """
   R -e 'renv::restore(lockfile = "/usr/local/src/myscripts/renv.lock")'
   date_today=$(date +'%Y-%m-%d')
   Rscript /usr/local/src/myscripts/workflow_unmasked_drugs.R -a $syn_config -c $cohort -d $date_today -s 
   """
}

outMaskingReport.view()

/*
Update the case count table with current case counts calculated
from Synapse tables. 
*/
process updateCaseCountTable {

   container 'hhunterzinck/update-case-count-table'

   input:
   file syn_config   from ch_synapse_config
   val comment       from ch_comment

   output:
   stdout into outCaseCount

   script:
   """
   R -e 'renv::restore(lockfile = "/usr/local/src/myscripts/renv.lock")'
   Rscript /usr/local/src/myscripts/update_case_count_table.R -a $syn_config -c $comment -s 
   """
}

outCaseCount.view()

