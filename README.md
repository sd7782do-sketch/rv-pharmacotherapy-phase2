# Phase 2 reanalysis of vasoactive strategies in suspected right-ventricular dysfunction

This repository contains the analysis plan, reproducibility documentation, and code associated with the Phase 2 reanalysis of milrinone versus dobutamine in adults treated for a suspected right-ventricular dysfunction phenotype in the eICU Collaborative Research Database and MIMIC-IV.

The primary estimand is the difference in in-hospital mortality between patients initiating milrinone and patients initiating dobutamine as monotherapy. The analysis is observational and estimates associations; it does not establish treatment effects or comparative effectiveness.

## Important status statement

The Phase 2 analysis plan was written after the results of Phase 1 had been reviewed and was intended to be locked before the Phase 2 outcome models were run. The public repository was prepared after the analysis. Accordingly, this study should not be described as strictly preregistered unless a dated registry record predating the Phase 2 models is available.

## Repository contents

```text
docs/
  SAP_phase2_v1.1_EN.md
  REGISTRATION_AND_REPOSITORY_PUBLIC.md
  DATA_AVAILABILITY.md
R/
  rv_phase2_analysis.R                 # canonical single-file pipeline
python/                                 # add figure scripts here, if used
output/                                 # aggregate tables and figure data only
work/                                   # local DuckDB/RDS intermediates; ignored
LICENSE
CITATION.cff
.gitignore
```

## Data access

The eICU-CRD and MIMIC-IV source data are not included. Investigators must obtain access directly from PhysioNet and comply with the applicable credentialing and data-use agreements. No patient-level extracts, derived patient-level datasets, raw notes, identifiers, timestamps, or database files belong in this repository.

The analysis uses **MIMIC-IV v3.1**. The eICU-CRD release identifier must still be confirmed from the local source metadata before the public release.

## Analysis decisions preserved in this release

- Primary comparison: milrinone versus dobutamine, initiated as monotherapy.
- Primary outcome: in-hospital mortality.
- Propensity-score restriction: 0.01–0.99.
- Sensitivity restriction: 0.05–0.95.
- Overlap weighting and risk-difference estimation.
- Attenuation calculated against the M0 estimate of the reported trajectory.
- PAPi values are cleaned within the cohort-building function using the prespecified plausibility range.
- Nitroprusside has no comparative outcome estimate unless the prespecified feasibility gate is satisfied.
- The duplicate MIMIC-IV `unit_cardiac` variable is not included; the MIMIC-IV M4 covariate count is therefore 27, not 28.

## Local execution

1. Obtain the source databases independently from PhysioNet.
2. Keep all source files outside the Git repository.
3. Set local, uncommitted paths for the eICU and MIMIC-IV directories.
4. Run the reviewed R pipeline.
5. Run the figure scripts, if applicable.
6. Inspect `git status` and confirm that no `.rds`, `.duckdb`, `.csv.gz`, parquet, SQLite, or patient-level files are staged.

The code writes local DuckDB/RDS intermediates to the ignored `work/` directory. It should write only aggregate tables, aggregate figure data, logs without local usernames, session information, and figures to `output/`.

## Citation

Please cite the versioned release DOI assigned by Zenodo together with the accompanying manuscript. The DOI should identify the exact release used for the publication, not the mutable development branch.

## License

The code is released under the MIT License. The source clinical databases remain subject to their original access agreements and are not relicensed by this repository.
