#!/bin/bash

set -euo pipefail

function installTravisTools {
  mkdir ~/.local
  curl -sSL https://github.com/SonarSource/travis-utils/tarball/v27 | tar zx --strip-components 1 -C ~/.local
  source ~/.local/bin/install
}

function strongEcho {
  echo ""
  echo "================ $1 ================="
}

case "$TARGET" in

CI)
  if [ "$TRAVIS_BRANCH" == "master" ] && [ "$TRAVIS_PULL_REQUEST" == "false" ]; then
    strongEcho "Build and analyze commit in master"
    # this commit is master must be built and analyzed (with upload of report)
    mvn verify -B -e -V

    # integration of jacoco report is quite memory-consuming
    export MAVEN_OPTS="-Xmx1536m -Xms128m"
    git fetch --unshallow 
    mvn org.jacoco:jacoco-maven-plugin:prepare-agent verify -Pcoverage-per-test sonar:sonar -B -e -V \
       -Dsonar.host.url=$SONAR_HOST_URL \
       -Dsonar.login=$SONAR_TOKEN

  elif [ "$TRAVIS_PULL_REQUEST" != "false" ] && [ -n "${GITHUB_TOKEN-}" ]; then
    # For security reasons environment variables are not available on the pull requests
    # coming from outside repositories
    # http://docs.travis-ci.com/user/pull-requests/#Security-Restrictions-when-testing-Pull-Requests
    # That's why the analysis does not need to be executed if the variable GITHUB_TOKEN is not defined.
    strongEcho "Build and analyze pull request"
    mvn verify -B -e -V

    export MAVEN_OPTS="-Xmx1G -Xms128m"
    mvn verify sonar:sonar -B -e -V \
        -Dsonar.analysis.mode=issues \
        -Dsonar.github.pullRequest=$TRAVIS_PULL_REQUEST \
        -Dsonar.github.repository=$TRAVIS_REPO_SLUG \
        -Dsonar.github.oauth=$GITHUB_TOKEN \
        -Dsonar.host.url=$SONAR_HOST_URL \
        -Dsonar.login=$SONAR_TOKEN

  else
    strongEcho 'Build, no analysis'
    # Build branch, without any analysis

    # No need for Maven goal "install" as the generated JAR file does not need to be installed
    # in Maven local repository
    mvn verify -B -e -V
  fi
  ;;

IT)
  mvn package -B -e -V -DskipTests
  installTravisTools

  start_xvfb

  cd its
  mvn -Djenkins.runtimeVersion="$JENKINS_VERSION" -Dsonar.runtimeVersion="$SQ_VERSION" -Dmaven.test.redirectTestOutputToFile=false verify 
  ;;

*)
  echo "Unexpected TARGET value: $TARGET"
  exit 1
  ;;

esac
