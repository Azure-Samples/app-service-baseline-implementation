using Azure.Identity;

var builder = WebApplication.CreateBuilder(args);

//var endpoint = Environment.GetEnvironmentVariable("WEBSITE_APP_CONFIGURATION_ENDPOINT");
//var identity = Environment.GetEnvironmentVariable("WEBSITE_APP_CONFIGURATION_MANAGED_IDENTITY");
//Console.WriteLine("This would have been good to know earlier");

//if (string.IsNullOrEmpty(endpoint))
//{
//    throw new ApplicationException($"The Environment Variable WEBSITE_APP_CONFIGURATION_ENDPOINT must be set");
//}
//if (string.IsNullOrEmpty(identity))
//{
//    throw new ApplicationException($"The Environment Variable WEBSITE_APP_CONFIGURATION_MANAGED_IDENTITY must be set");
//}

//builder.Configuration.AddAzureAppConfiguration(options =>
//{
//    options.Connect(new Uri(endpoint), new DefaultAzureCredential(new DefaultAzureCredentialOptions { ManagedIdentityClientId = identity }))
//        .ConfigureKeyVault(kv =>
//        {
//            kv.SetCredential(new DefaultAzureCredential(new DefaultAzureCredentialOptions { ManagedIdentityClientId = identity }));
//        });
//});

// Add services to the container.
builder.Services.AddControllersWithViews();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error");
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();

app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

app.Run();
