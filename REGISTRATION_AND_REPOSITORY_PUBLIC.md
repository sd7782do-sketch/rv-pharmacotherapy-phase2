# Public registration and repository statement

## What this record documents

The Phase 2 statistical analysis plan fixed the primary contrast, cohort and time-zero framework, covariate blocks, weighting strategy, feasibility gate, falsification analyses, sensitivity analyses, and interpretation rules for the reanalysis of milrinone versus dobutamine.

The plan was developed after the results of Phase 1 had been reviewed. It was intended to be locked before the Phase 2 outcome models were executed. The public record was prepared after the analysis. Therefore, this repository does **not** claim strict preregistration unless a dated registry record predating the Phase 2 models is separately documented.

## Changes from Phase 1

The following decisions were made for methodological reasons after Phase 1:

- milrinone versus dobutamine became the only primary comparison;
- nitroprusside was removed from the unrestricted primary comparisons and could return only as a prespecified secondary analysis if the feasibility gate was satisfied;
- inhaled vasodilators were retained as descriptive only;
- combination therapy was removed because the 120-minute exposure classification could introduce immortal-time bias;
- nitroglycerin was removed because of negligible contextual specificity;
- early treatment failure and complication flags were moved out of the main comparative outcomes because ascertainment was not comparable between databases.

These decisions must be described as post–Phase 1 design changes, not as part of the original prespecification.

## Documented implementation deviations

The public manuscript should disclose the following implementation details:

1. OASIS and predicted mortality were not reconstructed reliably in MIMIC-IV.
2. Day-1 SOFA was reconstructed from raw MIMIC-IV tables rather than taken from a derived concept table.
3. The adjustment sets are therefore not formally identical across eICU and MIMIC-IV.
4. The implemented sensitivity analysis restricts the propensity score to 0.05–0.95; it does not truncate weights at the 1st and 99th percentiles.
5. Attenuation is calculated relative to the M0 estimate from the reported M0–M4 trajectory.
6. PAPi cleaning is performed within the cohort-cleaning function using the prespecified plausibility range of 0–20.
7. The MIMIC-IV `unit_cardiac` variable was removed because it duplicated the post-cardiac-surgery indicator; the MIMIC-IV M4 covariate count is 27.

## What this file is not

This is a public transparency record. It is not a substitute for a dated prospective registry entry, and it does not convert an analysis deposited after execution into a preregistered study.
