using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.AspNetCore.Mvc;

namespace dotnet.Controllers;

[ApiController]
[Route("api/files")]
public sealed class FilesController(
    IAmazonS3 s3,
    IConfiguration configuration,
    ILogger<FilesController> logger) : ControllerBase
{
    private const long MaxFileSizeBytes = 10 * 1024 * 1024;

    /// <summary>Uploads one file to the configured S3 bucket.</summary>
    [HttpPost("upload")]
    [Consumes("multipart/form-data")]
    [ProducesResponseType(typeof(FileUploadResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
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

        var prefix = configuration["S3:KeyPrefix"]?.Trim('/') ?? "uploads";
        var extension = Path.GetExtension(Path.GetFileName(file.FileName));
        var key = string.IsNullOrEmpty(prefix)
            ? $"{Guid.NewGuid():N}{extension}"
            : $"{prefix}/{Guid.NewGuid():N}{extension}";

        try
        {
            await using var stream = file.OpenReadStream();
            await s3.PutObjectAsync(new PutObjectRequest
            {
                BucketName = bucket,
                Key = key,
                InputStream = stream,
                ContentType = string.IsNullOrWhiteSpace(file.ContentType)
                    ? "application/octet-stream"
                    : file.ContentType
            }, cancellationToken);

            return Ok(new FileUploadResponse(bucket, key, file.FileName, file.Length));
        }
        catch (AmazonS3Exception exception)
        {
            logger.LogError(exception, "S3 upload failed for bucket {Bucket} and key {Key}.", bucket, key);
            return Problem(
                title: "S3 upload failed.",
                detail: "Check the bucket name, AWS credentials, and S3 permissions.",
                statusCode: StatusCodes.Status502BadGateway);
        }
    }

    /// <summary>Checks whether the configured Amazon S3 bucket accepts a connection.</summary>
    [HttpGet("connection")]
    [ProducesResponseType(typeof(S3ConnectionResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(S3ConnectionResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> CheckConnection(CancellationToken cancellationToken)
    {
        var bucket = configuration["S3:BucketName"];
        if (string.IsNullOrWhiteSpace(bucket) || bucket.StartsWith("replace-", StringComparison.OrdinalIgnoreCase))
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new S3ConnectionResponse("not connected", "S3:BucketName is not configured."));
        }

        try
        {
            // Verify bucket existence and access
            var response = await s3.GetBucketLocationAsync(new GetBucketLocationRequest
            {
                BucketName = bucket
            }, cancellationToken);

            return Ok(new S3ConnectionResponse("connected", $"Amazon S3 connection succeeded. Bucket '{bucket}' in region {response.Location?.Value ?? "default"}."));
        }
        catch (AmazonS3Exception exception)
        {
            logger.LogWarning(exception, "Amazon S3 connection check failed for bucket {Bucket}.", bucket);
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new S3ConnectionResponse("not connected", $"Could not connect to S3 bucket '{bucket}'. Error: {exception.Message}"));
        }
        catch (Exception exception)
        {
            logger.LogWarning(exception, "Amazon S3 connection check error for bucket {Bucket}.", bucket);
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new S3ConnectionResponse("not connected", $"Could not connect to S3: {exception.Message}"));
        }
    }
}

public sealed record S3ConnectionResponse(string Status, string Message);

public sealed record FileUploadResponse(string Bucket, string Key, string OriginalFileName, long SizeBytes);
