using System.Diagnostics;
using System.Text.Json;
using System.Management.Automation;
using OpenAI;
using OpenAI.Chat;

namespace llm_lib;

public class StructuredDataConfig
{
    private const string GeneralSchemaName = "structured-data-extraction";
    private const string SchemaSystemPrompt = """
        You are an expert information extraction assistant that responds with JSON.
        Extract information from the provided text and structure it according to the specified JSON schema.
        Only extract information that is explicitly mentioned in the text. Use null for missing information.
        """;

    public string SystemPrompt { get; set; }
    public ChatResponseFormat JsonResponseFormat { get; }

    internal string SchemaText { get; }
    internal string SchemaFile { get; }

    internal StructuredDataConfig(
        string systemPrompt,
        ChatResponseFormat jsonResponseFormat,
        string schemaText,
        string schemaFile)
    {
        ArgumentException.ThrowIfNullOrEmpty(systemPrompt);
        ArgumentNullException.ThrowIfNull(jsonResponseFormat);

        SystemPrompt = systemPrompt;
        JsonResponseFormat = jsonResponseFormat;

        SchemaText = schemaText;
        SchemaFile = schemaFile;
    }

    internal static string CreateSchemaSystemPrompt(string prompt)
    {
        return string.IsNullOrEmpty(prompt) ? SchemaSystemPrompt : prompt;
    }

    internal static ChatResponseFormat CreateResponseFormatFromSchemaText(string schema, string name = null, string description = null)
    {
        return ChatResponseFormat.CreateJsonSchemaFormat(
            name ?? GeneralSchemaName,
            BinaryData.FromString(schema),
            description);
    }

    internal static ChatResponseFormat CreateResponseFormatFromSchemaFile(string path, string name = null, string description = null)
    {
        using var stream = File.OpenRead(path);
        return ChatResponseFormat.CreateJsonSchemaFormat(
            name ?? GeneralSchemaName,
            BinaryData.FromStream(stream),
            description);
    }
}

[Cmdlet(VerbsCommon.Set, "StructuredDataConfig", DefaultParameterSetName = SchemaTextSet)]
public class SetStructuredDataConfigCommand : PSCmdlet
{
    private const string SchemaTextSet = nameof(Schema);
    private const string SchemaFileSet = nameof(SchemaFile);

    [Parameter]
    [ValidateNotNullOrEmpty]
    public string Prompt { get; set; }

    [Parameter]
    [ValidateNotNullOrEmpty]
    public string SchemaName { get; set; }

    [Parameter]
    [ValidateNotNullOrEmpty]
    public string SchemaDescription { get; set; }

    [Parameter(Mandatory = true, ParameterSetName = SchemaTextSet)]
    public string Schema { get; set; }

    [Parameter(Mandatory = true, ParameterSetName = SchemaFileSet)]
    public string SchemaFile { get; set; }

    protected override void ProcessRecord()
    {
        var responseFormat = ParameterSetName switch
        {
            SchemaTextSet => StructuredDataConfig.CreateResponseFormatFromSchemaText(Schema, SchemaName, SchemaDescription),
            SchemaFileSet => StructuredDataConfig.CreateResponseFormatFromSchemaFile(SchemaFile, SchemaName, SchemaDescription),
            _ => throw new UnreachableException("Code not reachable.")
        };

        var systemPrompt = StructuredDataConfig.CreateSchemaSystemPrompt(Prompt);
        var config = new StructuredDataConfig(systemPrompt, responseFormat, Schema, SchemaFile);

        WriteObject(config);
    }
}

[Cmdlet(VerbsCommon.Get, "StructuredData", DefaultParameterSetName = DefaultSet)]
public class GetStructuredDataCommand : PSCmdlet
{
    private const string DefaultSet = "Default";
    private const string SchemaTextSet = nameof(Schema);
    private const string SchemaFileSet = nameof(SchemaFile);
    private const string DataConfigSet = nameof(DataConfig);

    [Parameter(Mandatory = true, ValueFromPipeline = true)]
    public string InputText { get; set; }

    [Parameter(Mandatory = true, ParameterSetName = DefaultSet)]
    [Parameter(ParameterSetName = SchemaTextSet)]
    [Parameter(ParameterSetName = SchemaFileSet)]
    [ValidateNotNullOrEmpty]
    public string Prompt { get; set; }

    [Parameter(Mandatory = true, ParameterSetName = SchemaTextSet)]
    public string Schema { get; set; }

    [Parameter(Mandatory = true, ParameterSetName = SchemaFileSet)]
    public string SchemaFile { get; set; }

    [Parameter(Mandatory = true, ParameterSetName = DataConfigSet)]
    public StructuredDataConfig DataConfig { get; set; }

    [ThreadStatic]
    private static ChatClient _chatClient;

    [ThreadStatic]
    private static long _timestamp;

    protected override void BeginProcessing()
    {
        var aiEndpoint = AIEndpoint.Singleton;
        if (string.IsNullOrEmpty(aiEndpoint.BaseUrl) || string.IsNullOrEmpty(aiEndpoint.Model) || aiEndpoint.ApiKey is null || aiEndpoint.ApiKey.Length == 0)
        {
            ThrowTerminatingError(new ErrorRecord(
                new InvalidOperationException("AI endpoint not configured. Please call Set-AIEndpoint before using Get-StructuredData."),
                "EndpointNotConfigured",
                ErrorCategory.InvalidOperation,
                null));
        }

        if (_chatClient is null || _timestamp < aiEndpoint.UpdateTimestamp)
        {
            _timestamp = aiEndpoint.UpdateTimestamp;
            var oaiClient = new OpenAIClient(
                new System.ClientModel.ApiKeyCredential(aiEndpoint.GetKeyInPlainText()),
                new OpenAIClientOptions { Endpoint = new Uri(aiEndpoint.BaseUrl) });
            _chatClient = oaiClient.GetChatClient(aiEndpoint.Model);
        }
    }

    protected override void ProcessRecord()
    {
        var responseFormat = ParameterSetName switch
        {
            DefaultSet => ChatResponseFormat.CreateJsonObjectFormat(),
            SchemaTextSet => StructuredDataConfig.CreateResponseFormatFromSchemaText(Schema),
            SchemaFileSet => StructuredDataConfig.CreateResponseFormatFromSchemaFile(SchemaFile),
            DataConfigSet => DataConfig.JsonResponseFormat,
            _ => throw new UnreachableException("Code not reachable.")
        };

        string systemPrompt = ParameterSetName switch
        {
            DefaultSet => $"You are an expert information extraction assistant that responds with JSON.\n{Prompt}",
            DataConfigSet => DataConfig.SystemPrompt,
            _ => StructuredDataConfig.CreateSchemaSystemPrompt(Prompt)
        };

        WriteVerbose($"System Prompt: {systemPrompt}");
        var messages = new List<ChatMessage>
        {
            new SystemChatMessage(systemPrompt),
            new UserChatMessage($"Extract information from the following text:\n\n{InputText}")
        };

        var chatCompletionOptions = new ChatCompletionOptions()
        {
            Temperature = 0f,
            ResponseFormat = responseFormat,
        };

        int retryCnt = 3;
        while (true)
        {
            var completion = _chatClient.CompleteChat(messages, chatCompletionOptions);
            var response = completion.Value.Content[0].Text;

            try
            {
                var jsonDocument = JsonDocument.Parse(response);
                WriteObject(response);
                return;
            }
            catch (JsonException ex)
            {
                if (--retryCnt is 0)
                {
                    break;
                }

                WriteVerbose($"Failed to parse JSON response: {ex.Message}.\nRetry: {3 - retryCnt}");
                continue;
            }
        }

        WriteError(new ErrorRecord(
            new InvalidDataException("Failed to obtain valid JSON from the AI response after 3 attempts."),
            "JsonExtractionFailed",
            ErrorCategory.InvalidData,
            InputText));
    }
}
