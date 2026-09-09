# Data availability and restricted-data statement

## Source databases

This project uses the eICU Collaborative Research Database and MIMIC-IV, accessed through PhysioNet under the applicable credentialing, training, and data-use requirements.

The source release identifiers used in the analysis are:

- **eICU-CRD release:** to be confirmed from the local source metadata.
- **MIMIC-IV release:** v3.1.

The database release identifiers must be identical in this file, the manuscript, the README, and the code metadata.

## What is included

This repository may include:

- analysis and figure-generation code;
- the versioned statistical analysis plan;
- variable definitions and phenotype rules;
- package and software-version metadata;
- aggregate tables and aggregate figure data that do not contain patient-level records or indirect identifiers;
- synthetic test data, if used.

## What is not included

The repository does not include:

- source eICU-CRD or MIMIC-IV files;
- patient-level extracts or derived patient-level datasets;
- `subject_id`, `hadm_id`, `stay_id`, `patientunitstayid`, or equivalent identifiers;
- exact patient-level timestamps;
- clinical notes or free-text fields;
- DuckDB, SQLite, parquet, RDS, or compressed CSV files containing restricted or derived patient-level data;
- credentials, tokens, passwords, or local filesystem paths.

Users who wish to reproduce the analysis must obtain the source databases independently and satisfy the applicable PhysioNet requirements. The code repository does not grant access to those databases.

## Compliance note

The public repository is intended to share the code associated with the publication, not to redistribute restricted clinical data. Any future sharing of derived data must be reviewed against the relevant PhysioNet agreement and, where required, performed through the approved PhysioNet mechanism.
