#!/usr/bin/env bash
# Creates (or updates) the Jenkins pipeline job from jenkins/job-config.xml.
# Needs a Jenkins API token (Jenkins -> your name -> Security -> API Token):
#
#   JENKINS_USER=admin JENKINS_TOKEN=xxxx bash capstone/scripts/create-jenkins-job.sh
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
URL="${JENKINS_URL:-http://localhost:8080}"
JOB="${JOB_NAME:-kijanikiosk-capstone}"
: "${JENKINS_USER:?set JENKINS_USER}"; : "${JENKINS_TOKEN:?set JENKINS_TOKEN}"
AUTH=(-u "$JENKINS_USER:$JENKINS_TOKEN")

if curl -sf "${AUTH[@]}" "$URL/job/$JOB/config.xml" >/dev/null; then
  curl -sf "${AUTH[@]}" -X POST -H 'Content-Type: application/xml' --data-binary @"$ROOT/jenkins/job-config.xml" "$URL/job/$JOB/config.xml"
  echo "updated job $JOB"
else
  curl -sf "${AUTH[@]}" -X POST -H 'Content-Type: application/xml' --data-binary @"$ROOT/jenkins/job-config.xml" "$URL/createItem?name=$JOB"
  echo "created job $JOB"
fi
echo "$URL/job/$JOB/"
