#!/bin/bash

#SBATCH --job-name=srb             
#SBATCH --time=00:01:00            # format:HH:MM:SS
#SBATCH --mem=1M                   # options: K M G T,  add ~10% safety margin
#SBATCH --nodes=1                  
#SBATCH --ntasks-per-node=1        #  task(s) aka. process(es) 
#SBATCH --cpus-per-task=1          
#SBATCH --hint=nomultithread       
#SBATCH --output=jobs/%j/stdout.log   
#SBATCH --error=jobs/%j/stderror.log   
#SBATCH --mail-type=END            # options: END, FAIL, ALL

## --- required ---

export PROJECT_NAME="simreplicabim"   
export R_VERSION="4.4"                 

## --- global sanity checks ---

set -eEuo pipefail                 
                                  
## --- environment variables ---

export DATA_DIR="${SLURM_SUBMIT_DIR}/data"
export STAN_DIR="${SLURM_SUBMIT_DIR}/stan"
export JOB_DIR="${SLURM_SUBMIT_DIR}/jobs"   

export JOB_DIR_ID="${JOB_DIR}/${SLURM_JOB_ID}"      
export RESULT_DIR="${JOB_DIR_ID}/results"           
export SNAPSHOT_DIR="${JOB_DIR_ID}/snapshots"      

export NUM_THREADS=1    #threading policy
export STAN_NUM_THREADS="${NUM_THREADS}"
export OMP_NUM_THREADS="${NUM_THREADS}"
export MKL_NUM_THREADS="${NUM_THREADS}"
export OPENBLAS_NUM_THREADS="${NUM_THREADS}"
export NUMEXPR_NUM_THREADS="${NUM_THREADS}"

# ---job directory setup ---

mkdir -p "${JOB_DIR}" "${RESULT_DIR}" "${SNAPSHOT_DIR}"
cd "${JOB_DIR_ID}"

## --- reproducibility snapshots ---

env | sort > "${SNAPSHOT_DIR}/env.txt"

cp -f "${SLURM_SUBMIT_DIR}/${PROJECT_NAME}".* "${SNAPSHOT_DIR}/"

shopt -s nullglob   
cp -f "${STAN_DIR}"/*.stan "${SNAPSHOT_DIR}/"
shopt -u nullglob

## --- logging (start) ---

printf '%s\n' \
  "Project name: ${PROJECT_NAME}" \
  "Script: ${PROJECT_NAME}.sh" \
  "Start time: $(date '+%Y-%m-%d %H:%M:%S')" \
  "Job ID: ${SLURM_JOB_ID}" \
  "Job name: ${SLURM_JOB_NAME}" \
  "Node: ${SLURMD_NODENAME:-${SLURM_NODELIST}}" \
  "Partition: ${SLURM_JOB_PARTITION}" \
  ""

## --- modules ---

module purge
module load "R/${R_VERSION}"

## --- run ---

# test runs (without r)
djaksecho "hello world"; sleep 60000

# include the r script
#srun Rscript "${SLURM_SUBMIT_DIR}/${PROJECT_NAME}.R"

# --- logging (end) ---

printf '%s\n' \
  "" \
  "End time: $(date '+%Y-%m-%d %H:%M:%S')" \
  "Duration: ${SECONDS}"
