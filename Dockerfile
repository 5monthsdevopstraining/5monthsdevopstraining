# Build and run with the .NET 8 SDK/runtime images.
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

ARG PROJECT_FILE=dotnet-app.csproj
COPY . .
RUN dotnet restore "$PROJECT_FILE"
RUN dotnet publish "$PROJECT_FILE" --configuration Release --output /app/publish --no-restore /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

# Set APP_DLL to the assembly name from the project's <AssemblyName>, or its .csproj filename.
ARG APP_DLL=dotnet-app.dll
ENV APP_DLL=$APP_DLL
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "exec dotnet \"$APP_DLL\""]
