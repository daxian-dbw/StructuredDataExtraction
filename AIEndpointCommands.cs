using System.Security;
using System.Management.Automation;
using System.Runtime.InteropServices;

namespace llm_lib;

public class AIEndpoint
{
    public string BaseUrl { get; private set; }
    public string Model { get; private set; }
    public SecureString ApiKey { get; private set; }

    internal long UpdateTimestamp { get; private set; }
    internal static AIEndpoint Singleton => s_singleton;

    private AIEndpoint() { }
    private static readonly AIEndpoint s_singleton = new();

    internal static void UpdateEndpoint(string baseUrl, string model, SecureString apiKey)
    {
        if (baseUrl == s_singleton.BaseUrl
            && model == s_singleton.Model
            && AreSecureStringsEqual(apiKey, s_singleton.ApiKey))
        {
            return;
        }

        s_singleton.BaseUrl = baseUrl;
        s_singleton.ApiKey = apiKey;
        s_singleton.Model = model;
        s_singleton.UpdateTimestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
    }

    internal string GetKeyInPlainText()
    {
        if (ApiKey == null || ApiKey.Length == 0)
        {
            return string.Empty;
        }

        IntPtr ptr = IntPtr.Zero;
        try
        {
            ptr = Marshal.SecureStringToGlobalAllocUnicode(ApiKey);
            return Marshal.PtrToStringUni(ptr) ?? string.Empty;
        }
        finally
        {
            if (ptr != IntPtr.Zero)
            {
                Marshal.ZeroFreeGlobalAllocUnicode(ptr);
            }
        }
    }

    internal static bool AreSecureStringsEqual(SecureString str1, SecureString str2)
    {
        if (ReferenceEquals(str1, str2))
        {
            return true;
        }

        if (str1 is null || str2 is null)
        {
            return false;
        }

        if (str1.Length != str2.Length)
        {
            return false;
        }

        IntPtr ptr1 = IntPtr.Zero;
        IntPtr ptr2 = IntPtr.Zero;
        try
        {
            ptr1 = Marshal.SecureStringToGlobalAllocUnicode(str1);
            ptr2 = Marshal.SecureStringToGlobalAllocUnicode(str2);

            // Compare the memory content byte by byte
            int byteLength = str1.Length * sizeof(char);
            for (int i = 0; i < byteLength; i++)
            {
                byte byte1 = Marshal.ReadByte(ptr1, i);
                byte byte2 = Marshal.ReadByte(ptr2, i);
                if (byte1 != byte2)
                {
                    return false;
                }
            }

            return true;
        }
        finally
        {
            if (ptr1 != IntPtr.Zero)
            {
                Marshal.ZeroFreeGlobalAllocUnicode(ptr1);
            }

            if (ptr2 != IntPtr.Zero)
            {
                Marshal.ZeroFreeGlobalAllocUnicode(ptr2);
            }
        }
    }
}

[Cmdlet(VerbsCommon.Set, "AIEndpoint")]
public class SetAIEndpointCommand : PSCmdlet
{
    [Parameter]
    public string BaseUrl { get; set; }

    [Parameter(Mandatory = true)]
    public string Model { get; set; }

    [Parameter(Mandatory = true)]
    public SecureString ApiKey { get; set; }

    [Parameter]
    public SwitchParameter PassThru { get; set; }

    protected override void ProcessRecord()
    {
        if (ApiKey.Length is 0)
        {
            throw new ArgumentException("The API key is required to be specified.");
        }

        if (string.IsNullOrEmpty(BaseUrl))
        {
            BaseUrl ??= "https://api.openai.com/v1";
        }
        else if (!Uri.TryCreate(BaseUrl, UriKind.Absolute, out Uri validatedUri) ||
            (validatedUri.Scheme != Uri.UriSchemeHttp && validatedUri.Scheme != Uri.UriSchemeHttps))
        {
            // Validate that BaseUrl is a valid URL.
            throw new ArgumentException($"The BaseUrl '{BaseUrl}' is not a valid HTTP or HTTPS URL.", nameof(BaseUrl));
        }

        AIEndpoint.UpdateEndpoint(BaseUrl, Model, ApiKey);
        if (PassThru)
        {
            WriteObject(AIEndpoint.Singleton);
        }
    }
}

[Cmdlet(VerbsCommon.Get, "AIEndpoint")]
public class GetAIEndpointCommand : PSCmdlet
{
    protected override void ProcessRecord()
    {
        WriteObject(AIEndpoint.Singleton);
    }
}
