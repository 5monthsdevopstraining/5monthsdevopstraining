#!/usr/bin/env bash
set -euo pipefail

apt-get update -qq && apt-get install -y -qq --no-install-recommends default-jre-headless >/dev/null
dotnet tool install --global dotnet-sonarscanner --version 9.0.2 >/dev/null 2>&1 || dotnet tool install --global dotnet-sonarscanner >/dev/null 2>&1
export PATH="$PATH:/root/.dotnet/tools"

rm -rf ./TestResults

AUTH_ARG="/d:sonar.login=${SONAR_TOKEN}"
if [ -n "${SONAR_PASSWORD:-}" ]; then
  AUTH_ARG="/d:sonar.login=admin /d:sonar.password=${SONAR_PASSWORD}"
fi

dotnet sonarscanner begin \
  /k:"dotnet-app" \
  /n:"dotnet-app" \
  /v:"build-${BUILD_NUMBER}" \
  /d:sonar.host.url="${SONARQUBE_URL}" \
  /d:sonar.scanner.scanAll=false \
  /d:sonar.cs.opencover.reportsPaths="**/coverage.opencover.xml" \
  ${AUTH_ARG}

dotnet test tests/dotnet.Tests/dotnet.Tests.csproj \
  --configuration Release \
  --collect:"XPlat Code Coverage" \
  --results-directory ./TestResults \
  -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=opencover

echo "Generated OpenCover reports:"
find ./TestResults -name "coverage.opencover.xml"

dotnet sonarscanner end ${AUTH_ARG}
