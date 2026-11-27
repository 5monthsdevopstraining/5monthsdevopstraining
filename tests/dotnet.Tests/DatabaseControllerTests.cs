using dotnet.Controllers;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;

namespace dotnet.Tests;

public class DatabaseControllerTests
{
    private static IConfiguration BuildConfig(string? connString) =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:Rds"] = connString
            })
            .Build();

    [Fact]
    public async Task CheckConnection_Returns503_WhenConnectionStringMissing()
    {
        var controller = new DatabaseController(BuildConfig(null), NullLogger<DatabaseController>.Instance);

        var result = await controller.CheckConnection(CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
        var body = Assert.IsType<DatabaseConnectionResponse>(obj.Value);
        Assert.Equal("not connected", body.Status);
    }

    [Fact]
    public async Task CheckConnection_Returns503_WhenConnectionStringWhitespace()
    {
        var controller = new DatabaseController(BuildConfig("   "), NullLogger<DatabaseController>.Instance);

        var result = await controller.CheckConnection(CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
    }

    [Fact]
    public async Task CheckConnection_Returns503_WhenDatabaseUnreachable()
    {
        var controller = new DatabaseController(
            BuildConfig("Host=127.0.0.1;Port=59999;Database=appdb;Username=appadmin;Password=bad;Timeout=1"),
            NullLogger<DatabaseController>.Instance);

        var result = await controller.CheckConnection(CancellationToken.None);

        var obj = Assert.IsType<ObjectResult>(result);
        Assert.Equal(503, obj.StatusCode);
        var body = Assert.IsType<DatabaseConnectionResponse>(obj.Value);
        Assert.Equal("not connected", body.Status);
    }
}
