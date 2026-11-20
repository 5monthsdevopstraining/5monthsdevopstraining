# ---------- Stage 1: build ----------
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy only the project file first so package restore is cached
COPY dotnet.csproj .
RUN dotnet restore

# Copy the rest of the code and publish
COPY . .
RUN dotnet publish dotnet.csproj -c Release -o /app/publish --no-restore /p:UseAppHost=false

# ---------- Stage 2: run ----------
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

ENV ASPNETCORE_HTTP_PORTS=8080
EXPOSE 8080

COPY --from=build /app/publish .

# Run as a non-root user (provided by the official image)
USER $APP_UID

ENTRYPOINT ["dotnet", "dotnet.dll"]
