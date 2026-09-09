# Statistical Analysis Plan — Phase 2

**Study:** Pharmacologic strategies in suspected right-ventricular dysfunction: reanalysis with an expanded covariate set  
**Version:** 1.1, amended  
**Status:** Public version of a Phase 2 analysis plan  
**Public-deposit timing:** The plan was prepared after review of Phase 1 results and was intended to be locked before the Phase 2 outcome models. The public deposit occurred after the analysis; this document is therefore not a strict preregistration unless a dated registry record predating the Phase 2 models is available.

> The contemporaneous author-controlled freeze date and complete author list must be added to the signed archival copy. They must not be inferred or backdated.

## 0. Purpose

The previous phase produced associations that were implausibly large in the absence of adequate measures of illness severity and admission context. This Phase 2 plan fixes, before the Phase 2 outcome models, the covariate blocks, estimands, comparisons, feasibility rules, falsification analyses, sensitivity analyses, and interpretation rules.

The plan was developed after Phase 1 results had been reviewed. The Phase 1 results motivated the design changes described below but do not constitute prespecified evidence for the Phase 2 comparisons.

The purpose of the interpretation rules is to prevent an attenuated or null association from being reinterpreted as a smaller treatment effect. The analysis remains observational and cannot establish causality.

## 1. Design changes from Phase 1

### 1.1 Primary comparison

The single primary comparison is **milrinone versus dobutamine**, among patients initiating either drug as monotherapy in the eICU Collaborative Research Database and MIMIC-IV.

This is the only comparison for which clinical equipoise is considered defensible in the available data: both drugs may be selected for a similar patient with suspected right-ventricular dysfunction.

### 1.2 Comparisons removed from the primary results

| Comparison | Role in Phase 2 | Reason |
|---|---|---|
| Nitroprusside versus inodilators | Removed from the unrestricted primary analysis; conditional secondary analysis only under Section 1.3 | The unrestricted cohorts do not represent a clinically meaningful treatment choice because the treated populations do not satisfy positivity. |
| Inhaled vasodilators versus inodilators | Descriptive only | Small and incompletely captured groups with residual imbalance and uncertain ascertainment. |
| Combination therapy versus monotherapy | Removed | The 120-minute exposure classification is post-baseline and may introduce immortal-time bias. |
| Nitroglycerin | Removed | Contextual specificity was negligible after applying the clinical-context filter. |

These changes were made after Phase 1 and must be reported as post–Phase 1 methodological decisions, not as part of the original prespecification.

### 1.3 Conditional secondary analysis of nitroprusside

Nitroprusside may be reintroduced as a secondary comparison only if an equipoise-restricted population can be defined using information measured before treatment initiation. The unrestricted comparison is not estimable as a clinically interpretable contrast.

The restricted population requires all of the following conditions in the window from 15 to 360 minutes before time zero:

| Criterion | Requirement | Rationale |
|---|---|---|
| R1 | Pulmonary artery catheter in place with measured mean pulmonary artery pressure | The hemodynamic context must be documented. |
| R2 | Mean pulmonary artery pressure >25 mmHg, or elevated pulmonary vascular resistance when calculable | Pulmonary afterload must be demonstrably elevated. |
| R3 | Cardiac index 1.8–2.5 L/min/m² | This is the prespecified overlap band in which both strategies could be clinically defensible. |
| R4 | No baseline vasopressor exposure (`crit_vasopressor = 0`) | The patient must be sufficiently perfused to tolerate systemic vasodilation. |

R3 is the principal equipoise criterion. R1, R2, and R4 define the clinical context.

The analysis must first run a feasibility-only script that counts the eligible cells and does not calculate or print mortality estimates. The comparison can proceed only if, in at least one database, all of the following are satisfied:

- at least 100 admissions per treatment arm;
- at least 20 deaths in the smaller arm;
- fewer than 20% of observations outside the common propensity-score range.

If the thresholds are met, the comparison is reported as a prespecified secondary analysis using the M4 model and the same weighting and inference rules as the primary comparison. If the thresholds are not met, the comparison remains descriptive and no comparative outcome estimate is produced.

The number of admissions surviving R1–R4 must be reported regardless of whether the gate is passed. Conditioning on R1 also limits generalizability to patients who received invasive hemodynamic monitoring.

### 1.4 Outcome hierarchy

The primary outcome is **in-hospital mortality**.

Early treatment failure at 24 hours and complication flags are not primary comparative outcomes. They may be shown in supplementary material as descriptive, non-comparable measures because ascertainment differed substantially between databases.

## 2. Covariate set

The propensity model must include all available variables in each prespecified block. A model that omits the severity block is not considered a valid implementation of this plan.

### Block A — Severity

| eICU | MIMIC-IV |
|---|---|
| APACHE IVa score | Day-1 SOFA total and subscores |
| APACHE IVa predicted mortality | OASIS, if reliably reconstructed |
| Mechanical ventilation on day 1 | Mechanical ventilation on day 1 |

### Block B — Demographics

| eICU | MIMIC-IV |
|---|---|
| Age, with `>89` recoded as 90 | `anchor_age` |
| Sex | Sex |
| Admission BMI or weight | Admission weight |

### Block C — Admission context

| eICU | MIMIC-IV |
|---|---|
| `apacheadmissiondx` | `admissions.admission_type` |
| `unittype` | `services.curr_service` |
| Post-cardiac-surgery indicator | Post-cardiac-surgery indicator |
| Admission source | `admissions.admission_location` |

### Block D — Comorbidity

| eICU | MIMIC-IV |
|---|---|
| Chronic variables from `apachePredVar` | Charlson and Elixhauser indices |
| Chronic liver disease, immunosuppression, chronic heart failure, and related variables | Corresponding diagnosis-derived variables |

### Block E — Hemodynamic and phenotype variables

Central venous pressure, cardiac index, CVP/PAOP ratio, mean pulmonary artery pressure, PAPi, lactate or vasopressor status, the qualifying diagnosis, the number of phenotype criteria satisfied, and indicators of missingness are retained from the prior phenotype definition.

The duplicate MIMIC-IV `unit_cardiac` variable is not included in the final implementation because it was identical to the post-cardiac-surgery indicator in the available MIMIC-IV cohort. The final MIMIC-IV M4 model therefore has 27 covariates rather than 28.

## 3. Statistical methods

- A logistic-regression propensity score estimates the probability of initiating milrinone rather than dobutamine.
- Overlap weights are used: (1-PS) for milrinone initiators and (PS) for dobutamine initiators.
- The primary propensity-score restriction is 0.01–0.99.
- The primary effect measure is the overlap-weighted risk difference for in-hospital mortality.
- 95% confidence intervals use 500 bootstrap replicates, resampling hospitals in eICU and admissions in MIMIC-IV, with the propensity model refitted in each replicate.
- Covariate balance is assessed using standardized mean differences; absolute values above 0.10 indicate residual imbalance.
- A hierarchical eICU model with a hospital-level random intercept is complementary to the primary analysis.
- Approximate E-values are reported for the point estimate and for the confidence-limit estimate closest to the null.

The sensitivity analysis restricts the propensity score to 0.05–0.95. It does not implement percentile truncation of the weights.

## 4. Prespecified interpretation rule

The primary comparison is evaluated using the M0–M4 trajectory:

| Model | Covariate blocks |
|---|---|
| M0 | Block E only |
| M1 | E + B |
| M2 | E + B + A |
| M3 | E + B + A + C |
| M4 | E + B + A + C + D; primary model |

Define:

- `RD_M0`: the risk difference from the M0 model;
- `RD_M4`: the risk difference from the primary M4 model;
- attenuation: (1 - |RD_{M4}|/|RD_{M0}|);
- `EV_new`: the E-value based on the confidence limit closest to the null in the expanded model.

The numerical values of `RD_M0`, `RD_M4`, and attenuation are analysis outputs and do not belong in this plan. They must be reported in the results files and manuscript.

### Outcome 1 — Substantial attenuation or loss of precision

If attenuation is at least 50% in either database, or the confidence interval includes the null in either database, the association is interpreted as substantially explained by confounding from severity and/or admission context.

The manuscript conclusion should state that the apparent milrinone advantage is markedly reduced when severity and surgical context are addressed, and that unadjusted observational estimates should not guide treatment selection.

### Outcome 2 — Persistent association with low E-value

If attenuation is less than 50%, confidence intervals exclude the null in both databases, and `EV_new` is below 2.0, the association is considered persistent but compatible with a plausible unmeasured confounder. It is presented as hypothesis-generating without a claim of superiority or clinical effectiveness.

### Outcome 3 — Persistent association with higher E-value

If attenuation is less than 50%, confidence intervals exclude the null in both databases, and `EV_new` is at least 2.0, the falsification analyses in Section 5 must be completed before any directional conclusion is considered.

### Outcome 4 — Directional reversal

If the direction reverses relative to Phase 1, the reversal and the covariate block producing it must be reported. No directional clinical conclusion is made.

### Cross-cutting rule

If the estimate changes materially depending on the covariate block added, the analysis is considered non-identified for a clinically interpretable treatment association and is reported using the cautious interpretation in Outcome 1.

## 5. Falsification analyses

Falsification analyses are mandatory if Outcome 3 is reached.

### 5.1 Negative-control outcome

The negative-control outcome is in-hospital mortality attributed to a noncardiovascular cause. In MIMIC-IV this is operationalized using a noncirculatory principal discharge diagnosis; in eICU it uses a noncardiovascular admission-diagnosis restriction.

The expected risk difference is approximately null. A strong apparent milrinone association on this outcome indicates general severity confounding rather than a drug-specific signal.

### 5.2 Negative-control exposure

The negative-control exposure is a comparison between two agents or administration strategies without a plausible mortality difference in the same clinical population. A strong association on this contrast indicates that the analytic pipeline generates spurious differences more generally.

### 5.3 Surgical restriction

The primary comparison is repeated separately in post-cardiotomy and non-surgical strata. The hypothesis is that a signal concentrated in the mixed cohort but attenuated within strata reflects case-mix composition.

### 5.4 Falsification success criterion

A signal is considered sufficiently coherent for prospective study only if all three conditions are met:

1. the negative-control outcome is approximately null;
2. the negative-control exposure is approximately null;
3. the primary association is directionally concordant within both surgical strata.

Failure of any one condition leads to the cautious interpretation in Outcome 1.

## 6. Incremental covariate analysis

The propensity model is fitted five times, adding one block at a time as shown in Section 4. The risk-difference trajectory from M0 to M4 is displayed graphically to show which covariate block absorbs the association.

## 7. Sensitivity analyses

- Exclude patients with probable chronic milrinone exposure by restricting to admissions without a pre-admission diagnosis of advanced heart failure.
- Restrict to phenotype-positive admissions with a phenotype score of at least 2.
- Restrict the propensity score to 0.05–0.95.
- Restrict eICU analyses to hospitals with at least 20 initiators in each treatment arm.

## 8. Reporting requirements

- Report the complete cohort flow and the number of admissions at every restriction.
- Report the exact database releases and access requirements.
- Provide the STROBE checklist.
- Deposit the reviewed analysis code publicly.
- State explicitly that comparisons involving nitroprusside, inhaled agents, and combination therapy were removed or restricted after Phase 1 for methodological reasons.
- Report all prespecified outcomes, including attenuation or null findings.

## 9. Author commitments

The authors commit to:

1. not changing the M4 covariate set after reviewing `RD_M4`;
2. reporting the result regardless of whether it is attenuated, null, reversed, or persistent;
3. not returning nitroprusside to the primary results solely because of statistical significance;
4. disclosing all implementation deviations from this plan.

## 10. Amendments

The amendment dates must be copied from the contemporaneous author-controlled records. They must not be backdated.

### A1 — Propensity-score sensitivity definition

The original wording referred to truncating weights at the 1st and 99th percentiles. The implemented analysis instead restricts the propensity score from 0.01–0.99 to 0.05–0.95. The plan is amended to match the operation actually implemented. This is a different and more stringent sensitivity analysis; the manuscript must use the implemented definition.

### A2 — Attenuation denominator

The attenuation denominator is defined as the M0 risk difference from the reported M0–M4 trajectory rather than a risk difference imported from an earlier exploratory extraction. This makes the attenuation calculation internally consistent with the displayed trajectory. Numerical results are reported separately from this plan.

### A3 — Nitroprusside criterion R4

The original restriction required MAP at least 65 mmHg and norepinephrine below 0.10 µg/kg/min. Those measurements were not available in the Phase 1 extraction. R4 is therefore implemented as absence of baseline vasopressor exposure (`crit_vasopressor = 0`). This is a more permissive replacement and must be disclosed as an implementation deviation.

### A4 — MIMIC-IV severity block

OASIS and predicted mortality were not included in the MIMIC-IV implementation because the required concepts could not be reconstructed with sufficient reliability. Day-1 SOFA was reconstructed from raw tables. The eICU and MIMIC-IV adjustment sets are therefore not formally identical.

### A5 — PAPi cleaning

Non-finite and physiologically implausible PAPi values generated by zero or invalid CVP values are set to missing using a prespecified plausibility range of 0–20. The cleaning is performed inside the cohort-cleaning function so that it is applied consistently.
