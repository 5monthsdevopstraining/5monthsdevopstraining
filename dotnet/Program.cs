using Amazon;
using Amazon.S3;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var region = builder.Configuration["AWS:Region"] ?? "ap-southeast-2";
builder.Services.AddSingleton<IAmazonS3>(_ => new AmazonS3Client(
    new AmazonS3Config { RegionEndpoint = RegionEndpoint.GetBySystemName(region) }));

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();
app.MapControllers();

app.Run();
