using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace dotnet.Controllers;

[ApiController]
[Route("api/files")]
public sealed class FilesController(
    IAmazonS3 s3,
    IConfiguration configuration,
    ILogger<FilesController> logger) : ControllerBase
{
    private const long MaxFileSizeBytes = 10 * 1024 * 1024;
    private static bool _tableInitialized;
    private static readonly SemaphoreSlim _initLock = new(1, 1);

    private async Task EnsureTableCreatedAsync(string connectionString, CancellationToken cancellationToken)
    {
        if (_tableInitialized) return;

        await _initLock.WaitAsync(cancellationToken);
        try
        {
            if (_tableInitialized) return;

            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            const string createTableSql = @"
                CREATE TABLE IF NOT EXISTS uploaded_files (
                    id UUID PRIMARY KEY,
                    file_name VARCHAR(255) NOT NULL,
                    s3_bucket_name VARCHAR(255) NOT NULL,
                    s3_object_key VARCHAR(512) NOT NULL,
                    content_type VARCHAR(100) NOT NULL,
                    file_size BIGINT NOT NULL,
                    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                CREATE INDEX IF NOT EXISTS idx_uploaded_files_uploaded_at ON uploaded_files(uploaded_at DESC);
            ";

            await using var command = new NpgsqlCommand(createTableSql, connection);
            await command.ExecuteNonQueryAsync(cancellationToken);

            _tableInitialized = true;
        }
        finally
        {
            _initLock.Release();
        }
    }

    /// <summary>Uploads one file to S3 and stores metadata in PostgreSQL.</summary>
    [HttpPost("upload")]
    [Consumes("multipart/form-data")]
    [ProducesResponseType(typeof(UploadedFileResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status502BadGateway)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> Upload(
        IFormFile? file,
        CancellationToken cancellationToken)
    {
        if (file is null || file.Length == 0)
        {
            return BadRequest(new { message = "Choose a non-empty file to upload." });
        }

        if (file.Length > MaxFileSizeBytes)
        {
            return BadRequest(new { message = "The maximum upload size is 10 MB." });
        }

        var bucket = configuration["S3:BucketName"];
        if (string.IsNullOrWhiteSpace(bucket) || bucket.StartsWith("replace-", StringComparison.OrdinalIgnoreCase))
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new { message = "Configure S3:BucketName before uploading." });
        }

        var connectionString = configuration.GetConnectionString("Rds");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new { message = "Configure ConnectionStrings:Rds before uploading." });
        }

        var prefix = configuration["S3:KeyPrefix"]?.Trim('/') ?? "uploads";
        var extension = Path.GetExtension(Path.GetFileName(file.FileName));
        var fileId = Guid.NewGuid();
        var key = string.IsNullOrEmpty(prefix)
            ? $"{fileId:N}{extension}"
            : $"{prefix}/{fileId:N}{extension}";

        var contentType = string.IsNullOrWhiteSpace(file.ContentType)
            ? "application/octet-stream"
            : file.ContentType;

        var uploadedAt = DateTime.UtcNow;

        // Step 1: Upload to S3
        try
        {
            await using var stream = file.OpenReadStream();
            await s3.PutObjectAsync(new PutObjectRequest
            {
                BucketName = bucket,
                Key = key,
                InputStream = stream,
                ContentType = contentType
            }, cancellationToken);
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "S3 upload failed for bucket {Bucket} and key {Key}.", bucket, key);
            return Problem(
                title: "S3 upload failed.",
                detail: "Check the bucket name, AWS credentials, and S3 permissions: " + exception.Message,
                statusCode: StatusCodes.Status502BadGateway);
        }

        // Step 2: Ensure Table and Insert Metadata into PostgreSQL
        try
        {
            await EnsureTableCreatedAsync(connectionString, cancellationToken);

            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            const string insertSql = @"
                INSERT INTO uploaded_files (id, file_name, s3_bucket_name, s3_object_key, content_type, file_size, uploaded_at)
                VALUES (@id, @file_name, @s3_bucket_name, @s3_object_key, @content_type, @file_size, @uploaded_at);
            ";

            await using var command = new NpgsqlCommand(insertSql, connection);
            command.Parameters.AddWithValue("id", fileId);
            command.Parameters.AddWithValue("file_name", file.FileName);
            command.Parameters.AddWithValue("s3_bucket_name", bucket);
            command.Parameters.AddWithValue("s3_object_key", key);
            command.Parameters.AddWithValue("content_type", contentType);
            command.Parameters.AddWithValue("file_size", file.Length);
            command.Parameters.AddWithValue("uploaded_at", uploadedAt);

            await command.ExecuteNonQueryAsync(cancellationToken);

            logger.LogInformation("File {FileName} uploaded to S3 ({Key}) and saved in PostgreSQL with ID {Id}", file.FileName, key, fileId);

            return Ok(new UploadedFileResponse(
                fileId,
                file.FileName,
                bucket,
                key,
                contentType,
                file.Length,
                uploadedAt));
        }
        catch (Exception dbException)
        {
            logger.LogError(dbException, "PostgreSQL insert failed for {Key}. Performing compensating S3 delete.", key);
            try
            {
                await s3.DeleteObjectAsync(new DeleteObjectRequest
                {
                    BucketName = bucket,
                    Key = key
                }, cancellationToken);
            }
            catch (Exception s3DeleteEx)
            {
                logger.LogError(s3DeleteEx, "Compensating S3 delete failed for bucket {Bucket} and key {Key}.", bucket, key);
            }

            return Problem(
                title: "Database metadata insertion failed.",
                detail: "The uploaded file was removed from S3 to prevent orphan data: " + dbException.Message,
                statusCode: StatusCodes.Status500InternalServerError);
        }
    }

    /// <summary>Lists all uploaded files recorded in PostgreSQL.</summary>
    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<UploadedFileResponse>), StatusCodes.Status200OK)]
    public async Task<IActionResult> List(CancellationToken cancellationToken)
    {
        var connectionString = configuration.GetConnectionString("Rds");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new { message = "RDS connection string is not configured." });
        }

        try
        {
            await EnsureTableCreatedAsync(connectionString, cancellationToken);

            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            const string selectSql = @"
                SELECT id, file_name, s3_bucket_name, s3_object_key, content_type, file_size, uploaded_at
                FROM uploaded_files
                ORDER BY uploaded_at DESC
                LIMIT 50;
            ";

            await using var command = new NpgsqlCommand(selectSql, connection);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken);

            var files = new List<UploadedFileResponse>();
            while (await reader.ReadAsync(cancellationToken))
            {
                files.Add(new UploadedFileResponse(
                    reader.GetGuid(0),
                    reader.GetString(1),
                    reader.GetString(2),
                    reader.GetString(3),
                    reader.GetString(4),
                    reader.GetInt64(5),
                    reader.GetDateTime(6)));
            }

            return Ok(files);
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Failed to list files from PostgreSQL.");
            return Problem(
                title: "Failed to query files.",
                detail: exception.Message,
                statusCode: StatusCodes.Status500InternalServerError);
        }
    }

    /// <summary>Downloads a previously uploaded file using its database record ID.</summary>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Download(Guid id, CancellationToken cancellationToken)
    {
        var connectionString = configuration.GetConnectionString("Rds");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new { message = "RDS connection string is not configured." });
        }

        try
        {
            await EnsureTableCreatedAsync(connectionString, cancellationToken);

            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            const string selectSql = @"
                SELECT file_name, s3_bucket_name, s3_object_key, content_type
                FROM uploaded_files
                WHERE id = @id;
            ";

            await using var command = new NpgsqlCommand(selectSql, connection);
            command.Parameters.AddWithValue("id", id);

            await using var reader = await command.ExecuteReaderAsync(cancellationToken);
            if (!await reader.ReadAsync(cancellationToken))
            {
                return NotFound(new { message = $"File with ID {id} not found." });
            }

            var fileName = reader.GetString(0);
            var bucket = reader.GetString(1);
            var key = reader.GetString(2);
            var contentType = reader.GetString(3);

            var s3Object = await s3.GetObjectAsync(bucket, key, cancellationToken);
            return File(s3Object.ResponseStream, contentType, fileName);
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Failed to download file with ID {Id}.", id);
            return Problem(
                title: "Failed to download file.",
                detail: exception.Message,
                statusCode: StatusCodes.Status500InternalServerError);
        }
    }
}

public sealed record UploadedFileResponse(
    Guid Id,
    string FileName,
    string S3BucketName,
    string S3ObjectKey,
    string ContentType,
    long FileSize,
    DateTime UploadedAt,
    string Bucket,
    string Key,
    string OriginalFileName,
    long SizeBytes)
{
    public UploadedFileResponse(
        Guid id,
        string fileName,
        string s3BucketName,
        string s3ObjectKey,
        string contentType,
        long fileSize,
        DateTime uploadedAt)
        : this(id, fileName, s3BucketName, s3ObjectKey, contentType, fileSize, uploadedAt, s3BucketName, s3ObjectKey, fileName, fileSize)
    {
    }
}
