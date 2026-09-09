# Items to complete before creating the DOI release

The following metadata cannot be inferred safely from the supplied files and must be completed by the authors:

- [ ] exact eICU-CRD release identifier;
- [x] exact MIMIC-IV release identifier: v3.1;
- [ ] contemporaneous Phase 2 analysis-freeze date, without backdating;
- [ ] complete author list and ORCID identifiers in `CITATION.cff`;
- [ ] final GitHub repository URL;
- [ ] final Zenodo DOI after the release is published;
- [ ] funding, conflicts of interest, ethics/waiver statement, and CRediT roles;
- [ ] run the R pipeline successfully against the intended source releases and add any final Python figure scripts;
- [ ] confirmation that no `.rds`, `.duckdb`, `.csv.gz`, parquet, SQLite, or patient-level files are staged;
- [ ] confirmation that the manuscript reports 27 rather than 28 MIMIC-IV M4 covariates.

The files in this directory are a corrected release candidate. They should not be represented as the final DOI deposit until the checklist is complete.
