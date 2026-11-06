using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace dotnet.Controllers;

[ApiController]
[Route("api/database")]
public sealed class DatabaseController(
    IConfiguration configuration,
    ILogger<DatabaseController> logger) : ControllerBase
{
    /// <summary>Checks whether the configured PostgreSQL RDS database accepts a connection.</summary>
    [HttpGet("connection")]
    [ProducesResponseType(typeof(DatabaseConnectionResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(DatabaseConnectionResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> CheckConnection(CancellationToken cancellationToken)
    {
        var connectionString = configuration.GetConnectionString("Rds");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new DatabaseConnectionResponse("not connected", "RDS connection string is not configured."));
        }

        try
        {
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = new NpgsqlCommand("SELECT 1", connection);
            await command.ExecuteScalarAsync(cancellationToken);

            return Ok(new DatabaseConnectionResponse("connected", "PostgreSQL RDS connection succeeded."));
        }
        catch (Exception exception) when (exception is NpgsqlException or TimeoutException)
        {
            logger.LogWarning(exception, "PostgreSQL RDS connection check failed.");
            return StatusCode(StatusCodes.Status503ServiceUnavailable,
                new DatabaseConnectionResponse("not connected", "Could not connect to PostgreSQL RDS. Check the endpoint, credentials, and network access."));
        }
    }
}

public sealed record DatabaseConnectionResponse(string Status, string Message);
