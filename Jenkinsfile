// KijaniKiosk payments CI pipeline
// Lint -> Build -> Verify (Test || Security Audit) -> Archive -> Publish
// Every stage must pass before the next one runs; a failure stops the line.
pipeline {
    // One pinned image for every stage: the same Node and npm on every run and every machine.
    agent {
        docker {
            image 'node:22.23.3-alpine3.24'
        }
    }

    options {
        timeout(time: 10, unit: 'MINUTES')          // the 10-minute budget is enforced, not hoped for
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '30'))
    }

    // Everything the pipeline depends on is declared here. Nothing is inherited from the machine.
    environment {
        APP_DIR              = 'week5/friday/kijanikiosk-payments'
        NEXUS_URL            = 'http://172.17.0.1:8081'   // Docker bridge: localhost inside the agent is the container itself
        NEXUS_REPO           = 'npm-kijanikiosk'
        NEXUS_CREDENTIALS_ID = 'nexus-ci-publisher'        // an ID only; the secret lives in Jenkins' credential store
        npm_config_cache     = '/tmp/.npm'                  // the agent user has no writable HOME
        npm_config_fund      = 'false'
        npm_config_update_notifier = 'false'
        CI                   = 'true'
        // Set at run time, not here: ARTIFACT_VERSION and PACKAGE_NAME (Build stage), FAILED_STAGE (the stage that failed).
        // Values declared in this block are read-only for the whole run, so they cannot be declared here.
    }

    stages {
        stage('Lint') {
            steps {
                dir(env.APP_DIR) {
                    sh 'node --version && npm --version'
                    sh 'npm ci --no-audit'
                    sh 'npm run lint'
                }
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }   // each stage records its own failure: a shared
                                                                                // 'current stage' variable races between parallel branches
        }

        stage('Build') {
            steps {
                dir(env.APP_DIR) {
                    script {
                        // <semver>-<git-sha>: every artifact traces back to exactly one commit.
                        def base = sh(returnStdout: true, script: "node -p \"require('./package.json').version\"").trim()
                        def sha  = env.GIT_COMMIT.take(7)
                        if (sha ==~ /\d+/) { sha = "g${sha}" }   // an all-digit pre-release id with a leading 0 is not valid semver
                        env.ARTIFACT_VERSION = "${base}-${sha}"
                        env.PACKAGE_NAME = sh(returnStdout: true, script: "node -p \"require('./package.json').name\"").trim()
                    }
                    // Stamp the version first so the build output records exactly what it is.
                    sh 'npm version "$ARTIFACT_VERSION" --no-git-tag-version'
                    sh 'npm run build'
                    echo "Artifact version: ${env.PACKAGE_NAME}@${env.ARTIFACT_VERSION}"
                }
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }

        stage('Verify') {
            failFast true
            parallel {
                stage('Test') {
                    steps {
                        dir(env.APP_DIR) {
                            sh 'npm test'
                        }
                    }
                    post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
                }
                stage('Security Audit') {
                    steps {
                        dir(env.APP_DIR) {
                            // Only what ships to production, and only high/critical findings stop the line.
                            sh 'npm audit --omit=dev --audit-level=high'
                        }
                    }
                    post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
                }
            }
        }

        stage('Archive') {
            steps {
                dir(env.APP_DIR) {
                    sh 'npm pack'
                }
                // The fingerprint (MD5) lets anyone trace this exact tarball to this build and commit.
                archiveArtifacts artifacts: "${env.APP_DIR}/*.tgz", fingerprint: true, allowEmptyArchive: false
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }

        stage('Publish') {
            steps {
                dir(env.APP_DIR) {
                    withCredentials([usernamePassword(credentialsId: env.NEXUS_CREDENTIALS_ID,
                                                      usernameVariable: 'NEXUS_USER',
                                                      passwordVariable: 'NEXUS_PASS')]) {
                        // Single-quoted: Groovy never interpolates the secret; the shell reads it from the environment.
                        // .npmrc is created and deleted inside this one sh step; the trap removes it even if publish fails.
                        sh '''
                            set +x
                            trap 'rm -f .npmrc' EXIT
                            REGISTRY="${NEXUS_URL}/repository/${NEXUS_REPO}/"
                            AUTH=$(printf '%s:%s' "$NEXUS_USER" "$NEXUS_PASS" | base64 | tr -d '\\n')
                            printf '%s:_auth=%s\\n' "${REGISTRY#http:}" "$AUTH" > .npmrc
                            npm publish ./*.tgz --registry "$REGISTRY"
                        '''
                    }
                }
            }
            post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
        }
    }

    post {
        always {
            junit allowEmptyResults: true, testResults: "${env.APP_DIR}/reports/junit.xml"
            cleanWs()
        }
        success {
            echo "PUBLISHED ${env.PACKAGE_NAME}@${env.ARTIFACT_VERSION}"
            echo "Artifact URL: ${env.NEXUS_URL}/repository/${env.NEXUS_REPO}/${env.PACKAGE_NAME}/-/${env.PACKAGE_NAME}-${env.ARTIFACT_VERSION}.tgz"
        }
        failure {
            echo "NOTIFY team: ${env.JOB_NAME} #${env.BUILD_NUMBER} FAILED in stage '${env.FAILED_STAGE ?: 'Checkout'}' " +
                 "(commit ${env.GIT_COMMIT?.take(7)}). Nothing was published. Log: ${env.BUILD_URL}console"
        }
        changed {
            echo "STATUS CHANGE: ${env.JOB_NAME} went from ${currentBuild.previousBuild?.result ?: 'no previous run'} " +
                 "to ${currentBuild.currentResult} at #${env.BUILD_NUMBER}"
        }
    }
}
