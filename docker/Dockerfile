# syntax=docker/dockerfile:1
# Build from the repository root:
#   docker build -f docker/Dockerfile -t dotnet-api:local .
#
# This image contains only the original .NET 10 application in dotnet/dotnet.csproj.

############################
# Stage 1: build
############################
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Restore before copying the rest of the source so dependency downloads stay cached.
COPY dotnet/dotnet.csproj dotnet/
RUN dotnet restore dotnet/dotnet.csproj

COPY dotnet/ dotnet/
RUN dotnet publish dotnet/dotnet.csproj \
      -c Release -o /app/publish --no-restore /p:UseAppHost=false

############################
# Stage 2: runtime
############################
FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS final
WORKDIR /app

# Official ASP.NET images listen on 8080. The application does not call UseUrls.
ENV ASPNETCORE_HTTP_PORTS=8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=true \
    DOTNET_EnableDiagnostics=0 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1

COPY --from=build /app/publish .

EXPOSE 8080

# Official .NET container images ship a non-root user named "app" (UID 1654).
USER app

ENTRYPOINT ["dotnet", "dotnet.dll"]
