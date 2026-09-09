# =============================================================================
#  Sequential confounder adjustment in two intensive care databases
#  Milrinone vs dobutamine in suspected right ventricular dysfunction
#
#  Companion code for the manuscript and for the Phase 2 analysis plan
#  (docs/SAP_phase2_v1.1_EN.md). Runs end to end in a single file.
#
#  Requirements
#    R >= 4.2 with: data.table, duckdb, DBI, lme4
#    eICU-CRD v2.0 and MIMIC-IV v3.1, obtained from PhysioNet under their
#    respective credentialing and data use agreements.
#
#  Runtime
#    First run 30-70 min, dominated by the MIMIC-IV derived-concept build
#    (chartevents ~3.3 GB, labevents ~2.5 GB). Later runs skip that step.
#
#  Data are NOT redistributed with this code. Set the three paths below.
# =============================================================================

## ---------------------------------------------------------------------------
## 0. CONFIGURATION -- edit these three paths only
## ---------------------------------------------------------------------------

PROJ_ROOT <- "."                    # project root; edit only the three paths
EICU_DIR  <- "<PATH>/eICU"          # folder holding the eICU-CRD csv(.gz) files
MIMIC_DIR <- "<PATH>/mimiciv"       # folder holding the MIMIC-IV csv(.gz) files

suppressPackageStartupMessages({
  library(data.table); library(duckdb); library(DBI); library(lme4)
})

CFG <- list(
  seed       = 20260101,
  n_boot     = 500,
  ps_trim    = c(0.01, 0.99),   # primary propensity score restriction
  smd_thresh = 0.10
)

set.seed(CFG$seed)
OUT      <- file.path(PROJ_ROOT, "output")
WORK     <- file.path(PROJ_ROOT, "work")
INTERMEDIATE <- file.path(WORK, "intermediate")
DUCK_TMP <- file.path(WORK, "duckdb_tmp")
DB       <- file.path(WORK, "rv_phase2.duckdb")
dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
dir.create(INTERMEDIATE, recursive = TRUE, showWarnings = FALSE)
dir.create(WORK, recursive = TRUE, showWarnings = FALSE)
dir.create(DUCK_TMP, recursive = TRUE, showWarnings = FALSE)

stopifnot(dir.exists(EICU_DIR), dir.exists(MIMIC_DIR))

# Covariate blocks (analysis plan, Section 2).
BLOCKS <- list(
  E = c("cvp", "cardiac_index", "cvp_pcwp_ratio", "mpap", "papi",
        "lactate_or_vasopressor", "qualifying_dx", "phenotype_n"),
  B = c("age", "female", "weight_kg"),
  A = c("severity_score", "severity_pred_mort", "vent_day1"),
  # unit_cardiac is retained for eICU only; in MIMIC-IV it is identical to
  # post_cardiac_surgery and is not constructed (see Supplementary Methods).
  C = c("post_cardiac_surgery", "admit_cardiac", "unit_cardiac",
        "admission_type_surgical"),
  D = c("chronic_hf", "chronic_resp", "chronic_renal", "chronic_liver",
        "immunosuppressed", "comorb_index")
)

MODELS <- list(
  M0 = BLOCKS$E,
  M1 = c(BLOCKS$E, BLOCKS$B),
  M2 = c(BLOCKS$E, BLOCKS$B, BLOCKS$A),
  M3 = c(BLOCKS$E, BLOCKS$B, BLOCKS$A, BLOCKS$C),
  M4 = c(BLOCKS$E, BLOCKS$B, BLOCKS$A, BLOCKS$C, BLOCKS$D)
)
PRIMARY_MODEL <- "M4"

# Decision rule (analysis plan, Section 4). Attenuation is measured against
# the M0 estimate of the reported trajectory (amendment A2).
ATTENUATION_THRESHOLD <- 0.50
EVALUE_THRESHOLD      <- 2.0

# Nitroprusside overlap restriction R1-R4 (analysis plan, Section 1.3).
# R4 is the amended criterion (amendment A3): absence of any baseline
# vasopressor, substituted for the originally intended MAP and
# norepinephrine-rate thresholds, which were unavailable in the source data.
NTP_RESTRICTION <- list(mpap_min = 25, ci_min = 1.8, ci_max = 2.5)
NTP_FEASIBILITY <- list(min_n_per_arm = 100, min_events_small = 20,
                        max_off_support = 0.20)

# DuckDB connection. Options must be set at instance creation: the temporary
# directory cannot be changed once used, and the instance is cached for the
# session.
duck_connect <- function(path, read_only = FALSE) {
  cfg <- list(temp_directory = gsub("\\\\", "/", normalizePath(DUCK_TMP)),
              memory_limit = "6GB", threads = "4",
              preserve_insertion_order = "false")
  tryCatch(
    DBI::dbConnect(duckdb::duckdb(), dbdir = path, read_only = read_only,
                   config = cfg),
    error = function(e) {
      try(duckdb::duckdb_shutdown(duckdb::duckdb()), silent = TRUE)
      DBI::dbConnect(duckdb::duckdb(), dbdir = path, read_only = read_only,
                     config = cfg)
    })
}

## ---------------------------------------------------------------------------
## 1. ATTACH SOURCE TABLES AS DUCKDB VIEWS
##    Nothing is imported; the files are read in place.
## ---------------------------------------------------------------------------

EICU_TABLES <- c("patient", "apachepatientresult", "apachepredvar",
                 "apacheapsvar", "diagnosis", "treatment", "infusiondrug",
                 "medication", "lab", "vitalperiodic", "vitalaperiodic")

MIMIC_MAP <- list(
  mimiciv_hosp = c("admissions", "patients", "transfers", "services",
                   "diagnoses_icd", "d_icd_diagnoses", "procedures_icd",
                   "labevents", "d_labitems", "prescriptions", "pharmacy"),
  mimiciv_icu  = c("icustays", "chartevents", "d_items", "inputevents",
                   "outputevents", "procedureevents", "datetimeevents")
)

attach_views <- function() {
  con <- duck_connect(DB); on.exit(dbDisconnect(con, shutdown = TRUE))

  scan_dir <- function(d) {
    f <- list.files(d, recursive = TRUE, full.names = TRUE,
                    pattern = "\\.(csv|csv\\.gz|tsv|parquet)$")
    data.table(path = f,
               tab = tolower(sub("\\.(csv|tsv)(\\.gz)?$|\\.parquet$", "",
                                 basename(f))),
               mb = round(file.size(f) / 1024^2, 1))
  }
  reader <- function(p) if (grepl("parquet$", p))
    sprintf("read_parquet('%s')", p) else
      sprintf("read_csv_auto('%s', header=true, sample_size=-1, union_by_name=true)", p)

  mk <- function(schema, name, path) {
    if (!is.na(schema))
      dbExecute(con, sprintf("CREATE SCHEMA IF NOT EXISTS %s", schema))
    full <- if (is.na(schema)) sprintf('"%s"', name) else
      sprintf('%s."%s"', schema, name)
    dbExecute(con, sprintf("CREATE OR REPLACE VIEW %s AS SELECT * FROM %s",
                           full, reader(path)))
  }

  e <- scan_dir(EICU_DIR)[tab %in% EICU_TABLES]
  setorder(e, tab, -mb); e <- unique(e, by = "tab")
  for (i in seq_len(nrow(e))) try(mk(NA, e$tab[i], e$path[i]), silent = TRUE)

  m <- scan_dir(MIMIC_DIR)
  m[, schema := NA_character_]
  for (s in names(MIMIC_MAP)) m[tab %in% MIMIC_MAP[[s]], schema := s]
  m <- m[!is.na(schema)]; setorder(m, schema, tab, -mb)
  m <- unique(m, by = c("schema", "tab"))
  for (i in seq_len(nrow(m)))
    try(mk(m$schema[i], m$tab[i], m$path[i]), silent = TRUE)

  cat("Attached", nrow(e), "eICU and", nrow(m), "MIMIC-IV tables.\n")
  invisible(NULL)
}

## ---------------------------------------------------------------------------
## 2. BUILD MIMIC-IV DERIVED CONCEPTS
##    The MIT-LCP derived schema was unavailable, so day-1 SOFA, Charlson,
##    ventilation and weight are reconstructed from raw tables. This is a
##    documented departure from the analysis plan (amendment A4).
## ---------------------------------------------------------------------------

build_mimic_derived <- function() {
  con <- duck_connect(DB); on.exit(dbDisconnect(con, shutdown = TRUE))

  already <- tryCatch(
    dbGetQuery(con, "SELECT COUNT(*) n FROM mimiciv_derived.first_day_sofa")$n[1] > 0,
    error = function(e) FALSE)
  if (already) { cat("mimiciv_derived already present; skipping build.\n")
    return(invisible(NULL)) }

  dbExecute(con, "CREATE SCHEMA IF NOT EXISTS mimiciv_derived")
  step <- function(label, sql) {
    cat(" ", label, "... "); t0 <- Sys.time(); dbExecute(con, sql)
    cat(round(difftime(Sys.time(), t0, units = "min"), 1), "min\n")
  }

  step("weight", "
CREATE OR REPLACE TABLE mimiciv_derived.weight_durations AS
SELECT stay_id, AVG(patientweight) AS weight
FROM mimiciv_icu.inputevents
WHERE patientweight BETWEEN 25 AND 300 GROUP BY stay_id")

  step("ventilation", "
CREATE OR REPLACE TABLE mimiciv_derived.ventilation AS
SELECT stay_id, starttime, endtime,
       CASE WHEN itemid = 225792 THEN 'InvasiveVent'
            WHEN itemid = 225794 THEN 'NonInvasiveVent'
            ELSE 'Tracheostomy' END AS ventilation_status
FROM mimiciv_icu.procedureevents WHERE itemid IN (225792, 225794, 224385)")

  # Charlson comorbidity index from ICD-9-CM and ICD-10-CM codes, following
  # published coding algorithms.
  step("charlson", "
CREATE OR REPLACE TABLE mimiciv_derived.charlson AS
WITH d AS (SELECT hadm_id, icd_version, REPLACE(icd_code,'.','') AS c
           FROM mimiciv_hosp.diagnoses_icd),
f AS (SELECT hadm_id,
  MAX(CASE WHEN (icd_version=9 AND c LIKE '428%')
            OR (icd_version=10 AND (c LIKE 'I50%' OR c LIKE 'I110%'))
           THEN 1 ELSE 0 END) AS congestive_heart_failure,
  MAX(CASE WHEN (icd_version=9 AND (c LIKE '49%' OR c LIKE '500%' OR c LIKE '505%'))
            OR (icd_version=10 AND (c LIKE 'J4%' OR c LIKE 'J60%' OR c LIKE 'J61%'
                                 OR c LIKE 'J84%' OR c LIKE 'J96%'))
           THEN 1 ELSE 0 END) AS chronic_pulmonary_disease,
  MAX(CASE WHEN (icd_version=9 AND (c LIKE '585%' OR c LIKE '586%' OR c LIKE '5830%'))
            OR (icd_version=10 AND (c LIKE 'N18%' OR c LIKE 'N19%' OR c LIKE 'N05%'))
           THEN 1 ELSE 0 END) AS renal_disease,
  MAX(CASE WHEN (icd_version=9 AND (c LIKE '5712%' OR c LIKE '5715%' OR c LIKE '5716%'))
            OR (icd_version=10 AND (c LIKE 'K70%' OR c LIKE 'K73%' OR c LIKE 'K74%'))
           THEN 1 ELSE 0 END) AS mild_liver_disease,
  MAX(CASE WHEN (icd_version=9 AND (c LIKE '4560%' OR c LIKE '4561%'
                                 OR c LIKE '5722%' OR c LIKE '5724%'))
            OR (icd_version=10 AND (c LIKE 'K704%' OR c LIKE 'K72%' OR c LIKE 'I85%'))
           THEN 1 ELSE 0 END) AS severe_liver_disease,
  MAX(CASE WHEN (icd_version=9 AND c LIKE '250%')
            OR (icd_version=10 AND (c LIKE 'E10%' OR c LIKE 'E11%' OR c LIKE 'E13%'))
           THEN 1 ELSE 0 END) AS diabetes,
  MAX(CASE WHEN (icd_version=9 AND c BETWEEN '140' AND '1729')
            OR (icd_version=10 AND (c LIKE 'C0%' OR c LIKE 'C1%' OR c LIKE 'C2%'
                                 OR c LIKE 'C3%' OR c LIKE 'C4%' OR c LIKE 'C5%'
                                 OR c LIKE 'C6%' OR c LIKE 'C8%' OR c LIKE 'C9%'))
           THEN 1 ELSE 0 END) AS malignant_cancer,
  MAX(CASE WHEN (icd_version=9 AND (c LIKE '196%' OR c LIKE '197%' OR c LIKE '198%'))
            OR (icd_version=10 AND (c LIKE 'C77%' OR c LIKE 'C78%' OR c LIKE 'C79%'))
           THEN 1 ELSE 0 END) AS metastatic_solid_tumor,
  MAX(CASE WHEN (icd_version=9 AND c LIKE '042%')
            OR (icd_version=10 AND (c LIKE 'B20%' OR c LIKE 'B21%' OR c LIKE 'B24%'))
           THEN 1 ELSE 0 END) AS aids,
  MAX(CASE WHEN (icd_version=9 AND c LIKE '410%')
            OR (icd_version=10 AND (c LIKE 'I21%' OR c LIKE 'I22%'))
           THEN 1 ELSE 0 END) AS myocardial_infarct,
  MAX(CASE WHEN (icd_version=9 AND (c LIKE '43%' OR c LIKE '436%'))
            OR (icd_version=10 AND (c LIKE 'I6%' OR c LIKE 'G45%'))
           THEN 1 ELSE 0 END) AS cerebrovascular_disease
  FROM d GROUP BY hadm_id)
SELECT *, congestive_heart_failure + chronic_pulmonary_disease
        + myocardial_infarct + cerebrovascular_disease + diabetes
        + mild_liver_disease + 2*renal_disease + 2*malignant_cancer
        + 3*severe_liver_disease + 6*metastatic_solid_tumor + 6*aids
        AS charlson_comorbidity_index
FROM f")

  # Day-1 SOFA, worst values in the first 24 h. Built in separate steps
  # because a single query over chartevents and labevents exhausts memory.
  step("SOFA 1/5 laboratory", "
CREATE OR REPLACE TABLE mimiciv_derived.fd_lab AS
SELECT ie.stay_id,
  MIN(CASE WHEN l.itemid = 51265 THEN l.valuenum END) AS platelet_min,
  MAX(CASE WHEN l.itemid = 50885 THEN l.valuenum END) AS bilirubin_max,
  MAX(CASE WHEN l.itemid = 50912 THEN l.valuenum END) AS creatinine_max,
  MIN(CASE WHEN l.itemid = 50821 THEN l.valuenum END) AS pao2_min
FROM mimiciv_icu.icustays ie
JOIN mimiciv_hosp.labevents l ON l.hadm_id = ie.hadm_id
 AND l.charttime BETWEEN ie.intime - INTERVAL 6 HOUR AND ie.intime + INTERVAL 1 DAY
WHERE l.itemid IN (51265, 50885, 50912, 50821) AND l.valuenum > 0
GROUP BY ie.stay_id")

  step("SOFA 2/5 chartevents (slow)", "
CREATE OR REPLACE TABLE mimiciv_derived.fd_chart AS
SELECT ie.stay_id,
  MIN(CASE WHEN c.itemid IN (220052,220181,225312)
            AND c.valuenum BETWEEN 10 AND 200 THEN c.valuenum END) AS map_min,
  MAX(CASE WHEN c.itemid = 223835 AND c.valuenum BETWEEN 21 AND 100
           THEN c.valuenum END) AS fio2_max,
  COALESCE(MIN(CASE WHEN c.itemid=220739 THEN c.valuenum END),4)
+ COALESCE(MIN(CASE WHEN c.itemid=223900 THEN c.valuenum END),5)
+ COALESCE(MIN(CASE WHEN c.itemid=223901 THEN c.valuenum END),6) AS gcs_min
FROM mimiciv_icu.icustays ie
JOIN mimiciv_icu.chartevents c ON c.stay_id = ie.stay_id
 AND c.charttime BETWEEN ie.intime AND ie.intime + INTERVAL 1 DAY
WHERE c.itemid IN (220052,220181,225312,220739,223900,223901,223835)
GROUP BY ie.stay_id")

  step("SOFA 3/5 urine output", "
CREATE OR REPLACE TABLE mimiciv_derived.fd_uo AS
SELECT ie.stay_id, SUM(o.value) AS urineoutput
FROM mimiciv_icu.icustays ie
JOIN mimiciv_icu.outputevents o ON o.stay_id = ie.stay_id
 AND o.charttime BETWEEN ie.intime AND ie.intime + INTERVAL 1 DAY
WHERE o.itemid IN (226559,226560,226561,226584,226563,226564,226565,
                   226567,226557,226558,227488,227489)
GROUP BY ie.stay_id")

  step("SOFA 4/5 vasoactive agents", "
CREATE OR REPLACE TABLE mimiciv_derived.fd_vp AS
SELECT ie.stay_id,
  MAX(CASE WHEN i.itemid = 221906 THEN i.rate END) AS norepi,
  MAX(CASE WHEN i.itemid = 221289 THEN i.rate END) AS epi,
  MAX(CASE WHEN i.itemid = 221662 THEN i.rate END) AS dopa,
  MAX(CASE WHEN i.itemid = 221653 THEN i.rate END) AS dobu
FROM mimiciv_icu.icustays ie
JOIN mimiciv_icu.inputevents i ON i.stay_id = ie.stay_id
 AND i.starttime BETWEEN ie.intime AND ie.intime + INTERVAL 1 DAY
WHERE i.itemid IN (221906,221289,221662,221653) AND i.rate > 0
GROUP BY ie.stay_id")

  step("SOFA 5/5 assembly", "
CREATE OR REPLACE TABLE mimiciv_derived.fd_components AS
SELECT ie.stay_id, lb.platelet_min, lb.bilirubin_max, lb.creatinine_max,
       lb.pao2_min, ce.map_min, ce.fio2_max, ce.gcs_min, uo.urineoutput,
       vp.norepi, vp.epi, vp.dopa, vp.dobu,
       CASE WHEN v.stay_id IS NULL THEN 0 ELSE 1 END AS vent_day1
FROM mimiciv_icu.icustays ie
LEFT JOIN mimiciv_derived.fd_lab   lb ON lb.stay_id = ie.stay_id
LEFT JOIN mimiciv_derived.fd_chart ce ON ce.stay_id = ie.stay_id
LEFT JOIN mimiciv_derived.fd_uo    uo ON uo.stay_id = ie.stay_id
LEFT JOIN mimiciv_derived.fd_vp    vp ON vp.stay_id = ie.stay_id
LEFT JOIN (SELECT DISTINCT v.stay_id FROM mimiciv_derived.ventilation v
           JOIN mimiciv_icu.icustays s ON s.stay_id = v.stay_id
           WHERE v.ventilation_status IN ('InvasiveVent','Tracheostomy')
             AND v.starttime <= s.intime + INTERVAL 1 DAY) v
  ON v.stay_id = ie.stay_id")

  step("SOFA scoring", "
CREATE OR REPLACE VIEW mimiciv_derived.first_day_sofa AS
WITH s AS (SELECT stay_id, vent_day1,
  CASE WHEN pao2_min IS NULL OR fio2_max IS NULL THEN 0
       WHEN pao2_min/(fio2_max/100.0) < 100 AND vent_day1=1 THEN 4
       WHEN pao2_min/(fio2_max/100.0) < 200 AND vent_day1=1 THEN 3
       WHEN pao2_min/(fio2_max/100.0) < 300 THEN 2
       WHEN pao2_min/(fio2_max/100.0) < 400 THEN 1 ELSE 0 END AS respiration,
  CASE WHEN platelet_min < 20 THEN 4 WHEN platelet_min < 50 THEN 3
       WHEN platelet_min < 100 THEN 2 WHEN platelet_min < 150 THEN 1
       ELSE 0 END AS coagulation,
  CASE WHEN bilirubin_max >= 12 THEN 4 WHEN bilirubin_max >= 6 THEN 3
       WHEN bilirubin_max >= 2 THEN 2 WHEN bilirubin_max >= 1.2 THEN 1
       ELSE 0 END AS liver,
  CASE WHEN norepi > 0.1 OR epi > 0.1 OR dopa > 15 THEN 4
       WHEN norepi > 0 OR epi > 0 OR dopa > 5 THEN 3
       WHEN dopa > 0 OR dobu > 0 THEN 2
       WHEN map_min < 70 THEN 1 ELSE 0 END AS cardiovascular,
  CASE WHEN gcs_min < 6 THEN 4 WHEN gcs_min < 10 THEN 3
       WHEN gcs_min < 13 THEN 2 WHEN gcs_min < 15 THEN 1 ELSE 0 END AS cns,
  CASE WHEN creatinine_max >= 5 OR urineoutput < 200 THEN 4
       WHEN creatinine_max >= 3.5 OR urineoutput < 500 THEN 3
       WHEN creatinine_max >= 2 THEN 2 WHEN creatinine_max >= 1.2 THEN 1
       ELSE 0 END AS renal
FROM mimiciv_derived.fd_components)
SELECT stay_id, vent_day1, respiration, coagulation, liver, cardiovascular,
       cns, renal,
       respiration+coagulation+liver+cardiovascular+cns+renal AS sofa
FROM s")

  print(dbGetQuery(con, "SELECT COUNT(*) n_stays, ROUND(AVG(sofa),2) mean_sofa,
                                ROUND(AVG(vent_day1),3) prop_ventilated
                         FROM mimiciv_derived.first_day_sofa"))
  invisible(NULL)
}

## ---------------------------------------------------------------------------
## 3. EXTRACT EXPANDED COVARIATES
## ---------------------------------------------------------------------------

extract_eicu <- function() {
  con <- duck_connect(DB, read_only = TRUE); on.exit(dbDisconnect(con, shutdown = TRUE))

  pat <- as.data.table(dbGetQuery(con, "
    SELECT patientunitstayid, hospitalid, age AS age_raw, gender,
           admissionweight, unittype, apacheadmissiondx, hospitaladmitsource
    FROM patient"))
  # '> 89' is a de-identification string, not a missing value.
  pat[, age := fifelse(age_raw == "> 89", 90, suppressWarnings(as.numeric(age_raw)))]
  pat[, female := as.integer(gender == "Female")]
  pat[, weight_kg := as.numeric(admissionweight)]
  pat[weight_kg < 25 | weight_kg > 300, weight_kg := NA_real_]

  apr <- as.data.table(dbGetQuery(con, "
    SELECT patientunitstayid, apachescore AS severity_score,
           predictedhospitalmortality AS severity_pred_mort
    FROM apachePatientResult WHERE apacheversion = 'IVa'"))
  apr[, severity_pred_mort := suppressWarnings(as.numeric(severity_pred_mort))]
  apr[severity_pred_mort < 0, severity_pred_mort := NA_real_]
  apr[severity_score < 0, severity_score := NA_real_]
  apr <- apr[, lapply(.SD, function(x) if (all(is.na(x))) NA_real_ else max(x, na.rm = TRUE)),
             by = patientunitstayid]

  apv <- as.data.table(dbGetQuery(con, "
    SELECT patientunitstayid, ventday1, cirrhosis, immunosuppression, leukemia,
           lymphoma, aids, hepaticfailure, diabetes FROM apachePredVar"))
  nc <- setdiff(names(apv), "patientunitstayid")
  apv[, (nc) := lapply(.SD, function(x) { x <- suppressWarnings(as.numeric(x))
                                          x[x < 0] <- NA_real_; x }), .SDcols = nc]
  apv[, vent_day1 := as.integer(ventday1 == 1)]
  apv[, chronic_liver := as.integer(cirrhosis == 1 | hepaticfailure == 1)]
  apv[, immunosuppressed := as.integer(immunosuppression == 1 | leukemia == 1 |
                                         lymphoma == 1 | aids == 1)]
  apv[, comorb_index := rowSums(.SD, na.rm = TRUE),
      .SDcols = c("cirrhosis","immunosuppression","leukemia","lymphoma",
                  "aids","hepaticfailure","diabetes")]

  dx <- as.data.table(dbGetQuery(con,
    "SELECT patientunitstayid, lower(diagnosisstring) AS dx FROM diagnosis"))
  dx[, chronic_hf := as.integer(grepl("chronic heart failure|cardiomyopathy|congestive heart failure", dx))]
  dx[, chronic_resp := as.integer(grepl("chronic obstructive|copd|interstitial lung|pulmonary fibrosis", dx))]
  dx[, chronic_renal := as.integer(grepl("chronic kidney|chronic renal|end-stage renal|dialysis", dx))]
  dx <- dx[, lapply(.SD, max), by = patientunitstayid,
           .SDcols = c("chronic_hf","chronic_resp","chronic_renal")]

  cs <- as.data.table(dbGetQuery(con, "
    SELECT DISTINCT patientunitstayid, 1 AS cs_treatment FROM treatment
    WHERE lower(treatmentstring) LIKE '%cabg%'
       OR lower(treatmentstring) LIKE '%cardiac surgery%'
       OR lower(treatmentstring) LIKE '%valve replacement%'
       OR lower(treatmentstring) LIKE '%post-op cardiac%'"))

  pat[, admit_dx_l := tolower(fcoalesce(apacheadmissiondx, ""))]
  pat[, unit_l := tolower(fcoalesce(unittype, ""))]
  pat[, admit_cardiac := as.integer(grepl(
    "cardio|cardiac|myocardial|chf|congestive|angina|valve|cabg|aortic", admit_dx_l))]
  pat[, unit_cardiac := as.integer(grepl("ctic|cardiac|ccu", unit_l))]
  pat[, admission_type_surgical := as.integer(grepl(
    "s/p|post-op|surgery|graft|repair|resection", admit_dx_l))]

  cov <- Reduce(function(x, y) merge(x, y, by = "patientunitstayid", all.x = TRUE),
                list(pat, apr, apv, dx, cs))
  cov[, post_cardiac_surgery := as.integer(
    fcoalesce(cs_treatment, 0L) == 1L |
      (unit_cardiac == 1L & admission_type_surgical == 1L) |
      grepl("cabg|valve|s/p cardiac", admit_dx_l))]

  bin <- c("chronic_hf","chronic_resp","chronic_renal","chronic_liver",
           "immunosuppressed","vent_day1","post_cardiac_surgery",
           "admit_cardiac","unit_cardiac","admission_type_surgical")
  cov[, (bin) := lapply(.SD, function(x) fifelse(is.na(x), 0L, as.integer(x))),
      .SDcols = bin]

  keep <- c("patientunitstayid", "hospitalid", BLOCKS$B, BLOCKS$A, BLOCKS$C, BLOCKS$D)
  cov <- cov[, intersect(keep, names(cov)), with = FALSE]
  saveRDS(cov, file.path(INTERMEDIATE, "eicu_cov.rds"))
  cat("eICU covariates:", nrow(cov), "stays,", ncol(cov) - 2, "variables\n")
  invisible(cov)
}

extract_mimic <- function() {
  con <- duck_connect(DB, read_only = TRUE); on.exit(dbDisconnect(con, shutdown = TRUE))

  demo <- as.data.table(dbGetQuery(con, "
    SELECT ie.stay_id, ie.hadm_id, p.anchor_age AS age, p.gender,
           a.admission_type, a.admission_location
    FROM mimiciv_icu.icustays ie
    JOIN mimiciv_hosp.patients p   ON p.subject_id = ie.subject_id
    JOIN mimiciv_hosp.admissions a ON a.hadm_id = ie.hadm_id"))
  demo[, female := as.integer(gender == "F")]
  demo[, admission_type_surgical := as.integer(grepl("SURGICAL|ELECTIVE",
                                    fcoalesce(admission_type, "")))]
  demo[, admit_cardiac := as.integer(grepl("CARDIAC|CORONARY",
                                    fcoalesce(admission_location, "")))]

  wt <- as.data.table(dbGetQuery(con,
    "SELECT stay_id, weight AS weight_kg FROM mimiciv_derived.weight_durations"))

  sofa <- as.data.table(dbGetQuery(con, "
    SELECT stay_id, sofa AS severity_score, vent_day1,
           respiration, coagulation, liver, cardiovascular, cns, renal
    FROM mimiciv_derived.first_day_sofa"))
  # OASIS could not be reconstructed; no predicted-mortality term is available
  # for MIMIC-IV. The column is created empty and dropped by prep_covariates.
  sofa[, severity_pred_mort := NA_real_]

  ch <- as.data.table(dbGetQuery(con, "
    SELECT hadm_id, charlson_comorbidity_index AS comorb_index,
           congestive_heart_failure AS chronic_hf,
           chronic_pulmonary_disease AS chronic_resp,
           renal_disease AS chronic_renal,
           CASE WHEN mild_liver_disease = 1 OR severe_liver_disease = 1
                THEN 1 ELSE 0 END AS chronic_liver,
           CASE WHEN malignant_cancer = 1 OR metastatic_solid_tumor = 1
                     OR aids = 1 THEN 1 ELSE 0 END AS immunosuppressed
    FROM mimiciv_derived.charlson"))

  srv <- as.data.table(dbGetQuery(con, "
    SELECT hadm_id, MAX(CASE WHEN curr_service = 'CSURG' THEN 1 ELSE 0 END) AS csurg
    FROM mimiciv_hosp.services GROUP BY hadm_id"))

  cov <- Reduce(function(x, y) merge(x, y, by = intersect(names(x), names(y)),
                                     all.x = TRUE),
                list(demo, wt, sofa, srv, ch))
  cov[, post_cardiac_surgery := as.integer(fcoalesce(csurg, 0L) == 1L)]
  # unit_cardiac is deliberately NOT constructed here. Defined as
  # (surgical service AND CSURG) it is identical to post_cardiac_surgery in
  # every MIMIC-IV stay, so including both would place a duplicated column in
  # the propensity model. eICU retains the variable, where the two differ.

  bin <- c("vent_day1","chronic_hf","chronic_resp","chronic_renal",
           "chronic_liver","immunosuppressed","post_cardiac_surgery",
           "admit_cardiac","admission_type_surgical")
  cov[, (bin) := lapply(.SD, function(x) fifelse(is.na(x), 0L, as.integer(x))),
      .SDcols = bin]

  keep <- c("stay_id", BLOCKS$B, BLOCKS$A,
            setdiff(BLOCKS$C, "unit_cardiac"), BLOCKS$D)
  cov <- cov[, intersect(keep, names(cov)), with = FALSE]
  saveRDS(cov, file.path(INTERMEDIATE, "mimic_cov.rds"))
  cat("MIMIC-IV covariates:", nrow(cov), "stays,", ncol(cov) - 1, "variables\n")
  invisible(cov)
}

## ---------------------------------------------------------------------------
## 4. ASSEMBLE ANALYSIS COHORTS
##    Inputs are the parent-cohort extracts: a primary-cohort file with the
##    treatment strategy and hemodynamic phenotype, and an outcome file.
## ---------------------------------------------------------------------------

build_cohorts <- function(files = list(
    eicu_cohort  = "05e_eICU_primary_cohort.csv",
    eicu_outcome = "09_eICU_outcomes.csv",
    mimic_cohort = "07e_MIMICIV_primary_cohort.csv",
    mimic_outcome = "11_MIMICIV_outcomes.csv")) {

  one <- function(coh_f, out_f, id_out) {
    co <- fread(file.path(PROJ_ROOT, coh_f))
    ou <- fread(file.path(PROJ_ROOT, out_f))
    drop <- intersect(c("initial_strategy", "arm_role"), names(ou))
    d <- merge(co, ou[, .SD, .SDcols = setdiff(names(ou), drop)], by = "stay_id")

    s <- tolower(d$initial_strategy)
    d[, drug_group := fcase(
        grepl("milrin", s),                                "milrinone",
        grepl("dobut", s),                                 "dobutamine",
        grepl("nitroprus|snp", s),                         "nitroprusside",
        grepl("inhal|nitric|epoprost|treprost|ilopro", s), "inhaled",
        grepl("combin|multi", s),                          "combination",
        default = NA_character_)]

    d[, hosp_mortality := as.integer(hospital_mortality)]
    d[, cvp := CVP][, mpap := PAP_mean][, papi := PAPi]
    d[, cvp_pcwp_ratio := fifelse(PAOP_PCWP > 0, CVP / PAOP_PCWP, NA_real_)]
    d[, lactate_or_vasopressor := as.integer(crit_lactate_or_vasopressor)]
    d[, qualifying_dx := as.integer(crit_diagnosis)]
    d[, phenotype_n  := as.integer(n_criteria_met)]
    setnames(d, "stay_id", id_out)
    d[]
  }

  e <- one(files$eicu_cohort,  files$eicu_outcome,  "patientunitstayid")
  m <- one(files$mimic_cohort, files$mimic_outcome, "stay_id")
  saveRDS(e, file.path(INTERMEDIATE, "eicu_cohort.rds"))
  saveRDS(m, file.path(INTERMEDIATE, "mimic_cohort.rds"))
  cat("Cohorts:", nrow(e), "eICU |", nrow(m), "MIMIC-IV\n")
  invisible(list(eicu = e, mimic = m))
}

## ---------------------------------------------------------------------------
## 5. ANALYSIS FUNCTIONS
## ---------------------------------------------------------------------------

# Non-finite and implausible values. PAPi = (PAPs - PAPd) / CVP diverges when
# CVP is recorded as zero; the parent extract contained Inf and negative values.
clean_cohort <- function(d) {
  num <- names(d)[vapply(d, is.numeric, logical(1))]
  for (v in num) set(d, which(!is.finite(d[[v]])), v, NA_real_)
  if ("papi" %in% names(d))           d[papi <= 0 | papi > 20, papi := NA_real_]
  if ("cardiac_index" %in% names(d))  d[cardiac_index <= 0 | cardiac_index > 10,
                                        cardiac_index := NA_real_]
  if ("cvp" %in% names(d))            d[cvp < 0 | cvp > 50, cvp := NA_real_]
  if ("mpap" %in% names(d))           d[mpap <= 0 | mpap > 90, mpap := NA_real_]
  if ("cvp_pcwp_ratio" %in% names(d)) d[cvp_pcwp_ratio <= 0 | cvp_pcwp_ratio > 10,
                                        cvp_pcwp_ratio := NA_real_]
  d[]
}

# Median imputation with a missingness indicator; drops covariates that are
# entirely missing, constant, or non-numeric. isTRUE() is required because
# var() returns NA on vectors with missing values and an NA logical index
# would place an NA name in the model formula.
prep_covariates <- function(dt, covs) {
  dt <- copy(dt)
  covs <- unique(intersect(covs[!is.na(covs) & nzchar(covs)], names(dt)))
  covs <- covs[vapply(covs, function(v) !all(is.na(dt[[v]])), logical(1))]
  for (v in covs) {
    x <- dt[[v]]
    if (!is.numeric(x)) x <- as.numeric(as.factor(x))
    x[!is.finite(x)] <- NA_real_
    if (anyNA(x)) {
      dt[[paste0("miss_", v)]] <- as.integer(is.na(x))
      med <- median(x, na.rm = TRUE)
      if (is.finite(med)) x[is.na(x)] <- med
    }
    dt[[v]] <- x
  }
  cand <- unique(c(covs, grep("^miss_", names(dt), value = TRUE)))
  cand <- cand[!is.na(cand) & nzchar(cand)]
  keep <- vapply(cand, function(v) {
    x <- dt[[v]]
    isTRUE(is.numeric(x) && !anyNA(x) && all(is.finite(x)) && stats::var(x) > 0)
  }, logical(1))
  final <- cand[keep]
  if (!length(final)) stop("No usable covariates.")
  list(data = dt, covs = final)
}

fit_overlap <- function(dt, treat, covs, trim = CFG$ps_trim) {
  covs <- unique(covs[!is.na(covs) & nzchar(covs) & covs %in% names(dt)])
  if (!length(covs)) stop("No valid covariates for the propensity model.")
  m  <- glm(reformulate(covs, response = treat), data = dt, family = binomial())
  ps <- pmin(pmax(predict(m, type = "response"), trim[1]), trim[2])
  list(ps = ps, w = ifelse(dt[[treat]] == 1, 1 - ps, ps), model = m, covs = covs)
}

smd_weighted <- function(dt, treat, covs, w) {
  t_idx <- dt[[treat]] == 1
  vapply(covs, function(v) {
    x <- dt[[v]]
    m1 <- weighted.mean(x[t_idx], w[t_idx]); m0 <- weighted.mean(x[!t_idx], w[!t_idx])
    v1 <- sum(w[t_idx] * (x[t_idx] - m1)^2) / sum(w[t_idx])
    v0 <- sum(w[!t_idx] * (x[!t_idx] - m0)^2) / sum(w[!t_idx])
    sp <- sqrt((v1 + v0) / 2)
    if (!isTRUE(is.finite(sp) && sp > 0)) return(0)
    (m1 - m0) / sp
  }, numeric(1))
}

# Weighted risk difference with a cluster bootstrap. cluster names the
# resampling unit in eICU (hospital); NULL resamples individual stays.
weighted_rd <- function(dt, treat, outcome, covs, cluster = NULL,
                        n_boot = CFG$n_boot, trim = CFG$ps_trim) {
  point <- function(d) {
    d <- d[!is.na(d[[outcome]])]
    fit <- fit_overlap(d, treat, covs, trim = trim)
    w <- fit$w; t_idx <- d[[treat]] == 1
    r1 <- weighted.mean(d[[outcome]][t_idx],  w[t_idx],  na.rm = TRUE)
    r0 <- weighted.mean(d[[outcome]][!t_idx], w[!t_idx], na.rm = TRUE)
    c(rd = r1 - r0, r1 = r1, r0 = r0)
  }
  est <- point(dt)
  boots <- matrix(NA_real_, n_boot, 3)
  for (b in seq_len(n_boot)) {
    d_b <- if (is.null(cluster)) dt[sample(.N, .N, TRUE)] else {
      cl <- unique(dt[[cluster]])
      rbindlist(lapply(sample(cl, length(cl), TRUE),
                       function(h) dt[get(cluster) == h]))
    }
    boots[b, ] <- tryCatch(point(d_b), error = function(e) rep(NA_real_, 3))
  }
  ci <- quantile(boots[, 1], c(.025, .975), na.rm = TRUE)
  data.table(rd = est["rd"] * 100, rd_lo = ci[1] * 100, rd_hi = ci[2] * 100,
             risk_treat = est["r1"], risk_ctrl = est["r0"],
             n_boot_ok = sum(!is.na(boots[, 1])))
}

evalue_rr <- function(rr) { rr <- ifelse(rr < 1, 1 / rr, rr); rr + sqrt(rr * (rr - 1)) }

evalue_from_rd <- function(rd, lo, hi, risk_ctrl) {
  na <- data.table(rr_approx = NA_real_, evalue_point = NA_real_, evalue_ci = NA_real_)
  if (!isTRUE(is.finite(risk_ctrl) && risk_ctrl > 0) || !isTRUE(is.finite(rd)))
    return(na)
  rr <- (risk_ctrl + rd / 100) / risk_ctrl
  if (!isTRUE(is.finite(rr)) || rr <= 0) return(na)
  bound <- if (rr < 1) (risk_ctrl + hi / 100) / risk_ctrl else
                       (risk_ctrl + lo / 100) / risk_ctrl
  ev_ci <- if (!isTRUE(is.finite(bound)) || bound <= 0) NA_real_
           else if ((rr < 1 && bound >= 1) || (rr > 1 && bound <= 1)) 1
           else evalue_rr(bound)
  data.table(rr_approx = rr, evalue_point = evalue_rr(rr), evalue_ci = ev_ci)
}

# Decision rule (analysis plan, Section 4). Attenuation is measured against the
# M0 estimate of the reported trajectory.
apply_decision_rule <- function(inc) {
  g <- function(db, m) inc[database == db & model == m]
  att <- c(eicu  = 1 - abs(g("eICU","M4")$rd)     / abs(g("eICU","M0")$rd),
           mimic = 1 - abs(g("MIMIC-IV","M4")$rd) / abs(g("MIMIC-IV","M0")$rd))
  m4 <- inc[model == "M4"]
  crosses <- m4$rd_lo <= 0 & m4$rd_hi >= 0
  flip <- sign(g("eICU","M4")$rd) != sign(g("eICU","M0")$rd) ||
          sign(g("MIMIC-IV","M4")$rd) != sign(g("MIMIC-IV","M0")$rd)
  ev_min <- min(m4$evalue_ci, na.rm = TRUE)

  decision <- if (flip) {
    "OUTCOME 4 - direction reversed; no directional conclusion."
  } else if (any(att >= ATTENUATION_THRESHOLD) || any(crosses)) {
    paste("OUTCOME 1 - substantial attenuation or a confidence interval",
          "including the null. The original association is attributable in",
          "large part to confounding by severity and admission context.")
  } else if (ev_min < EVALUE_THRESHOLD) {
    paste0("OUTCOME 2 - association persists but the confidence-limit E-value ",
           "is below ", EVALUE_THRESHOLD, "; explainable by plausible ",
           "unmeasured confounding. No claim of superiority.")
  } else {
    "OUTCOME 3 - association persists and is robust; falsification analyses required."
  }
  list(attenuation = round(att, 3), crosses_null = crosses,
       evalue_min = round(ev_min, 2), decision = decision)
}

## ---------------------------------------------------------------------------
## 6. NITROPRUSSIDE FEASIBILITY GATE
##    Runs before any outcome model. The only outcome quantity computed is the
##    death count required by the prespecified threshold.
## ---------------------------------------------------------------------------

nitroprusside_feasibility <- function(eicu, mimic) {
  R <- NTP_RESTRICTION; F <- NTP_FEASIBILITY
  req <- c("mpap", "cardiac_index", "crit_vasopressor")

  flow_one <- function(dt, label) {
    miss <- setdiff(req, names(dt))
    if (length(miss)) stop("Missing columns in ", label, ": ",
                           paste(miss, collapse = ", "))
    d <- dt[drug_group %in% c("nitroprusside", "milrinone", "dobutamine")]
    d[, treat := as.integer(drug_group == "nitroprusside")]
    steps <- data.table(database = label, step = c(
      "All initiators", "R1: PA catheter in situ (mPAP measured)",
      "R2: mPAP > 25 mm Hg", "R3: Cardiac index 1.8-2.5 L/min/m2",
      "R4: No baseline vasopressor"), n_ntp = NA_integer_, n_ino = NA_integer_)
    cur <- copy(d)
    rec <- function(i) steps[i, `:=`(n_ntp = sum(cur$treat == 1),
                                     n_ino = sum(cur$treat == 0))]
    rec(1)
    cur <- cur[!is.na(mpap)];                          rec(2)
    cur <- cur[mpap > R$mpap_min];                     rec(3)
    cur <- cur[!is.na(cardiac_index) &
                 cardiac_index >= R$ci_min & cardiac_index <= R$ci_max]; rec(4)
    cur <- cur[fcoalesce(as.integer(crit_vasopressor), 0L) == 0L];       rec(5)
    list(flow = steps, cohort = cur)
  }

  fe <- flow_one(eicu, "eICU"); fm <- flow_one(mimic, "MIMIC-IV")
  flow <- rbind(fe$flow, fm$flow)
  print(flow)
  fwrite(flow, file.path(OUT, "ntp_restriction_flow.csv"))

  support <- function(coh) {
    if (nrow(coh) < 40 || length(unique(coh$treat)) < 2) return(NA_real_)
    p <- prep_covariates(coh, MODELS[[PRIMARY_MODEL]])
    ps <- fit_overlap(p$data, "treat", p$covs)$ps
    t1 <- ps[p$data$treat == 1]; t0 <- ps[p$data$treat == 0]
    mean(ps < max(min(t1), min(t0)) | ps > min(max(t1), max(t0)))
  }
  assess <- function(f, label) {
    coh <- f$cohort; n1 <- sum(coh$treat == 1); n0 <- sum(coh$treat == 0)
    ev <- if (n1 == 0 || n0 == 0) 0 else
      sum(coh[treat == (if (n1 <= n0) 1 else 0)][["hosp_mortality"]], na.rm = TRUE)
    off <- support(coh)
    data.table(database = label, n_ntp = n1, n_ino = n0, deaths_smaller_arm = ev,
               off_support = round(off, 3),
               feasible = n1 >= F$min_n_per_arm && n0 >= F$min_n_per_arm &&
                          ev >= F$min_events_small &&
                          isTRUE(off < F$max_off_support))
  }
  feas <- rbind(assess(fe, "eICU"), assess(fm, "MIMIC-IV"))
  print(feas); fwrite(feas, file.path(OUT, "ntp_feasibility.csv"))

  verdict <- if (any(feas$feasible))
    "FEASIBLE - the contrast may be analysed as a prespecified secondary comparison." else
    paste("NOT FEASIBLE - the contrast is descriptive only. Positivity fails:",
          "the two treatments are not used in overlapping clinical states.")
  cat("\n", verdict, "\n", sep = "")
  writeLines(c(verdict, "", capture.output(print(flow)), "",
               capture.output(print(feas))),
             file.path(OUT, "nitroprusside_decision.txt"))
  invisible(feas)
}

## ---------------------------------------------------------------------------
## 7. PRIMARY ANALYSIS
## ---------------------------------------------------------------------------

prep_arm <- function(dt) {
  d <- dt[drug_group %in% c("milrinone", "dobutamine")]
  d[, treat := as.integer(drug_group == "milrinone")]
  d[!is.na(hosp_mortality)]
}

run_incremental <- function(dt, db_label, cluster = NULL) {
  rbindlist(lapply(names(MODELS), function(mn) {
    p <- prep_covariates(dt, MODELS[[mn]])
    r <- weighted_rd(p$data, "treat", "hosp_mortality", p$covs, cluster = cluster)
    cbind(database = db_label, model = mn, n_cov = length(p$covs), r,
          evalue_from_rd(r$rd, r$rd_lo, r$rd_hi, r$risk_ctrl))
  }))
}

balance_report <- function(dt, db_label) {
  p <- prep_covariates(dt, MODELS[[PRIMARY_MODEL]])
  w <- fit_overlap(p$data, "treat", p$covs)$w
  data.table(database = db_label, covariate = p$covs,
             smd_pre  = smd_weighted(p$data, "treat", p$covs, rep(1, nrow(p$data))),
             smd_post = smd_weighted(p$data, "treat", p$covs, w))
}

run_sensitivity <- function(eicu_a, mimic_a) {
  one <- function(dt, label, db, cluster = NULL, trim = CFG$ps_trim) {
    if (nrow(dt) < 100 || length(unique(dt$treat)) < 2)
      return(data.table(scenario = label, database = db, n = nrow(dt),
                        rd = NA_real_, rd_lo = NA_real_, rd_hi = NA_real_))
    p <- prep_covariates(dt, MODELS[[PRIMARY_MODEL]])
    r <- weighted_rd(p$data, "treat", "hosp_mortality", p$covs,
                     cluster = cluster, trim = trim)
    data.table(scenario = label, database = db, n = nrow(dt),
               rd = r$rd, rd_lo = r$rd_lo, rd_hi = r$rd_hi)
  }
  vol <- eicu_a[, .(n1 = sum(treat), n0 = sum(1 - treat)), by = hospitalid]
  keep_h <- vol[n1 >= 20 & n0 >= 20, hospitalid]

  rbindlist(list(
    one(eicu_a,  "Fully adjusted model (reference)", "eICU", "hospitalid"),
    one(eicu_a[chronic_hf == 0], "Excluding advanced chronic heart failure",
        "eICU", "hospitalid"),
    one(eicu_a[phenotype_n >= 2], "Phenotype-positive only", "eICU", "hospitalid"),
    one(eicu_a,  "Propensity score truncated at 0.05-0.95", "eICU", "hospitalid",
        trim = c(0.05, 0.95)),
    one(eicu_a[hospitalid %in% keep_h], "Hospitals with >=20 per arm",
        "eICU", "hospitalid"),
    one(mimic_a, "Fully adjusted model (reference)", "MIMIC-IV"),
    one(mimic_a[chronic_hf == 0], "Excluding advanced chronic heart failure",
        "MIMIC-IV"),
    one(mimic_a[phenotype_n >= 2], "Phenotype-positive only", "MIMIC-IV"),
    one(mimic_a, "Propensity score truncated at 0.05-0.95", "MIMIC-IV",
        trim = c(0.05, 0.95))), fill = TRUE)
}

## ---------------------------------------------------------------------------
## 8. MAIN
## ---------------------------------------------------------------------------

main <- function() {
  t0 <- Sys.time()

  cat("\n[1/6] Attaching source tables\n");        attach_views()
  cat("\n[2/6] Building MIMIC-IV derived concepts\n"); build_mimic_derived()
  cat("\n[3/6] Extracting covariates\n");          extract_eicu(); extract_mimic()
  cat("\n[4/6] Assembling cohorts\n");             build_cohorts()

  eicu  <- merge(readRDS(file.path(INTERMEDIATE, "eicu_cohort.rds")),
                 readRDS(file.path(INTERMEDIATE, "eicu_cov.rds")), by = "patientunitstayid")
  mimic <- merge(readRDS(file.path(INTERMEDIATE, "mimic_cohort.rds")),
                 readRDS(file.path(INTERMEDIATE, "mimic_cov.rds")), by = "stay_id")
  # Drop duplicate source-cased columns retained from the parent extract.
  drop_source_duplicates <- function(d) {
    dup <- intersect(c("CVP","PAPi","PAP_mean","PAP_systolic","PAP_diastolic"),
                     names(d))
    if (length(dup)) d[, (dup) := NULL]
    d
  }
  eicu <- drop_source_duplicates(eicu)
  mimic <- drop_source_duplicates(mimic)
  eicu <- clean_cohort(eicu); mimic <- clean_cohort(mimic)

  cat("\n[5/6] Nitroprusside feasibility gate\n")
  nitroprusside_feasibility(eicu, mimic)

  cat("\n[6/6] Primary analysis\n")
  eicu_a <- prep_arm(eicu); mimic_a <- prep_arm(mimic)
  cat("  eICU :", nrow(eicu_a), "stays,", sum(eicu_a$treat), "milrinone\n")
  cat("  MIMIC:", nrow(mimic_a), "stays,", sum(mimic_a$treat), "milrinone\n")

  incremental <- rbind(run_incremental(eicu_a,  "eICU", "hospitalid"),
                       run_incremental(mimic_a, "MIMIC-IV", NULL))
  print(incremental[, .(database, model, n_cov, rd = round(rd, 1),
                        ci = sprintf("%.1f to %.1f", rd_lo, rd_hi),
                        evalue_ci = round(evalue_ci, 2))])
  fwrite(incremental, file.path(OUT, "incremental_M0_M4.csv"))

  bal <- rbind(balance_report(eicu_a, "eICU"), balance_report(mimic_a, "MIMIC-IV"))
  fwrite(bal, file.path(OUT, "balance_M4.csv"))

  # Complementary hierarchical model with a hospital random intercept (eICU).
  pe <- prep_covariates(eicu_a, MODELS[[PRIMARY_MODEL]])
  mh <- try(glmer(reformulate(c(pe$covs, "(1 | hospitalid)"),
                              response = "hosp_mortality"),
                  data = cbind(pe$data, treat = eicu_a$treat),
                  family = binomial(),
                  control = glmerControl(optimizer = "bobyqa",
                                         optCtrl = list(maxfun = 2e5))),
            silent = TRUE)
  if (!inherits(mh, "try-error")) capture.output(print(summary(mh)$coefficients),
    file = file.path(OUT, "hierarchical_eicu.txt"))

  decision <- apply_decision_rule(incremental)
  cat("\n=========== DECISION RULE ===========\n"); print(decision)
  writeLines(c("PRESPECIFIED DECISION RULE",
    paste("Attenuation vs M0:", paste(names(decision$attenuation),
                                      decision$attenuation, collapse = "; ")),
    paste("Minimum confidence-limit E-value:", decision$evalue_min), "",
    decision$decision), file.path(OUT, "decision.txt"))

  sens <- run_sensitivity(eicu_a, mimic_a)
  print(sens[, .(database, scenario, n, rd = round(rd, 1))])
  fwrite(sens, file.path(OUT, "sensitivity.csv"))

  saveRDS(list(incremental = incremental, balance = bal, sensitivity = sens,
               decision = decision), file.path(INTERMEDIATE, "main_results.rds"))

  writeLines(capture.output(sessionInfo()), file.path(OUT, "session_info.txt"))

  cat("\nDone in", round(difftime(Sys.time(), t0, units = "min"), 1), "min.\n")
  cat("Outputs in", normalizePath(OUT), "\n")
  invisible(NULL)
}

if (sys.nframe() == 0L) main()
