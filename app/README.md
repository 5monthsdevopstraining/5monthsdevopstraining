# S3 and PostgreSQL RDS Training API 

A small .NET 10 Web API for practicing Swagger, multipart file uploads to Amazon S3, and PostgreSQL connectivity checks against Amazon RDS.

## Requirements

- .NET 10 SDK
- An existing S3 bucket in the configured AWS region
- AWS credentials with `s3:PutObject` for that bucket and upload prefix
- An existing PostgreSQL RDS instance and its endpoint, database name, username, and password
- Network access from the computer running this API to the RDS endpoint

The application does not create or configure the S3 bucket or RDS instance. For a private RDS instance, run this API in a network that can reach the database and allow inbound PostgreSQL traffic on port 5432 from the API host or security group.

## Configuration

Defaults live in `appsettings.json`:

| Setting | Description |
| --- | --- |
| `AWS:Region` | AWS region for the S3 client (`ap-southeast-2` by default) |
| `S3:BucketName` | Existing S3 bucket name; replace the sample placeholder |
| `S3:KeyPrefix` | Object key prefix (`training-uploads` by default) |
| `ConnectionStrings:Rds` | PostgreSQL connection string; leave blank in the file and provide it securely at runtime |

ASP.NET Core maps double underscores in environment variable names to configuration sections. Set the bucket and connection string in PowerShell; do not commit database passwords to `appsettings.json`.

```powershell
$env:AWS_PROFILE = "aravindan"
$env:S3__BucketName = "your-existing-s3-bucket"
$env:ConnectionStrings__Rds = "Host=your-rds-endpoint;Port=5432;Database=your-database;Username=your-user;Password=your-password;SSL Mode=Require;Trust Server Certificate=true"
```

The AWS SDK uses the normal credential chain. The profile above is for local development; when deployed on EC2, use an instance role with the required S3 permission instead of storing AWS keys in the application.

## Run the API

From this directory:

```powershell
dotnet restore
dotnet run --urls http://localhost:5077
```

Open Swagger UI at [http://localhost:5077/swagger](http://localhost:5077/swagger).

## API endpoints

### Upload a file

`POST /api/files/upload` accepts `multipart/form-data` with one field named `file`. Swagger provides a file picker. Files must be non-empty and no larger than 10 MB. The API generates an object key under `S3:KeyPrefix` and returns the bucket, key, original file name, and size. Objects remain private; the API does not return a public URL.

The application role needs `s3:PutObject` on `arn:aws:s3:::<bucket>/<prefix>/*`. S3 bucket permissions and network policies must also permit the request.

### Check the RDS connection

`GET /api/database/connection` opens the configured PostgreSQL connection and runs `SELECT 1`.

- Success: HTTP 200 with status `connected`.
- Missing or unreachable database configuration: HTTP 503 with status `not connected` and a safe troubleshooting message.

The detailed connection exception is written to the application log, not returned to the caller.

## Project dependencies

- `AWSSDK.S3` — uploads objects to S3
- `Npgsql` — PostgreSQL database connectivity
- `Swashbuckle.AspNetCore` — Swagger document and interactive Swagger UI
