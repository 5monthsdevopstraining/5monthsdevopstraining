using System.Net;
using Microsoft.AspNetCore.Mvc.Testing;

namespace dotnet.Tests;

public class ApiIntegrationTests(WebApplicationFactory<Program> factory) : IClassFixture<WebApplicationFactory<Program>>
{
    [Fact]
    public async Task SwaggerJson_ReturnsOk()
    {
        var client = factory.CreateClient();
        var response = await client.GetAsync("/swagger/v1/swagger.json");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task DatabaseConnectionEndpoint_ReturnsServiceUnavailable_WhenUnconfigured()
    {
        var client = factory.CreateClient();
        var response = await client.GetAsync("/api/database/connection");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }

    [Fact]
    public async Task FilesListEndpoint_ReturnsServiceUnavailable_WhenUnconfigured()
    {
        var client = factory.CreateClient();
        var response = await client.GetAsync("/api/files");
        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
    }

    [Fact]
    public async Task FilesUploadEndpoint_ReturnsBadRequest_WhenNoFileSent()
    {
        var client = factory.CreateClient();
        using var content = new MultipartFormDataContent();
        var response = await client.PostAsync("/api/files/upload", content);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}
