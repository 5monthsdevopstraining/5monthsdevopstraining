
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src

ARG PROJECT_FILE=app/dotnet.csproj

COPY . .

RUN dotnet restore "$PROJECT_FILE"

RUN dotnet publish "$PROJECT_FILE" \
    --configuration Release \
    --output /app/publish \
    --no-restore \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime

WORKDIR /app

COPY --from=build /app/publish .

ARG APP_DLL=dotnet.dll
ENV APP_DLL=$APP_DLL

EXPOSE 8080

ENTRYPOINT ["sh", "-c", "exec dotnet \"$APP_DLL\""]

