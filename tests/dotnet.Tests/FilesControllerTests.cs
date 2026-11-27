using System.Text;
using Amazon.S3;
using Amazon.S3.Model;
using dotnet.Controllers;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;

namespace dotnet.Tests;

public class FilesControllerTests
{
    private static IConfiguration BuildConfig(
        string? bucket = "dotnet-app-dev-artifacts",
        string? prefix = "training-uploads",
        string? connString = "Host=127.0.0.1;Port=59999;Database=appdb;Username=appadmin;Password=bad;Timeout=1") =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["S3:BucketName"] = bucket,
                ["S3:KeyPrefix"] = prefix,
                ["ConnectionStrings:Rds"] = connString
            })
            .Build();

    private static IFormFile CreateFormFile(string fileName, string content, string? contentType = "application/pdf", long? lengthOverride = null)
    {
        var bytes = Encoding.UTF8.GetBytes(content);
        var mock = new Mock<IFormFile>();
        mock.Setup(f => f.FileName).Returns(fileName);
        mock.Setup(f => f.Length).Returns(lengthOverride ?? bytes.Length);
        mock.Setup(f => f.ContentType).Returns(contentType!);
        mock.Setup(f => f.OpenReadStream()).Returns(() => new MemoryStream(bytes));
        return mock.Object;
    }

    [Fact]
    public async Task Upload_ReturnsBadRequest_WhenFileIsNull()
    {
        var s3 = new Mock<IAmazonS3>();
        var controller = new FilesController(s3.Object, BuildConfig(), NullLogger<FilesController>.Instance);

        var result = await controller.Upload(null, CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task Upload_ReturnsBadRequest_WhenFileIsEmpty()
    {
        var s3 = new Mock<IAmazonS3>();
        var controller = new FilesController(s3.Object, BuildConfig(), NullLogger<FilesController>.Instance);
        var file = CreateFormFile("empty.txt", "", lengthOverride: 0);

        var result = await controller.Upload(file, CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Fact]
    public async Task Upload_ReturnsBadRequest_WhenFileExceeds10Mb()
    {
        var s3 = new Mock<IAmazonS3>();
        var controller = new FilesController(s3.Object, BuildConfig(), NullLogger<FilesController>.Instance);
        var file = CreateFormFile("huge.bin", "x", lengthOverride: (10 * 1024 * 1024) + 1);

        var result = await controller.Upload(file, CancellationToken.None);

        Assert.IsType<BadRequestObjectResult>(result);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("replace-with-bucket")]
    public async Task Upload_Returns503_WhenBucketInvalid(string? bucket)
    {
        var s3 = new Mock<IAmazonS3>();
        var controller = new FilesController(s3.Object, BuildConfig(bucket: bucket), NullLogger<FilesController>.Instance);
        var file = CreateFormFile("doc.pdf", "hello");

        var result = await controller.Upload(file, CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
    }

    [Fact]
    public async Task Upload_Returns503_WhenConnectionStringMissing()
    {
        var s3 = new Mock<IAmazonS3>();
        var controller = new FilesController(s3.Object, BuildConfig(connString: null), NullLogger<FilesController>.Instance);
        var file = CreateFormFile("doc.pdf", "hello");

        var result = await controller.Upload(file, CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
    }

    [Fact]
    public async Task Upload_Returns502_WhenS3UploadThrows()
    {
        var s3 = new Mock<IAmazonS3>();
        s3.Setup(x => x.PutObjectAsync(It.IsAny<PutObjectRequest>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new AmazonS3Exception("Access Denied"));

        var controller = new FilesController(s3.Object, BuildConfig(), NullLogger<FilesController>.Instance);
        var file = CreateFormFile("doc.pdf", "hello");

        var result = await controller.Upload(file, CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(502, obj.StatusCode);
    }

    [Fact]
    public async Task Upload_PerformsCompensatingS3Delete_WhenDbInsertFails()
    {
        var s3 = new Mock<IAmazonS3>();
        s3.Setup(x => x.PutObjectAsync(It.IsAny<PutObjectRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PutObjectResponse());
        s3.Setup(x => x.DeleteObjectAsync(It.IsAny<DeleteObjectRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new DeleteObjectResponse());

        var controller = new FilesController(s3.Object, BuildConfig(prefix: null), NullLogger<FilesController>.Instance);
        var file = CreateFormFile("doc.pdf", "hello", contentType: null);

        var result = await controller.Upload(file, CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(500, obj.StatusCode);
        s3.Verify(x => x.PutObjectAsync(
            It.Is<PutObjectRequest>(r => r.BucketName == "dotnet-app-dev-artifacts" && r.ContentType == "application/octet-stream"),
            It.IsAny<CancellationToken>()), Times.Once);
        s3.Verify(x => x.DeleteObjectAsync(
            It.Is<DeleteObjectRequest>(r => r.BucketName == "dotnet-app-dev-artifacts"),
            It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Upload_Returns500_EvenWhenCompensatingS3DeleteAlsoFails()
    {
        var s3 = new Mock<IAmazonS3>();
        s3.Setup(x => x.PutObjectAsync(It.IsAny<PutObjectRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PutObjectResponse());
        s3.Setup(x => x.DeleteObjectAsync(It.IsAny<DeleteObjectRequest>(), It.IsAny<CancellationToken>()))
            .ThrowsAsync(new AmazonS3Exception("Delete failed"));

        var controller = new FilesController(s3.Object, BuildConfig(prefix: ""), NullLogger<FilesController>.Instance);
        var file = CreateFormFile("doc.pdf", "hello");

        var result = await controller.Upload(file, CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(500, obj.StatusCode);
    }

    [Fact]
    public async Task List_Returns503_WhenConnectionStringMissing()
    {
        var s3 = new Mock<IAmazonS3>();
        var controller = new FilesController(s3.Object, BuildConfig(connString: null), NullLogger<FilesController>.Instance);

        var result = await controller.List(CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
    }

    [Fact]
    public async Task List_Returns500_WhenDatabaseUnreachable()
    {
        var s3 = new Mock<IAmazonS3>();
        var controller = new FilesController(s3.Object, BuildConfig(), NullLogger<FilesController>.Instance);

        var result = await controller.List(CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(500, obj.StatusCode);
    }

    [Fact]
    public async Task Download_Returns503_WhenConnectionStringMissing()
    {
        var s3 = new Mock<IAmazonS3>();
        var controller = new FilesController(s3.Object, BuildConfig(connString: null), NullLogger<FilesController>.Instance);

        var result = await controller.Download(Guid.NewGuid(), CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
    }

    [Fact]
    public async Task Download_Returns500_WhenDatabaseUnreachable()
    {
        var s3 = new Mock<IAmazonS3>();
        var controller = new FilesController(s3.Object, BuildConfig(), NullLogger<FilesController>.Instance);

        var result = await controller.Download(Guid.NewGuid(), CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(500, obj.StatusCode);
    }

    [Fact]
    public void UploadedFileResponse_Constructor_MapsBackwardCompatibleFields()
    {
        var id = Guid.NewGuid();
        var now = DateTime.UtcNow;

        var dto = new UploadedFileResponse(id, "test.pdf", "bucket-1", "prefix/test.pdf", "application/pdf", 123, now);

        Assert.Equal(id, dto.Id);
        Assert.Equal("test.pdf", dto.FileName);
        Assert.Equal("test.pdf", dto.OriginalFileName);
        Assert.Equal("bucket-1", dto.S3BucketName);
        Assert.Equal("bucket-1", dto.Bucket);
        Assert.Equal("prefix/test.pdf", dto.S3ObjectKey);
        Assert.Equal("prefix/test.pdf", dto.Key);
        Assert.Equal(123, dto.FileSize);
        Assert.Equal(123, dto.SizeBytes);
        Assert.Equal(now, dto.UploadedAt);
    }
}
